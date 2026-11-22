#!/bin/bash
# Prints the files create_release attaches to a ghul release, one a line,
# from the artefacts downloaded into the current directory: the compiler
# package, the Native AOT compiler, the native compilers for x64 and arm64
# and the wasm-built compiler, each archive with its .sha256. All of them
# must be present.
#
# usage: build/release-assets.sh <package version>

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

required "nupkg/ghul.compiler.$package.nupkg"
required "llvm-arm64/ghul-compiler-llvm-aarch64-unknown-linux-musl.tar.gz"
required "llvm-arm64/ghul-compiler-llvm-aarch64-unknown-linux-musl.tar.gz.sha256"
required "aot/ghul-compiler-linux-x64.tar.gz"
required "aot/ghul-compiler-linux-x64.tar.gz.sha256"
required "llvm/ghul-compiler-llvm-x86_64-unknown-linux-musl.tar.gz"
required "llvm/ghul-compiler-llvm-x86_64-unknown-linux-musl.tar.gz.sha256"
required "wasm/ghul-compiler-wasm.tar.gz"
required "wasm/ghul-compiler-wasm.tar.gz.sha256"
