#!/bin/bash
# Checks that the native compiler's --fork-server builds exactly what a cold
# compile of the same arguments builds: for a sample of the execution tests,
# on wasm and llvm, the same output files byte for byte and the same
# diagnostics. One extra build with a different flag must be compiled cold
# by the server, and the server's count of builds served from its snapshot
# must cover every other one.
#
# usage: build/fork-server-equivalence.sh <native compiler> <ghul-runtime> [every]
#
# <ghul-runtime> is a checkout of the runtime, core and runtime trees both.
# Every <every>th test with empty ghulflags, built for both targets, is
# taken (default 40). ghul-llvm
# must be on the PATH.
set -euo pipefail

if [ $# -lt 2 ]; then
    echo "usage: build/fork-server-equivalence.sh <native compiler> <ghul-runtime> [every]" >&2
    exit 2
fi

root=$(cd "$(dirname "$0")/.." && pwd)
compiler=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
runtime=$(cd "$2" && pwd)
every=${3:-40}

work=$(mktemp -d)
[ -n "${FORK_EQUIVALENCE_KEEP:-}" ] || trap 'rm -r "$work"' EXIT

"$root/build/llvm-self-sources.sh" "$work" "$runtime"

tests=()
i=0
for directory in "$root"/integration-tests/execution/*/; do
    i=$((i + 1))
    [ $((i % every)) -eq 0 ] || continue
    if [ -e "$directory/ghulflags" ] && grep -q '[^[:space:]]' "$directory/ghulflags"; then
        continue
    fi
    if [ -e "$directory/targets" ] && ! { grep -qw wasm "$directory/targets" && grep -qw llvm "$directory/targets"; }; then
        continue
    fi
    ls "$directory"/*.ghul > /dev/null 2>&1 || continue
    tests+=("$directory")
done

failures=0

check_target() {
    local target=$1
    local options=(--target "$target")

    if [ "$target" = wasm ]; then
        options+=(--wasm-loader "$runtime/ghul-core/host/loader.mjs")
    fi

    local out=$work/$target
    mkdir -p "$out/server"

    # The server's own diagnostics and each build's reach this script on the
    # coproc's output; its standard output is not part of the protocol.
    coproc SERVER { exec "$compiler" --fork-server "${options[@]}" @"$work/libraries.rsp" -o "$out/server/prog" 2>&1 >/dev/null; }

    # Kept apart from SERVER, which bash unsets when the server exits.
    local from_server to_server
    exec {from_server}<&"${SERVER[0]}" {to_server}>&"${SERVER[1]}"

    local requests=0

    build() {
        local name=$1
        shift

        mkdir -p "$out/cold/$name" "$out/warm/$name"

        printf '%s\n' "$@" -o "$out/cold/$name/prog" > "$out/$name.cold.rsp"
        printf '%s\n' "$@" -o "$out/warm/$name/prog" > "$out/$name.warm.rsp"

        local cold_status=0
        "$compiler" @"$out/$name.cold.rsp" 2> "$out/$name.cold.err" > /dev/null || cold_status=$?

        echo "$out/$name.warm.rsp" >&"$to_server"
        requests=$((requests + 1))

        : > "$out/$name.warm.err"

        local line warm_status=
        while IFS= read -r line <&"$from_server"; do
            if [[ $line == $'\001build-done '* ]]; then
                warm_status=${line#*build-done }
                break
            fi

            printf '%s\n' "$line" >> "$out/$name.warm.err"
        done

        local problem=

        # The two output trees differ only in their directory.
        if [ "$warm_status" != "$cold_status" ]; then
            problem="exit status $warm_status, cold $cold_status"
        elif ! diff <(sed "s|$out/cold/|OUT/|g" "$out/$name.cold.err") <(sed "s|$out/warm/|OUT/|g" "$out/$name.warm.err") > "$out/$name.diff"; then
            problem="diagnostics differ"
        elif ! diff -r "$out/cold/$name" "$out/warm/$name" > /dev/null; then
            problem="output differs"
        fi

        if [ -n "$problem" ]; then
            echo "FAIL $target $name: $problem"
            head -20 "$out/$name.diff" || true
            failures=$((failures + 1))
        fi
    }

    for directory in "${tests[@]}"; do
        build "$(basename "$directory")" "${options[@]}" @"$work/libraries.rsp" "$directory"/*.ghul
    done

    # A flag the snapshot was not compiled with: built cold by the server.
    build "with-a-define" "${options[@]}" --define FORK_SERVER_EQUIVALENCE @"$work/libraries.rsp" "${tests[0]}"/*.ghul

    echo quit >&"$to_server"

    local line summary=
    while IFS= read -r line <&"$from_server"; do
        if [[ $line == $'\001fork-server '* ]]; then
            summary=${line#$'\001'}
        fi
    done

    exec {from_server}<&- {to_server}>&-
    wait "$SERVER_PID" || true

    local expected="fork-server served $((requests - 1)) cold 1"

    if [ "$summary" != "$expected" ]; then
        echo "FAIL $target: the server said '$summary', expected '$expected'"
        failures=$((failures + 1))
    fi

    echo "$target: $requests builds, $summary"
}

check_target llvm
check_target wasm

if [ "$failures" -gt 0 ]; then
    echo "$failures failure(s)"
    exit 1
fi

echo "the fork server's builds match cold builds"
