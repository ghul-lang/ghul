#!/usr/bin/env bash
#
# engine-check.sh — hand every module of the matrix to real engines.
#
# The suite pins bytes; this script is the other half of the matrix's job,
# asking whether the bytes are the ones an engine accepts. It writes a
# throwaway test that dumps each module to a file, runs it, then validates
# every file against each engine it can find and removes the test again.
#
# Engines, each run when it is on the PATH, skipped silently when not:
#   node     - WebAssembly.validate
#   wasmtime - `compile` with exceptions and gc enabled
#
# Usage: wasm/tests/engine-check.sh [output-dir]
#        (default: a fresh directory under /tmp)
#
# Exits nonzero if any module is rejected by any engine present.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="${1:-$(mktemp -d /tmp/wasm-matrix.XXXXXX)}"
mkdir -p "$out"

dump="$here/_engine_dump.ghul"

cleanup() { rm -f "$dump"; }
trap cleanup EXIT

cat > "$dump" <<'GHUL'
namespace Wasm.UnitTests is
    use Wasm.BINARY_WRITER
    use Wasm.Tests.MODULE_MATRIX

    use TestClass = Microsoft.VisualStudio.TestTools.UnitTesting.TestClassAttribute
    use Test = Microsoft.VisualStudio.TestTools.UnitTesting.TestMethodAttribute

    // Written and removed by engine-check.sh; it exists only to dump the
    // matrix where the engines can reach it.
    @TestClass()
    class ENGINE_DUMP_TESTS is
        init() is si

        @Test()
        write__every_module() is
            for name in MODULE_MATRIX.names() do
                let bytes = BINARY_WRITER().write(MODULE_MATRIX.by_name(name))

                let dir = System.Environment.get_environment_variable("WASM_MATRIX_DIR")

                IO.File.write_all_bytes("{dir ?? "/tmp/wasm-matrix"}/{name}.wasm", bytes)
            od
        si
    si
si
GHUL

echo "writing the matrix to $out"
WASM_MATRIX_DIR="$out" dotnet test "$here/wasm-tests.ghulproj" \
    --filter "FullyQualifiedName~ENGINE_DUMP" --nologo -v q >/dev/null 2>&1

count=$(ls "$out"/*.wasm 2>/dev/null | wc -l)
if [ "$count" -eq 0 ]; then
    echo "engine-check: no modules were written; the test run failed" >&2
    exit 1
fi

failures=0

check_node() {
    command -v node >/dev/null 2>&1 || return 0
    local engine="node"
    for f in "$out"/*.wasm; do
        local name; name="$(basename "$f" .wasm)"
        if node -e 'process.exit(WebAssembly.validate(require("fs").readFileSync(process.argv[1])) ? 0 : 1)' "$f"; then
            echo "  $engine  ok       $name"
        else
            echo "  $engine  REJECT   $name"
            failures=$((failures + 1))
        fi
    done
}

check_wasmtime() {
    local wasmtime; wasmtime="$(command -v wasmtime || true)"
    [ -n "$wasmtime" ] || return 0
    local engine="wasmtime"
    for f in "$out"/*.wasm; do
        local name; name="$(basename "$f" .wasm)"
        if "$wasmtime" compile -W exceptions -W gc -o /dev/null "$f" >/dev/null 2>&1; then
            echo "  $engine  ok       $name"
        else
            echo "  $engine  REJECT   $name"
            failures=$((failures + 1))
        fi
    done
}

check_node
check_wasmtime

echo
echo "$count modules, $failures rejection(s)"
[ "$failures" -eq 0 ]
