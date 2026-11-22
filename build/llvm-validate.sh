#!/usr/bin/env bash
#
# llvm-validate.sh - hand every module the llvm integration tests build
# to LLVM.
#
# ghul-test builds and runs each test built for the llvm target where
# ghul-llvm is present, but a test that is a library build, or one whose
# compilation is the subject, never reaches LLVM there. This script builds
# each test's module again as a library and has ghul-llvm verify and
# compile it to an object, so a module the compiler accepts is one LLVM
# accepts too. Any host's compiler writes the same module, so it can be the
# native compiler or the .NET one.
#
# ghul-llvm is found on the PATH unless GHUL_LLVM names it.
#
# Usage: build/llvm-validate.sh [test-root [compiler command...]]
#        (defaults: integration-tests, and `dotnet publish/ghul.dll` after
#        `dotnet publish --output publish/`; run from the repository root)
#
# Fails when ghul-llvm is missing, when a test that should build a module
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
ghul_llvm="${GHUL_LLVM:-ghul-llvm}"

if ! command -v "$ghul_llvm" >/dev/null 2>&1; then
    echo "llvm-validate: $ghul_llvm is not on the PATH; set GHUL_LLVM" >&2
    exit 1
fi

if [ $# -eq 0 ] && [ ! -f "${compiler[1]}" ]; then
    echo "llvm-validate: no compiler at ${compiler[1]}; publish first" >&2
    exit 1
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

checked=0
failed=0

# The command ghul-test builds each llvm test with, one JSON line each, from
# the configuration for this compiler: a .NET one is handed the reference
# assemblies, and one hosted elsewhere is not. A test whose flags name the
# target builds in its own directory; one that runs under llvm through
# build_targets builds in a copy under .targets/ and is left to ghul-test.
if [[ "${compiler[*]}" == *.dll ]]; then
    configuration=llvm
else
    configuration=host-llvm
fi

if ! dotnet ghul-test --config "$configuration" --compiler "${compiler[*]}" --commands "$scratch/commands.jsonl" "$root" >"$scratch/ghul-test.out" 2>&1; then
    echo "llvm-validate: ghul-test could not list the build commands:" >&2
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


    checked=$((checked + 1))

    if ! (cd "$dir" && "$executable" "${options[@]}" --library "${sources[@]}" -o "$out/module.ll") >"$out/compiler.out" 2>&1; then
        echo "llvm-validate: $dir did not compile:" >&2
        head -5 "$out/compiler.out" >&2
        failed=$((failed + 1))
        continue
    fi

    if ! "$ghul_llvm" --emit=obj "$out/module.ll" -o "$out/module.o" >"$out/ghul-llvm.out" 2>&1; then
        echo "llvm-validate: LLVM rejected the module built from $dir:" >&2
        head -10 "$out/ghul-llvm.out" >&2
        failed=$((failed + 1))
    fi
done < <(node "$(dirname "$0")/test-commands.mjs" "$scratch/commands.jsonl" --target llvm --in-place)

echo "llvm-validate: $checked modules checked, $failed failed"

[ "$failed" = 0 ]
