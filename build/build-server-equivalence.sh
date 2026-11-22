#!/bin/bash
# Checks that --build-server builds exactly what a cold compile of the same
# arguments builds, however many builds the server has run before: a sample
# of the execution tests is built one after another by one server, on wasm
# and llvm, and each output is compared byte for byte, with its diagnostics,
# against a compile in a process of its own. The first test is built again
# at the end, so a build that follows every other one is compared too.
#
# usage: build/build-server-equivalence.sh <compiler> <ghul-runtime> [every]
#
# <compiler> is the native compiler or a .NET ghul.dll, run with dotnet.
# <ghul-runtime> is a checkout of the runtime, core and runtime trees both.
# Every <every>th test whose test.json is `{}` is taken (default 40). An llvm
# build writes its module's text and links nothing, so ghul-llvm is not needed.
set -euo pipefail

if [ $# -lt 2 ]; then
    echo "usage: build/build-server-equivalence.sh <compiler> <ghul-runtime> [every]" >&2
    exit 2
fi

root=$(cd "$(dirname "$0")/.." && pwd)
compiler_path=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
runtime=$(cd "$2" && pwd)
every=${3:-40}

if [[ $compiler_path == *.dll ]]; then
    compiler=(dotnet "$compiler_path")
else
    compiler=("$compiler_path")
fi

work=$(mktemp -d)
[ -n "${BUILD_EQUIVALENCE_KEEP:-}" ] || trap 'rm -r "$work"' EXIT

"$root/build/llvm-self-sources.sh" "$work" "$runtime"

tests=()
i=0
for directory in "$root"/integration-tests/execution/*/; do
    i=$((i + 1))
    [ $((i % every)) -eq 0 ] || continue
    [ "$(tr -d '[:space:]' < "$directory/test.json" 2> /dev/null)" = '{}' ] || continue
    ls "$directory"/*.ghul > /dev/null 2>&1 || continue
    tests+=("${directory%/}")
done

failures=0

check_target() {
    local target=$1
    local options=(--target "$target")

    if [ "$target" = wasm ]; then
        options+=(--wasm-loader "$runtime/ghul-core/host/loader.mjs")
    fi

    local out=$work/$target
    mkdir -p "$out"

    # Each build's diagnostics reach this script on the coproc's output; the
    # server's standard output is not part of the protocol.
    coproc SERVER { exec "${compiler[@]}" --build-server 2>&1 >/dev/null; }

    # Kept apart from SERVER, which bash unsets when the server exits.
    local from_server to_server
    exec {from_server}<&"${SERVER[0]}" {to_server}>&"${SERVER[1]}"

    local builds=0

    build() {
        local name=$1
        local directory=$2

        local files=()
        mapfile -t files < <(ls "$directory"/*.ghul)

        local kind
        for kind in cold warm; do
            local output=$out/$kind/$name
            mkdir -p "$output"

            {
                printf '%s\n' "${options[@]}" @"$work/libraries.rsp"

                if [ "$target" = llvm ]; then
                    printf '%s\n' --llvm-output "$output/module.ll" --llvm-no-link
                fi

                printf '%s\n' -o "$output/prog" "${files[@]}"
            } > "$out/$name.$kind.rsp"
        done

        local cold_status=0
        "${compiler[@]}" @"$out/$name.cold.rsp" 2> "$out/$name.cold.err" > /dev/null || cold_status=$?

        printf '%s\n' "$out/$name.warm.rsp" >&"$to_server"
        builds=$((builds + 1))

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
            cat "$out/$name.warm.err" > "$out/$name.diff"
        elif ! diff <(sed "s|$out/cold/|OUT/|g" "$out/$name.cold.err") <(sed "s|$out/warm/|OUT/|g" "$out/$name.warm.err") > "$out/$name.diff"; then
            problem="diagnostics differ"
        elif ! diff -r <(cd "$out/cold/$name" && find . -type f | sort | xargs cat | sed "s|$out/cold/|OUT/|g") \
                       <(cd "$out/warm/$name" && find . -type f | sort | xargs cat | sed "s|$out/warm/|OUT/|g") > "$out/$name.diff"; then
            problem="output differs"
        fi

        if [ -n "$problem" ]; then
            echo "FAIL $target $name (build $builds): $problem"
            head -20 "$out/$name.diff" | cut -c1-200 || true
            failures=$((failures + 1))
        fi

        rm -rf "$out/cold/$name" "$out/warm/$name"
    }

    local directory
    for directory in "${tests[@]}"; do
        build "$(basename "$directory")" "$directory"
        echo "$target: $builds builds"
    done

    build "$(basename "${tests[0]}")-again" "${tests[0]}"

    echo quit >&"$to_server"
    exec {from_server}<&- {to_server}>&-
    wait "$SERVER_PID" || true

    echo "$target: $builds builds compared"
}

check_target wasm
check_target llvm

if [ "$failures" -gt 0 ]; then
    echo "$failures failure(s)"
    exit 1
fi

echo "the build server's builds match cold builds"
