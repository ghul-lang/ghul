#!/bin/bash
# Prints the compiler options a test's test.json asks for, as ghul-test passes
# them for a build of the test for `target` (default dotnet): `--type-check`
# for check_only, `--library` for library, then its flags, then `--optimise N`
# where the target is llvm. Prints nothing for a directory with no test.json.
#
# Usage: build/test-flags.sh <test-directory> [target]

set -euo pipefail

settings="$1/test.json"
target="${2:-dotnet}"

[ -f "$settings" ] || exit 0

jq -r --arg target "$target" '
    [
        (if .check_only then "--type-check" else empty end),
        (if .library then "--library" else empty end),
        (.flags // empty),
        (if $target == "llvm" and .optimise != null then "--optimise \(.optimise)" else empty end)
    ] | join(" ")' "$settings"
