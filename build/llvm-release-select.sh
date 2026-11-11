#!/bin/bash
# Chooses the llvm-built compiler a release carries for one platform, where
# the release ships from the chain (LLVM_RELEASE_FROM=chain in ci.yml): the
# chain's settled build where it matches the .NET-seeded one, the
# .NET-seeded build where there is no chain to ship, and nothing where the
# two disagree or the chain is not reproducible.
#
# usage: build/llvm-release-select.sh <triple> <input dir> <output dir>
#
# The input directory holds what the run produced for the platform, any of
# which may be missing:
#   chain-status      how llvm-chain.sh ended: settled, stage0-failed,
#                     unsettled, or no-stage0 where no release carried a
#                     compiler to start from
#   chain/            the chain's archive, ghul-compiler-llvm-<triple>.tar.gz
#                     and its .sha256
#   chain.sha256      the chain's module and executable, hashed
#   bootstrap/        llvm_bootstrap's archive and its .sha256
#   bootstrap.sha256  llvm_bootstrap's pass 2, hashed the same way
#
# The chosen archive and its .sha256 are copied to the output directory.
# Where the release says something about the platform, the line is written
# to <output dir>/notes.txt. Exits 1 where the two builds disagree, and 0
# otherwise, including where nothing is shipped for another reason.

set -euo pipefail

if [ $# -ne 3 ]; then
    echo "usage: build/llvm-release-select.sh <triple> <input dir> <output dir>" >&2
    exit 2
fi

triple=$1
in=$2
out=$3

archive=ghul-compiler-llvm-$triple.tar.gz

case "$triple" in
    x86_64-*) platform=linux-x64 ;;
    aarch64-*) platform=linux-arm64 ;;
    *) platform=$triple ;;
esac

mkdir -p "$out"

note() {
    echo "$1" >> "$out/notes.txt"
    echo "::warning::$1"
}

ship() {
    cp "$in/$1/$archive" "$in/$1/$archive.sha256" "$out/"
    echo "shipping the $1 build of the llvm-built compiler for $platform"
}

status=$(cat "$in/chain-status" 2>/dev/null || echo missing)

has_bootstrap() {
    [ -f "$in/bootstrap/$archive" ] && [ -f "$in/bootstrap.sha256" ]
}

case "$status" in
    settled)
        if ! has_bootstrap; then
            note "This release has no llvm-built compiler for $platform: its .NET-seeded build did not succeed, so the chain's build could not be checked against it."
        elif ! cmp -s "$in/chain.sha256" "$in/bootstrap.sha256"; then
            note "This release has no llvm-built compiler for $platform: the chain and the .NET-seeded build gave different compilers."
            echo "::error::the chain and the .NET-seeded build give different compilers for $triple: one route miscompiles"
            cat "$in/chain.sha256" "$in/bootstrap.sha256"
            exit 1
        else
            ship chain
        fi
        ;;

    unsettled)
        note "This release has no llvm-built compiler for $platform: building it from the released compiler did not reach a fixed point."
        ;;

    no-stage0 | stage0-failed | missing)
        case "$status" in
            no-stage0) reason="no release carried an llvm-built compiler for it to start from" ;;
            stage0-failed) reason="the released llvm-built compiler could not build this source" ;;
            missing) reason="the chain did not run" ;;
        esac

        if has_bootstrap; then
            note "The llvm-built compiler for $platform in this release is built from .NET alone: $reason."
            ship bootstrap
        else
            note "This release has no llvm-built compiler for $platform: $reason, and its .NET-seeded build did not succeed."
        fi
        ;;

    *)
        echo "::error::unknown chain status for $triple: $status"
        exit 2
        ;;
esac
