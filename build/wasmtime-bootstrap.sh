#!/bin/bash
# Checks that the compiler reproduces itself on the wasm target under the
# wasmtime embedder, as wasm-bootstrap.sh does under Node: the compiler builds
# a wasm compiler from its own source, that compiler, run by the embedder,
# builds the same source again, and the passes must write the same module and
# the same loader.
#
# usage: build/wasmtime-bootstrap.sh [<compiler dll> [<ghul-runtime>]]
#
# The defaults are publish/ghul.dll and the runtime library checkout under
# libraries/, where CI puts it. The embedder has to be on the PATH as
# wasmtime-host, or named by GHUL_WASMTIME_HOST. The passes are written to a
# temporary directory, or to WASMTIME_BOOTSTRAP_DIR where it is set, which is
# then kept. The build command can be shown without running anything by
# setting WASMTIME_BOOTSTRAP_DRY_RUN.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

compiler=${1:-$root/publish/ghul.dll}
runtime=${2:-$root/libraries/ghul-runtime}

embedder=${GHUL_WASMTIME_HOST:-$(command -v wasmtime-host || true)}
if [ -z "$embedder" ]; then
    echo "wasmtime-bootstrap: no embedder; put wasmtime-host on the PATH or set GHUL_WASMTIME_HOST" >&2
    exit 2
fi

if [ -n "${WASMTIME_BOOTSTRAP_DIR:-}" ]; then
    work=$WASMTIME_BOOTSTRAP_DIR
    mkdir -p "$work"
else
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
fi

"$root/build/llvm-self-sources.sh" "$work" "$runtime"

cd "$root"

# Builds the compiler into <directory>/ghul.wasm and ghul.mjs. Both passes
# use the same names, since the loader names the module it loads.
build() {
    local name=$1
    local directory=$work/$name
    shift

    mkdir -p "$directory"

    local start=$(date +%s)

    if [ -n "${WASMTIME_BOOTSTRAP_DRY_RUN:-}" ]; then
        echo "$name: $* --target wasm --wasm-loader $runtime/ghul-core/host/loader.mjs --underscore-access legacy -o $directory/ghul @$work/libraries.rsp @$work/sources.rsp"
        return
    fi

    if ! "$@" --target wasm --wasm-loader "$runtime/ghul-core/host/loader.mjs" --underscore-access legacy -o "$directory/ghul" @"$work/libraries.rsp" @"$work/sources.rsp" > "$work/$name.log" 2>&1; then
        grep -v ': warn: ' "$work/$name.log" || true
        echo "$name failed"
        exit 1
    fi

    echo "$name: $(( $(date +%s) - start ))s"
}

build pass-1 dotnet "$compiler"
build pass-2 "$embedder" "$work/pass-1/ghul.wasm"
build pass-3 "$embedder" "$work/pass-2/ghul.wasm"

if [ -n "${WASMTIME_BOOTSTRAP_DRY_RUN:-}" ]; then
    exit 0
fi

status=0

for file in ghul.wasm ghul.mjs; do
    if cmp -s "$work/pass-1/$file" "$work/pass-2/$file"; then
        echo "pass-1/$file is identical to pass-2"
    else
        echo "pass-1/$file differs from pass-2"
        status=1
    fi

    if cmp -s "$work/pass-2/$file" "$work/pass-3/$file"; then
        echo "pass-2/$file is identical to pass-3"
    else
        echo "pass-2/$file differs from pass-3"
        status=1
    fi
done

exit $status
