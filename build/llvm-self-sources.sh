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

# A compiler built for a target other than .NET has no assembly resource to
# carry the wasm loader, so its text is compiled in as a string, in place of
# the committed file that has none.
{
    echo 'namespace IR.WasmGC is'
    echo '    @IF.not.dotnet()'
    echo '    class WASMGC_LOADER_TEXT is'
    echo '        text: string? static =>'
    # One literal for each line, which run together into one string: a
    # single literal of the whole file would be longer than the compiler
    # reads as one token.
    awk '{ gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\{/, "{{"); gsub(/\}/, "}}"); gsub(/\t/, "\\t"); printf "            \"%s\\n\"\n", $0 }' "$root/src/ir/wasmgc/loader.mjs"
    echo '    si'
    echo 'si'
} > "$output/wasmgc_loader_text.ghul"

grep -vxF "$root/src/ir/wasmgc/wasmgc_loader_text.ghul" "$output/sources.rsp" > "$output/sources.rsp.tmp"
echo "$output/wasmgc_loader_text.ghul" >> "$output/sources.rsp.tmp"
mv "$output/sources.rsp.tmp" "$output/sources.rsp"

# A native build of the compiler reports the version GHUL_NATIVE_VERSION
# names, through a copy of
# src/driver/native_build.ghul compiled in place of the committed one.
if [ -n "${GHUL_NATIVE_VERSION:-}" ]; then
    case "$GHUL_NATIVE_VERSION" in
        *[!A-Za-z0-9.+-]*)
            echo "GHUL_NATIVE_VERSION is not a version: $GHUL_NATIVE_VERSION" >&2
            exit 2
            ;;
    esac

    cat > "$output/native_build.ghul" <<EOF
namespace Driver is
    @IF.not.dotnet()
    class NATIVE_BUILD is
        version: string static => "$GHUL_NATIVE_VERSION"

        @IF.wasm()
        host: string static => "wasm"

        @IF.llvm()
        host: string static => "llvm"
    si
si
EOF

    committed="$root/src/driver/native_build.ghul"

    grep -vxF "$committed" "$output/sources.rsp" > "$output/sources.rsp.tmp"
    echo "$output/native_build.ghul" >> "$output/sources.rsp.tmp"
    mv "$output/sources.rsp.tmp" "$output/sources.rsp"
fi
