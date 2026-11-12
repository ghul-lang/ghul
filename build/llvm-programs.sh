#!/usr/bin/env bash
#
# llvm-programs.sh - check that the programs the llvm integration tests
# built are fully static, by running each in an image with nothing in it.
#
# An llvm build links the program against musl and libghul statically, so
# it should need nothing from the machine it runs on: no dynamic loader, no
# shared libraries, no files. `collect` gathers each program ghul-test kept
# (run with GHUL_TEST_KEEP_ARTIFACTS set) with its arguments, input and
# expected output and exit status. `run` copies them into a `FROM scratch`
# image and runs each there, with no network, comparing what it writes to
# standard output and the status it exits with against its test's.
#
# Usage: build/llvm-programs.sh collect <test-root> <dir>
#        build/llvm-programs.sh run <dir>
#
# `run` needs docker. It fails when a program does not start, or writes or
# exits other than its test expects.

set -uo pipefail

usage() {
    echo "usage: build/llvm-programs.sh collect <test-root> <dir> | run <dir>" >&2
    exit 2
}

collect() {
    local root="$1" out="$2" count=0

    mkdir -p "$out"

    while IFS= read -r program; do
        local dir name

        dir="$(dirname "$program")"
        name="$(printf '%s' "${dir#"$root"/}" | tr '/' '_')"

        # A session is answered as the program prompts, which only the test
        # runner does; the suite has already run it.
        if [ -f "$dir/run.session" ]; then
            continue
        fi

        mkdir -p "$out/$name"
        cp "$program" "$out/$name/program"

        for file in run.args run.in run.expected run.exit.expected; do
            if [ -f "$dir/$file" ]; then
                cp "$dir/$file" "$out/$name/$file"
            fi
        done

        count=$((count + 1))
    done < <(find "$root" -name binary.exe -type f | sort)

    echo "llvm-programs: collected $count programs"

    [ "$count" -gt 0 ]
}

run() {
    local dir failed=0 count=0

    dir="$(cd "$1" && pwd)"
    image="ghul-llvm-programs:$$"

    printf 'FROM scratch\nCOPY . /programs/\n' | docker build -q -t "$image" -f - "$dir" >/dev/null || exit 1
    trap 'docker image rm -f "$image" >/dev/null 2>&1' EXIT

    for test in "$dir"/*/; do
        local name input args=() status expected

        name="$(basename "$test")"
        input=/dev/null
        count=$((count + 1))

        if [ -f "$test/run.in" ]; then
            input="$test/run.in"
        fi

        if [ -f "$test/run.args" ]; then
            mapfile -t args < "$test/run.args"
        fi

        docker run --rm -i --network none "$image" "/programs/$name/program" "${args[@]}" \
            < "$input" > "$test/run.out" 2> "$test/run.err"
        status=$?

        expected=0

        if [ -f "$test/run.exit.expected" ]; then
            expected="$(tr -d '[:space:]' < "$test/run.exit.expected")"
        fi

        if [ "$status" != "$expected" ]; then
            echo "llvm-programs: $name exited with $status, expected $expected" >&2
            head -5 "$test/run.err" >&2
            failed=$((failed + 1))
        elif [ -f "$test/run.expected" ] && ! diff -u "$test/run.expected" "$test/run.out" >&2; then
            echo "llvm-programs: $name wrote other output than its run.expected" >&2
            failed=$((failed + 1))
        fi
    done

    echo "llvm-programs: $count run in an empty image, $failed failed"

    [ "$failed" = 0 ]
}

case "${1:-}" in
    collect) [ $# -eq 3 ] || usage; collect "$2" "$3" ;;
    run) [ $# -eq 2 ] || usage; run "$2" ;;
    *) usage ;;
esac
