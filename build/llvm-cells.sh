#!/usr/bin/env bash
#
# llvm-cells.sh - build the scenarios in cell-tests as cells
# of one session, load them into the cell host one after another, and compare
# what they print with each scenario's run.expected.
#
# A scenario is a directory of namespace-less source files, one a cell, in the
# order of their names. Cell N is compiled against the N-1 before it
# (--cell-link N-1), written as a shared object by ghul-llvm --emit=cell, and
# loaded by ghul-host after them, as a session would.
#
# Usage: build/llvm-cells.sh <ghul.dll> <ghul-llvm dir> <host dir> [scenario...]
#
# <ghul.dll> is the compiler to test, <ghul-llvm dir> and <host dir> are the
# unpacked releases (each holding bin/), and ghul-core and ghul-runtime are
# read from libraries/ghul-core and libraries/ghul-runtime, or from
# GHUL_CORE and GHUL_RUNTIME.
#
# With GHUL_CELLS_CAPTURE set, a scenario that runs writes what it printed as
# its run.expected, to be read before it is committed.

set -uo pipefail

if [ $# -lt 3 ]; then
    echo "usage: build/llvm-cells.sh <ghul.dll> <ghul-llvm dir> <host dir> [scenario...]" >&2
    exit 2
fi

compiler="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
tool="$(cd "$2" && pwd)/bin/ghul-llvm"
host="$(cd "$3" && pwd)/bin/ghul-host"
shift 3

root="$(cd "$(dirname "$0")/.." && pwd)"
core="${GHUL_CORE:-$root/libraries/ghul-core}"
runtime="${GHUL_RUNTIME:-$root/libraries/ghul-runtime}"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# The libraries are source: their root and version, then each source file.
{
    echo "--library-source"
    echo "ghul-core@$(tr -d '[:space:]' < "$core/VERSION")=$core"
    (cd "$core" && find src -name '*.ghul' | sort | sed "s#^#$core/#")
    echo "--library-source"
    echo "ghul-runtime@$(tr -d '[:space:]' < "$runtime/VERSION")=$runtime"
    (cd "$runtime" && find ghul-runtime/src -name '*.ghul' | sort | sed "s#^#$runtime/#")
} > "$scratch/libraries.rsp"

scenarios=("$@")

if [ ${#scenarios[@]} -eq 0 ]; then
    for dir in "$root"/cell-tests/*/; do
        scenarios+=("$(basename "$dir")")
    done
fi

failures=0

for scenario in "${scenarios[@]}"; do
    dir="$root/cell-tests/$scenario"
    work="$scratch/$scenario"
    mkdir -p "$work"

    cells=()
    objects=()
    built=true

    for source in $(ls "$dir"/*.ghul | sort); do
        cells+=("$source")
        name="$(basename "$source" .ghul)"

        if ! dotnet "$compiler" --target llvm --cell-link $(( ${#cells[@]} - 1 )) \
                --llvm-output "$work/$name.ll" --llvm-no-link -o "$work/$name.out" \
                "${cells[@]}" "@$scratch/libraries.rsp" > "$work/$name.compile" 2>&1 \
            || ! "$tool" --emit=cell -O0 "$work/$name.ll" -o "$work/$name.so" > "$work/$name.emit" 2>&1; then
            echo "FAILED: $scenario: $name did not build" >&2
            cat "$work/$name.compile" "$work/$name.emit" 2>/dev/null | head -20 | sed 's/^/    /' >&2
            built=false
            break
        fi

        objects+=("$work/$name.so")
    done

    if ! $built; then
        failures=$((failures + 1))
        continue
    fi

    "$host" "${objects[@]}" > "$work/run.out" 2> "$work/run.err"
    status=$?

    if [ -n "${GHUL_CELLS_CAPTURE:-}" ] && [ "$status" -eq 0 ]; then
        cp "$work/run.out" "$dir/run.expected"
    fi

    if [ "$status" -ne 0 ] || ! diff -u "$dir/run.expected" "$work/run.out" > "$work/run.diff"; then
        echo "FAILED: $scenario: exited $status" >&2
        head -20 "$work/run.diff" "$work/run.err" 2>/dev/null >&2
        failures=$((failures + 1))
    else
        echo "ok: $scenario"
    fi
done

[ "$failures" -eq 0 ]
