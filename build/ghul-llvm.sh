#!/usr/bin/env bash
#
# ghul-llvm.sh - fetch the ghul-llvm release the llvm target is tested
# with, as a user's build fetches it, and print the path of its executable.
#
# ghul-llvm is the assembler, optimiser and linker an llvm build hands its
# module to, with the C runtime and libghul it links against. The latest
# release is downloaded from GitHub, checked against the sha256 published
# beside it, and unpacked into <dir>; nothing else is needed on the machine
# to build or run a program.
#
# Usage: build/ghul-llvm.sh <dir>
#
# Prints the absolute path of bin/ghul-llvm, for GHUL_LLVM or the PATH.

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: build/ghul-llvm.sh <dir>" >&2
    exit 2
fi

triple=x86_64-unknown-linux-musl
archive="ghul-llvm-$triple.tar.gz"
url="https://github.com/ghul-lang/ghul-llvm/releases/latest/download/$archive"

mkdir -p "$1"
dir="$(cd "$1" && pwd)"

# Retried where GitHub answers with an error or the connection drops, so a
# release asset that is briefly unavailable doesn't fail the build. What
# arrives is checked against its digest below before anything is unpacked.
fetch() {
    curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 --connect-timeout 30 "$@"
}

fetch -o "$dir/$archive" "$url"
fetch -o "$dir/$archive.sha256" "$url.sha256"

(cd "$dir" && sha256sum --check --quiet "$archive.sha256") >&2

tar -xzf "$dir/$archive" -C "$dir"
rm "$dir/$archive" "$dir/$archive.sha256"

echo "$dir/ghul-llvm-$triple/bin/ghul-llvm"
