#!/usr/bin/env bash
#
# wasm-validate.sh - hand every module the wasm integration tests build
# to an engine.
#
# ghul-test compiles each test under integration-tests/wasm and compares
# what the compiler said and the text form it wrote, but it has no
# engine, and it deletes a passing test's module. So a module the tests
# accept may still be one an engine rejects. This script builds each
# test's module again, with the compiler in publish/, and asks Node
# about it through WebAssembly.validate.
#
# Usage: build/wasm-validate.sh [test-root]
#        (default: integration-tests/wasm; run from the repository root
#        after `dotnet publish --output publish/`)
#
# Fails when Node is missing, when a test that should build a module
# does not, or when any module is rejected.

set -uo pipefail

root="${1:-integration-tests/wasm}"
compiler="$(pwd)/publish/ghul.dll"

if ! command -v node >/dev/null 2>&1; then
    echo "wasm-validate: node is not on the PATH" >&2
    exit 1
fi

if [ ! -f "$compiler" ]; then
    echo "wasm-validate: no compiler at $compiler; publish first" >&2
    exit 1
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

checked=0
failed=0

while IFS= read -r flags_file; do
    dir="$(cd "$(dirname "$flags_file")" && pwd)"

    if [ -e "$dir/fail.expected" ] || compgen -G "$dir/disabled*" >/dev/null; then
        continue
    fi

    out="$scratch/$checked"
    mkdir -p "$out"

    read -r -a flags < "$flags_file"

    if ! (cd "$out" && dotnet "$compiler" "${flags[@]}" -o module.wasm "$dir"/*.ghul) >"$out/compiler.out" 2>&1; then
        echo "wasm-validate: $dir did not compile:" >&2
        head -5 "$out/compiler.out" >&2
        failed=$((failed + 1))
    elif ! node -e '
        const bytes = require("fs").readFileSync(process.argv[1]);
        new WebAssembly.Module(bytes);
    ' "$out/module.wasm" 2>"$out/validate.err"; then
        echo "wasm-validate: $dir: $(grep -m1 CompileError "$out/validate.err" || head -1 "$out/validate.err")" >&2
        failed=$((failed + 1))
    fi

    checked=$((checked + 1))
done < <(find "$root" -name ghulflags | sort)

echo "wasm-validate: $checked modules checked, $failed failed"

[ "$failed" -eq 0 ]
