#!/usr/bin/env bash
#
# llvm-repl.sh - a read-eval-print loop on the llvm target, built from cells.
#
# Each cell read from standard input is compiled as the next cell of a session
# (--cell-link), written as a shared object by ghul-llvm --emit=cell, and handed
# to one long-running ghul-host, which loads it beside the cells before it and
# runs it. Everything an earlier cell printed, held or changed stays in the
# host for as long as it runs, so a name a cell defines is there for the next.
#
# A cell is the lines up to one that holds only ";;". Cells are named c1, c2,
# ... and refer to each other the way a session's cells do: `use c1.name`.
#
# Usage: build/llvm-repl.sh <ghul.dll> <ghul-llvm dir> <host dir>
#
# The runtime library, core and runtime sources both, is read from
# libraries/ghul-runtime, or from GHUL_RUNTIME. With
# GHUL_REPL_TIMING set, the time each step of a cell takes is written to
# standard error.

set -uo pipefail

if [ $# -ne 3 ]; then
    echo "usage: build/llvm-repl.sh <ghul.dll> <ghul-llvm dir> <host dir>" >&2
    exit 2
fi

compiler="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
tool="$(cd "$2" && pwd)/bin/ghul-llvm"
host="$(cd "$3" && pwd)/bin/ghul-host"

root="$(cd "$(dirname "$0")/.." && pwd)"
runtime="${GHUL_RUNTIME:-$root/libraries/ghul-runtime}"

work="$(mktemp -d)"
trap 'kill "$server" 2>/dev/null; rm -rf "$work"' EXIT

{
    echo "--library-source"
    echo "ghul-runtime@$(tr -d '[:space:]' < "$runtime/VERSION")=$runtime"
    (cd "$runtime" && find ghul-core/src ghul-runtime/src -name '*.ghul' | sort | sed "s#^#$runtime/#")
} > "$work/libraries.rsp"

mkfifo "$work/commands"

# The host's standard output is this loop's, so a cell's output is shown as it
# comes. The line it writes after each cell tells this loop that one is done.
mkfifo "$work/done"

# Opened for reading and writing, which does not wait for the other end.
exec 7<> "$work/commands"
exec 8<> "$work/done"

"$host" --serve "$work/commands" > "$work/done" &
server=$!

now() { date +%s.%N; }

cells=()
count=0
text=""

run_cell() {
    count=$((count + 1))
    local name="c$count"

    printf '%s' "$text" > "$work/$name.ghul"
    cells+=("$work/$name.ghul")

    local started compiled emitted
    started="$(now)"

    if ! dotnet "$compiler" --target llvm --cell-link $((count - 1)) \
            --llvm-output "$work/$name.ll" --llvm-no-link -o "$work/$name.out" \
            "${cells[@]}" "@$work/libraries.rsp" > "$work/$name.compile" 2>&1; then
        sed 's/^/  /' "$work/$name.compile" >&2
        unset 'cells[-1]'
        count=$((count - 1))
        return
    fi

    compiled="$(now)"

    if ! "$tool" --emit=cell -O0 "$work/$name.ll" -o "$work/$name.so" 2> "$work/$name.emit"; then
        cat "$work/$name.emit" >&2
        unset 'cells[-1]'
        count=$((count - 1))
        return
    fi

    emitted="$(now)"

    echo "$work/$name.so" >&7

    local line
    while IFS= read -r line <&8; do
        case "$line" in
        $'\001'cell-done*) break ;;
        *) printf '%s\n' "$line" ;;
        esac
    done

    if [ -n "${GHUL_REPL_TIMING:-}" ]; then
        local finished
        finished="$(now)"
        printf '[%s: compile %.2fs, emit %.2fs, load and run %.2fs]\n' "$name" \
            "$(echo "$compiled - $started" | bc)" "$(echo "$emitted - $compiled" | bc)" \
            "$(echo "$finished - $emitted" | bc)" >&2
    fi
}

while IFS= read -r line; do
    if [ "$line" = ";;" ]; then
        run_cell
        text=""
    else
        text+="$line"$'\n'
    fi
done

if [ -n "$text" ]; then
    run_cell
fi

echo quit >&7
