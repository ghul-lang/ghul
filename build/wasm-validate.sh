#!/usr/bin/env bash
#
# wasm-validate.sh - hand every module the wasm integration tests build
# to an engine.
#
# ghul-test compiles each test built for the wasm target and compares
# what the compiler said and the text form it wrote, but it has no
# engine, and it deletes a passing test's module. So a module the tests
# accept may still be one an engine rejects. This script builds each
# test's module again and asks Node about it through WebAssembly.validate.
# Any host's compiler writes the same module, so it can be the native
# compiler or the .NET one.
#
# Usage: build/wasm-validate.sh [test-root [compiler command...]]
#        (defaults: integration-tests, and `dotnet publish/ghul.dll` after
#        `dotnet publish --output publish/`; run from the repository root)
#
# Fails when Node is missing, when a test that should build a module
# does not, or when any module is rejected.

set -uo pipefail

root="${1:-integration-tests}"
if [ $# -gt 0 ]; then
    shift
fi
if [ $# -gt 0 ]; then
    compiler=("$@")
else
    compiler=(dotnet "$(pwd)/publish/ghul.dll")
fi

if ! command -v node >/dev/null 2>&1; then
    echo "wasm-validate: node is not on the PATH" >&2
    exit 1
fi

if [ $# -eq 0 ] && [ ! -f "${compiler[1]}" ]; then
    echo "wasm-validate: no compiler at ${compiler[1]}; publish first" >&2
    exit 1
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
: > "$scratch/loader.mjs"

checked=0
failed=0

# The command ghul-test builds each wasm test with, one JSON line each, from
# the configuration for this compiler: a .NET one is handed the reference
# assemblies, and one hosted elsewhere is not. A test whose flags name the
# target builds in its own directory; one that runs under wasm through
# build_targets builds in a copy under .targets/ and is left to ghul-test.
if [[ "${compiler[*]}" == *.dll ]]; then
    configuration=local
else
    configuration=host-wasm
fi

if ! dotnet ghul-test --config "$configuration" --compiler "${compiler[*]}" --commands "$scratch/commands.jsonl" "$root" >"$scratch/ghul-test.out" 2>&1; then
    echo "wasm-validate: ghul-test could not list the build commands:" >&2
    tail -5 "$scratch/ghul-test.out" >&2
    exit 1
fi

# read_command: reads one command test-commands.mjs wrote into test,
# target, dir, executable, output, options and sources.
read_command() {
    local count i value
    IFS= read -r -d '' test || return 1
    IFS= read -r -d '' target
    IFS= read -r -d '' dir
    IFS= read -r -d '' executable
    IFS= read -r -d '' output
    options=()
    IFS= read -r -d '' count
    for ((i = 0; i < count; i++)); do IFS= read -r -d '' value; options+=("$value"); done
    sources=()
    IFS= read -r -d '' count
    for ((i = 0; i < count; i++)); do IFS= read -r -d '' value; sources+=("$value"); done
}

while read_command; do

    if [ -e "$dir/fail.expected" ] || compgen -G "$dir/disabled*" >/dev/null; then
        continue
    fi

    out="$scratch/$checked"
    mkdir -p "$out"


    # Only the module is checked, so a test that names no loader is given
    # an empty one: the compiler needs one to write an executable.
    if [[ " ${options[*]} " != *" --wasm-loader "* ]]; then
        options+=(--wasm-loader "$scratch/loader.mjs")
    fi

    if ! (cd "$dir" && "$executable" "${options[@]}" "${sources[@]}" -o "$out/module.wasm") >"$out/compiler.out" 2>&1; then
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
done < <(node "$(dirname "$0")/test-commands.mjs" "$scratch/commands.jsonl" --target wasm --in-place)

echo "wasm-validate: $checked modules checked, $failed failed"

[ "$failed" -eq 0 ]
