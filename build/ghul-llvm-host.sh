#!/usr/bin/env bash
#
# ghul-llvm-host.sh - fetch the cell host from the latest ghul-llvm release
# and print the directory it is unpacked into.
#
# The host loads the cells a session is built from (see `--cell-link` and
# build/llvm-cells.sh). It is a glibc program, with the collector, the unwinder
# and the runtime library linked into it, so nothing else is needed on the
# machine to run it.
#
# Usage: build/ghul-llvm-host.sh <dir>
#
# Prints the absolute path of the directory holding bin/ghul-host.

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: build/ghul-llvm-host.sh <dir>" >&2
    exit 2
fi

triple=x86_64-unknown-linux-gnu
archive="ghul-llvm-host-$triple.tar.gz"
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

echo "$dir/ghul-llvm-host-$triple"
