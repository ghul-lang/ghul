#!/usr/bin/env bash
#
# llvm-unit-tests.sh - build the compiler's unit tests on the ghul-testing
# runner for llvm, and run them.
#
# Usage: build/llvm-unit-tests.sh <work> <ghul-testing> <compiler command...>
#
# <work> holds the libraries.rsp and sources.rsp that llvm-self-sources.sh
# writes, the runtime and the compiler's own sources; the tests are compiled
# with those, the sources under unit-tests-native/src and ghul-testing's,
# into <work>/unit-tests/unit-tests, which runs every test and exits with the
# runner's status. The compiler links with the ghul-llvm on the PATH or in
# GHUL_LLVM. Arguments for the runner go in UNIT_TEST_ARGUMENTS.
set -euo pipefail

if [ $# -lt 3 ]; then
    echo "usage: build/llvm-unit-tests.sh <work> <ghul-testing> <compiler command...>" >&2
    exit 2
fi

root=$(cd "$(dirname "$0")/.." && pwd)
work=$1
testing=$(cd "$2" && pwd)
shift 2

directory=$work/unit-tests
mkdir -p "$directory"

{
    cat "$work/libraries.rsp"
    echo --library-source
    echo "ghul-testing@$(tr -d '[:space:]' < "$testing/VERSION")=$testing"
    find "$testing/src" -name '*.ghul' | sort
} > "$directory/libraries.rsp"

{
    cat "$work/sources.rsp"
    find "$root/unit-tests-native/src" -name '*.ghul' | sort
} > "$directory/sources.rsp"

start=$(date +%s)

# The tests' own entry runs, rather than the compiler's. They are built
# unoptimised: optimising takes three quarters of an -O2 build (about two
# minutes) and saves the run a few milliseconds, and the llvm bootstrap
# already builds and checks the optimised compiler.
if ! "$@" --target llvm --llvm-parallel-gc --rtti-roots --underscore-access legacy --optimise 0 --entry unit_tests_entry -o "$directory/unit-tests" @"$directory/libraries.rsp" @"$directory/sources.rsp" > "$directory/build.log" 2>&1; then
    grep -v ': warn: ' "$directory/build.log" || true
    echo "the unit tests failed to build"
    exit 1
fi

echo "unit tests built: $(( $(date +%s) - start ))s"

# shellcheck disable=SC2086
"$directory/unit-tests" --format text ${UNIT_TEST_ARGUMENTS:-}
