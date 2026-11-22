#!/usr/bin/env bash
#
# llvm-gaps.sh - the integration tests tagged llvm-gap: those that do not
# pass on llvm yet, which CI builds for .NET instead. The list may only
# shrink.
#
# Usage: build/llvm-gaps.sh list            the tagged tests, one a line
#        build/llvm-gaps.sh check <ref>     fail if any test is tagged that
#                                           is not tagged at <ref>
#
# Run from the repository root.

set -euo pipefail

# The tagged tests at the given ref, or in the working tree when none is.
tagged() {
    if [ $# -gt 0 ]; then
        git grep -lw --full-name llvm-gap "$1" -- 'integration-tests/**/tags' | sed -e "s|^$1:||"
    else
        git grep -lw --full-name --untracked llvm-gap -- 'integration-tests/**/tags'
    fi | sed -e 's|/tags$||' | LC_ALL=C sort
}

case "${1:-}" in
list)
    tagged
    ;;
check)
    [ $# -eq 2 ] || { echo "usage: build/llvm-gaps.sh check <ref>" >&2; exit 2; }
    if ! git cat-file -e "$2:build/llvm-gaps.sh" 2>/dev/null; then
        echo "$2 has no llvm-gap list yet: $(tagged | wc -l) tests tagged llvm-gap"
        exit 0
    fi
    added="$(LC_ALL=C comm -13 <(tagged "$2") <(tagged))"
    if [ -n "$added" ]; then
        echo "tagged llvm-gap here but not at $2; fix the test on llvm instead:" >&2
        echo "$added" >&2
        exit 1
    fi
    echo "$(tagged | wc -l) tests tagged llvm-gap, none added"
    ;;
*)
    echo "usage: build/llvm-gaps.sh list | check <ref>" >&2
    exit 2
    ;;
esac
