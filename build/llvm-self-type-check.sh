#!/bin/bash
# Type-checks the compiler's own source for the llvm target, against the
# core library and runtime sources a native build compiles in. A gap in
# either, or a .NET-only declaration left uncarved, fails here rather than
# at the next native build of the compiler.
#
# usage: build/llvm-self-type-check.sh [<compiler dll> [<ghul-runtime>]]
#
# The defaults are publish/ghul.dll and the runtime library checkout under
# libraries/, where CI puts it.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

compiler=${1:-$root/publish/ghul.dll}
runtime=${2:-$root/libraries/ghul-runtime}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

"$root/build/llvm-self-sources.sh" "$work" "$runtime"

echo "type-checking $(wc -l < "$work/sources.rsp") files for llvm with $compiler"

cd "$root"

set +e
output=$(dotnet "$compiler" --target llvm --type-check --underscore-access legacy @"$work/libraries.rsp" @"$work/sources.rsp" 2>&1)
status=$?
set -e

# Warnings are the .NET build's too, and reported there; what fails here is
# an error.
printf '%s\n' "$output" | grep -v ': warn: ' || true

exit $status
