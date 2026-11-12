#!/bin/bash
# Checks that the compiler reproduces itself on the wasm target, as
# llvm-bootstrap.sh does on llvm: the compiler builds a wasm compiler from
# its own source, that compiler, run by Node, builds the same source again,
# and the two passes must write the same module and the same loader. The
# second pass's compiler must then pass the analysis tests in the bootstrap
# category.
#
# usage: build/wasm-bootstrap.sh [<compiler dll> [<ghul-runtime>]]
#
# The defaults are publish/ghul.dll and the runtime library checkout under
# libraries/, where CI puts it. Node 24 or later has to be on the PATH;
# NODE_OPTIONS passes it options. The passes are written to a temporary
# directory, or to WASM_BOOTSTRAP_DIR where it is set, which is then kept.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

compiler=${1:-$root/publish/ghul.dll}
runtime=${2:-$root/libraries/ghul-runtime}

if [ -n "${WASM_BOOTSTRAP_DIR:-}" ]; then
    work=$WASM_BOOTSTRAP_DIR
    mkdir -p "$work"
else
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
fi

"$root/build/llvm-self-sources.sh" "$work" "$runtime"

cd "$root"

# Builds the compiler into <directory>/ghul.wasm and ghul.mjs. Both passes
# use the same names, since the loader finds its module by its own name.
build() {
    local name=$1
    local directory=$work/$name
    shift

    mkdir -p "$directory"

    local start=$(date +%s)

    # The version the built compiler reports: GHUL_NATIVE_VERSION, which CI
    # sets, or 0.0.0-local where it is unset.
    local version=()

    if [ -n "${GHUL_NATIVE_VERSION:-}" ]; then
        version=(--version "$GHUL_NATIVE_VERSION")
    fi

    if ! "$@" --target wasm --wasm-loader "$runtime/ghul-core/host/loader.mjs" --rtti-roots --underscore-access legacy "${version[@]}" -o "$directory/ghul" @"$work/libraries.rsp" @"$work/sources.rsp" > "$work/$name.log" 2>&1; then
        grep -v ': warn: ' "$work/$name.log" || true
        echo "$name failed"
        exit 1
    fi

    echo "$name: $(( $(date +%s) - start ))s"
}

build pass-1 dotnet "$compiler"
build pass-2 node "$work/pass-1/ghul.mjs"

status=0

for file in ghul.wasm ghul.mjs; do
    if cmp -s "$work/pass-1/$file" "$work/pass-2/$file"; then
        echo "$file is identical"
    else
        echo "$file differs"
        status=1
    fi
done

# The second pass's compiler is the one released, so it must serve analysis
# mode: the analysis tests in the bootstrap category run against it.
if ! ANALYSIS_TESTS_ON_DIR="$work/pass-2" "$root/build/analysis-tests-on.sh" wasm "$compiler" "$runtime" -- --filter TestCategory=bootstrap > "$work/analysis-tests.log" 2>&1; then
    cat "$work/analysis-tests.log"
    echo "analysis mode failed"
    status=1
else
    echo "analysis mode answers"
fi

# A function declared extern is an import the program's caller supplies, by
# name. The program is built by the wasm-built compiler and run with them.
mkdir -p "$work/extern"

if node "$work/pass-2/ghul.mjs" --target wasm --wasm-loader "$runtime/ghul-core/host/loader.mjs" -o "$work/extern/program" @"$work/libraries.rsp" "$root/build/wasm-externs/test.ghul" > "$work/extern.log" 2>&1 &&
    node "$root/build/wasm-externs/run.mjs" "$work/extern/program.mjs" > "$work/extern.out" 2>> "$work/extern.log" &&
    cmp -s "$work/extern.out" "$root/build/wasm-externs/expected.txt"; then
    echo "extern functions are supplied by the caller"
else
    cat "$work/extern.log" "$work/extern.out" 2>/dev/null
    echo "extern functions were not supplied by the caller"
    status=1
fi

exit $status
