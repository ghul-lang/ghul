#!/usr/bin/env bash
#
# unit-tests-alone.sh - runs each unit test class on its own and lists the
# ones that fail that way.
#
# The unit suite runs in one process, so a test class can pass only because
# another class ran first and left behind state it depends on: a container,
# a static, a fixture another test set up. Run on its own, such a class
# fails. This finds them.
#
# Usage: build/unit-tests-alone.sh [-j <jobs>] [-o <dir>] [<class-name-pattern>]
#
# Builds the unit tests once, then runs every class, <jobs> at a time
# (default: the number of processors), and prints each class that fails
# alone. Exits non-zero if any does. -o keeps each failing class's test
# output in <dir>/<class>.log. A pattern limits the run to the classes whose
# names contain it.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

jobs=$(nproc)
pattern=""
keep=""

while [ $# -gt 0 ]; do
    case "$1" in
        -j) jobs="$2"; shift 2 ;;
        -o) keep="$2"; shift 2 ;;
        -*) echo "unknown option: $1" >&2; exit 2 ;;
        *) pattern="$1"; shift ;;
    esac
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Each test class, fully qualified: the file's namespace, then the name of
# the class declared after each @TestClass().
for file in $(grep -rl '@TestClass()' unit-tests/src --include='*.ghul'); do
    namespace=$(sed -n 's/^namespace \([A-Za-z0-9_.]*\) is.*/\1/p' "$file" | head -n 1)
    grep -A2 '@TestClass()' "$file" |
        sed -n 's/^ *class \([A-Za-z0-9_]*\).*/\1/p' |
        while read -r class; do
            echo "$namespace.$class"
        done
done | sort -u | grep -F -- "$pattern" > "$work/classes" || true

count=$(wc -l < "$work/classes")
echo "building the unit tests"
dotnet build unit-tests -nologo -v q > "$work/build.log" 2>&1 || { cat "$work/build.log"; exit 1; }

echo "running $count classes, $jobs at a time"

run_one() {
    local class="$1" work="$2"
    local log="$work/$class.log"

    if dotnet test unit-tests --no-build --nologo \
        --filter "ClassName=$class" \
        --results-directory "$work/results/$class" > "$log" 2>&1; then
        rm -f "$log"
    elif grep -q 'No test matches the given testcase filter' "$log"; then
        echo "unmatched: $class"
    else
        echo "fails alone: $class"
    fi
}
export -f run_one

start=$(date +%s)
xargs -P "$jobs" -I{} bash -c 'run_one "$@"' _ {} "$work" < "$work/classes" | sort > "$work/report" || true
elapsed=$(( $(date +%s) - start ))

cat "$work/report"

if [ -n "$keep" ]; then
    mkdir -p "$keep"
    find "$work" -maxdepth 1 -name '*.log' ! -name build.log -exec cp {} "$keep"/ \;
fi
failures=$(grep -c '^fails alone' "$work/report" || true)
echo "$failures of $count classes fail alone (${elapsed}s)"

[ "$failures" -eq 0 ]
