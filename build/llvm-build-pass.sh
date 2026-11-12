#!/bin/bash
# Builds the compiler for llvm from its own source, as one pass of
# llvm-bootstrap.sh or one stage of llvm-chain.sh: into <work>/<name>/ghul,
# keeping the module as <work>/<name>/ghul.ll. Every pass and stage is
# built by this one command line, so two routes that should produce the
# same compiler are compared on their compilers alone.
#
# usage: build/llvm-build-pass.sh <work> <name> <compiler command...>
#
# <work> holds libraries.rsp and sources.rsp, as build/llvm-self-sources.sh
# writes them. The build's output goes to <work>/<name>.log, and is shown
# only where the build fails.

set -euo pipefail

if [ $# -lt 3 ]; then
    echo "usage: build/llvm-build-pass.sh <work> <name> <compiler command...>" >&2
    exit 2
fi

work=$1
name=$2
shift 2

directory=$work/$name

mkdir -p "$directory"

start=$(date +%s)

# The version the built compiler reports: GHUL_NATIVE_VERSION, which CI
# sets, or 0.0.0-local where it is unset.
version=()

if [ -n "${GHUL_NATIVE_VERSION:-}" ]; then
    version=(--version "$GHUL_NATIVE_VERSION")
fi

# Every pass uses the same names, since the module's file name is recorded
# in the executable.
if ! "$@" --target llvm --llvm-parallel-gc --rtti-roots --underscore-access legacy "${version[@]}" --llvm-output "$directory/ghul.ll" -o "$directory/ghul" @"$work/libraries.rsp" @"$work/sources.rsp" > "$work/$name.log" 2>&1; then
    grep -v ': warn: ' "$work/$name.log" || true
    echo "$name failed"
    exit 1
fi

echo "$name: $(( $(date +%s) - start ))s"
