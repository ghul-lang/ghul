#!/bin/bash
# Checks that the compiler reproduces itself on the llvm target, as
# bootstrap.sh does on .NET: the compiler builds a native compiler from its
# own source, that native compiler builds the same source again, and the
# two passes must write the same LLVM module and the same executable.
#
# usage: build/llvm-bootstrap.sh [<compiler dll> [<ghul-runtime>]]
#
# The defaults are publish/ghul.dll and the runtime library checkout under
# libraries/, where CI puts it. ghul-llvm has to be on the PATH, or named
# by GHUL_LLVM. The passes are written to a temporary directory, or to
# LLVM_BOOTSTRAP_DIR where it is set, which is then kept.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

compiler=${1:-$root/publish/ghul.dll}
runtime=${2:-$root/libraries/ghul-runtime}

if [ -n "${LLVM_BOOTSTRAP_DIR:-}" ]; then
    work=$LLVM_BOOTSTRAP_DIR
    mkdir -p "$work"
else
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
fi

"$root/build/llvm-self-sources.sh" "$work" "$runtime"

cd "$root"

# Builds the compiler into <directory>/ghul, keeping its module as
# <directory>/ghul.ll. Both passes use the same names, since the module's
# file name is recorded in the executable.
build() {
    local name=$1
    local directory=$work/$name
    shift

    mkdir -p "$directory"

    local start=$(date +%s)

    if ! "$@" --target llvm --underscore-access legacy --llvm-output "$directory/ghul.ll" -o "$directory/ghul" @"$work/libraries.rsp" @"$work/sources.rsp" > "$work/$name.log" 2>&1; then
        grep -v ': warn: ' "$work/$name.log" || true
        echo "$name failed"
        exit 1
    fi

    echo "$name: $(( $(date +%s) - start ))s"
}

build pass-1 dotnet "$compiler"
build pass-2 "$work/pass-1/ghul"

status=0

if cmp -s "$work/pass-1/ghul.ll" "$work/pass-2/ghul.ll"; then
    echo "the LLVM modules are identical"
else
    echo "the LLVM modules differ:"
    diff "$work/pass-1/ghul.ll" "$work/pass-2/ghul.ll" | head -40 || true
    status=1
fi

if cmp -s "$work/pass-1/ghul" "$work/pass-2/ghul"; then
    echo "the executables are identical"
else
    echo "the executables differ"
    status=1
fi

exit $status
