#!/bin/bash
# Prints the files create_release attaches to a ghul release, one a line,
# from the artefacts downloaded into the current directory: the compiler
# package, the Native AOT, llvm-built and wasm-built compiler archives,
# each archive with its .sha256.
#
# usage: build/release-assets.sh <package version>
#
# The llvm-built archives are listed where present, under llvm/ and
# llvm-arm64/: a release built from the chain can lack one, and says so in
# its notes. Everything else must be present.

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: build/release-assets.sh <package version>" >&2
    exit 2
fi

package=$1

required() {
    if [ ! -f "$1" ]; then
        echo "release-assets: $1 is missing" >&2
        exit 1
    fi

    echo "./$1"
}

optional() {
    if [ -f "$1" ]; then
        echo "./$1"
        echo "./$1.sha256"
    fi
}

required "nupkg/ghul.compiler.$package.nupkg"
optional "llvm-arm64/ghul-compiler-llvm-aarch64-unknown-linux-musl.tar.gz"
required "aot/ghul-compiler-linux-x64.tar.gz"
required "aot/ghul-compiler-linux-x64.tar.gz.sha256"
optional "llvm/ghul-compiler-llvm-x86_64-unknown-linux-musl.tar.gz"
required "wasm/ghul-compiler-wasm.tar.gz"
required "wasm/ghul-compiler-wasm.tar.gz.sha256"
