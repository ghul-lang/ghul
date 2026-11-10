#!/bin/bash
# Runs the analysis-tests suite against the compiler built for another
# target: the wasm-built compiler under Node, or the llvm-built one as a
# native executable. The compiler is built from this checkout's source by
# the .NET compiler, as wasm-bootstrap.sh and llvm-bootstrap.sh build their
# first pass, and is given the runtime library's sources in place of the
# assemblies the .NET-built analyser reads.
#
# usage: build/analysis-tests-on.sh <wasm|llvm> [<compiler dll> [<ghul-runtime>]] [-- <dotnet test arguments>]
#
# The defaults are publish/ghul.dll and the runtime library checkout under
# libraries/, where CI puts it. The wasm target needs Node 24 or later on
# the PATH; the llvm target needs ghul-llvm on the PATH or named by
# GHUL_LLVM. The built compiler is written to a temporary directory, or to
# ANALYSIS_TESTS_ON_DIR where it is set, which is then kept; where that
# directory already holds a built compiler it is used as it is.
#
# Tests of what an analyser reading library sources does not advertise or
# cannot do skip themselves; they are reported as skipped, not passed.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

if [ $# -lt 1 ] || { [ "$1" != wasm ] && [ "$1" != llvm ]; }; then
    echo "usage: build/analysis-tests-on.sh <wasm|llvm> [<compiler dll> [<ghul-runtime>]] [-- <dotnet test arguments>]" >&2
    exit 2
fi

target=$1
shift

compiler=$root/publish/ghul.dll
runtime=$root/libraries/ghul-runtime

if [ $# -gt 0 ] && [ "$1" != -- ]; then
    compiler=$1
    shift
fi

if [ $# -gt 0 ] && [ "$1" != -- ]; then
    runtime=$1
    shift
fi

if [ $# -gt 0 ] && [ "$1" = -- ]; then
    shift
fi

if [ -n "${GHUL_LLVM:-}" ]; then
    export PATH="$(dirname "$GHUL_LLVM"):$PATH"
fi

if [ -n "${ANALYSIS_TESTS_ON_DIR:-}" ]; then
    work=$ANALYSIS_TESTS_ON_DIR
    mkdir -p "$work"
else
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
fi

"$root/build/llvm-self-sources.sh" "$work" "$runtime"

# Analysis mode reads requests by reflection, which a target other than
# .NET answers from the descriptions --rtti compiles in.
case $target in
    wasm)
        analyser=$work/ghul.mjs
        build=(--target wasm --wasm-loader "$runtime/ghul-core/host/loader.mjs" -o "$work/ghul")
        ;;
    llvm)
        analyser=$work/ghul
        build=(--target llvm -o "$work/ghul")
        ;;
esac

if [ ! -e "$analyser" ]; then
    start=$(date +%s)

    if ! dotnet "$compiler" "${build[@]}" --rtti --underscore-access legacy @"$work/libraries.rsp" @"$work/sources.rsp" > "$work/build.log" 2>&1; then
        grep -v ': warn: ' "$work/build.log" || true
        echo "building the $target analyser failed"
        exit 1
    fi

    echo "built the $target analyser: $(( $(date +%s) - start ))s"
fi

cd "$root"

# A run held by an analyser that never answers is stopped after five
# minutes without progress, naming the test it was in.
ANALYSIS_TESTS_ANALYSER=$analyser \
ANALYSIS_TESTS_TARGET=$target \
ANALYSIS_TESTS_LIBRARIES=$work/libraries.rsp \
    dotnet test analysis-tests --blame-hang --blame-hang-timeout 5m "$@"
