#!/bin/bash
# Writes the response files that compile the compiler's own source for the
# llvm target: libraries.rsp names the runtime library's sources, both its
# core and its runtime trees, and sources.rsp the compiler's. Shared by
# llvm-self-type-check.sh and llvm-bootstrap.sh.
#
# usage: build/llvm-self-sources.sh <output directory> <ghul-runtime>

set -euo pipefail

if [ $# -ne 2 ]; then
    echo "usage: build/llvm-self-sources.sh <output directory> <ghul-runtime>" >&2
    exit 2
fi

root=$(cd "$(dirname "$0")/.." && pwd)

output=$1
runtime=$(cd "$2" && pwd)

mkdir -p "$output"

{
    echo --library-source
    echo "ghul-runtime@$(tr -d '[:space:]' < "$runtime/VERSION")=$runtime"
    find "$runtime/ghul-core/src" "$runtime/ghul-runtime/src" -name '*.ghul' | sort
} > "$output/libraries.rsp"

for directory in src wasm/src llvm/src analysis-protocol/src; do
    find "$root/$directory" -name '*.ghul' -not -path '*/bin/*' -not -path '*/obj/*'
done | sort > "$output/sources.rsp"

