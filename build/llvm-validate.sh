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
target=llvm
test_flags="$(cd "$(dirname "$0")" && pwd)/test-flags.sh"
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

# Every test under $root whose test.json flags name `--target $target`, printed
# as its directory and its flags, tab-separated. A test that runs under the
# target through build_targets is left to ghul-test, run by a configuration
# whose run_targets names llvm. A `.targets` directory holds ghul-test's own
# copies of a test, not tests.
tests_for_target() {
    find "$root" -name test.json -not -path "*/.targets/*" | sort | while IFS= read -r settings_file; do
        dir="$(dirname "$settings_file")"
        flags="$("$test_flags" "$dir" "$target")"

        if [[ " $flags " == *" --target $target "* ]]; then
            printf "%s\t%s\n" "$dir" "$flags"
        fi
    done
}

while IFS=$'\t' read -r dir flags_text; do
    dir="$(cd "$dir" && pwd)"

    if [ -e "$dir/fail.expected" ] || compgen -G "$dir/disabled*" >/dev/null; then
        continue
    fi

    out="$scratch/$checked"
    mkdir -p "$out"

    read -r -a flags <<< "$flags_text"

    checked=$((checked + 1))

    if ! (cd "$dir" && "${compiler[@]}" "${flags[@]}" --library -o "$out/module.ll" ./*.ghul) >"$out/compiler.out" 2>&1; then
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
done < <(tests_for_target)

echo "llvm-validate: $checked modules checked, $failed failed"

[ "$failed" = 0 ]
