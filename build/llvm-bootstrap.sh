#!/bin/bash
# Checks that the compiler reproduces itself on the llvm target, as
# bootstrap.sh does on .NET: the compiler builds a native compiler from its
# own source, that native compiler builds the same source again, and the
# two passes must write the same LLVM module and the same executable. The
# second pass's compiler must then pass the analysis tests in the bootstrap
# category.
#
# usage: build/llvm-bootstrap.sh [<compiler dll> [<ghul-runtime>]]
#
# The defaults are publish/ghul.dll and the runtime library checkout under
# libraries/, where CI puts it. ghul-llvm has to be on the PATH, or named
# by GHUL_LLVM. The passes are written to a temporary directory, or to
# LLVM_BOOTSTRAP_DIR where it is set, which is then kept.
#
# With LLVM_BOOTSTRAP_DIR set, LLVM_BOOTSTRAP_STEP splits the work in two:
# `pass-1` builds the first pass and stops, so it can be used while the
# second is built, and `rest` builds the second pass from the first pass
# already in the directory, <dir>/pass-1/ghul, and makes every check. The
# two steps can run on different machines: each lists the sources itself.
# Unset, it does both.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

compiler=${1:-$root/publish/ghul.dll}
runtime=${2:-$root/libraries/ghul-runtime}

step=${LLVM_BOOTSTRAP_STEP:-all}

case "$step" in
    all|pass-1|rest) ;;
    *) echo "LLVM_BOOTSTRAP_STEP must be pass-1 or rest, not $step" >&2; exit 2 ;;
esac

if [ "$step" != all ] && [ -z "${LLVM_BOOTSTRAP_DIR:-}" ]; then
    echo "LLVM_BOOTSTRAP_STEP needs LLVM_BOOTSTRAP_DIR, where the first pass is kept" >&2
    exit 2
fi

if [ -n "${LLVM_BOOTSTRAP_DIR:-}" ]; then
    work=$LLVM_BOOTSTRAP_DIR
    mkdir -p "$work"
else
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
fi

cd "$root"

build() {
    "$root/build/llvm-build-pass.sh" "$work" "$@"
}

"$root/build/llvm-self-sources.sh" "$work" "$runtime"

if [ "$step" != rest ]; then
    build pass-1 dotnet "$compiler"
fi

if [ "$step" = pass-1 ]; then
    exit 0
fi

if [ ! -x "$work/pass-1/ghul" ]; then
    echo "there is no first pass in $work to build the second from" >&2
    exit 1
fi

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

# The second pass's compiler is the one released, so it must serve analysis
# mode: the analysis tests in the bootstrap category run against it.
if ! ANALYSIS_TESTS_ON_DIR="$work/pass-2" "$root/build/analysis-tests-on.sh" llvm "$compiler" "$runtime" -- --filter TestCategory=bootstrap > "$work/analysis-tests.log" 2>&1; then
    cat "$work/analysis-tests.log"
    echo "analysis mode failed"
    status=1
else
    echo "analysis mode answers"
fi

exit $status
