#!/bin/bash
# Builds the compiler for llvm from a chain that starts at a released native
# compiler rather than at .NET: stage 0, the released compiler, builds this
# source (stage 1); stage 1 builds it again (stage 2). Where stages 1 and 2
# agree, module and executable, stage 2 is the fixed point. Stage 1 was
# built by an older compiler, so it can differ; then stage 2 builds a stage
# 3, which must match stage 2. A chain that has not settled by stage 3 fails.
#
# usage: build/llvm-chain.sh <stage 0 compiler> [<ghul-runtime>]
#
# The runtime defaults to the checkout under libraries/, where CI puts it.
# ghul-llvm has to be on the PATH, or named by GHUL_LLVM. The stages are
# written to a temporary directory, or to LLVM_CHAIN_DIR where it is set,
# which is then kept. The stage that settled is named in <dir>/final, and
# its module and executable are hashed into <dir>/final.sha256.
#
# Every stage is built by build/llvm-build-pass.sh, the command
# llvm-bootstrap.sh builds its passes with, so a settled stage can be
# compared byte for byte with llvm-bootstrap.sh's pass 2.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

if [ $# -lt 1 ]; then
    echo "usage: build/llvm-chain.sh <stage 0 compiler> [<ghul-runtime>]" >&2
    exit 2
fi

stage0=$1
runtime=${2:-$root/libraries/ghul-runtime}

if [ -n "${LLVM_CHAIN_DIR:-}" ]; then
    work=$LLVM_CHAIN_DIR
    mkdir -p "$work"
else
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
fi

"$root/build/llvm-self-sources.sh" "$work" "$runtime"

cd "$root"

build() {
    "$root/build/llvm-build-pass.sh" "$work" "$@"
}

same() {
    cmp -s "$work/$1/ghul.ll" "$work/$2/ghul.ll" && cmp -s "$work/$1/ghul" "$work/$2/ghul"
}

echo "stage 0: $("$stage0")"

if ! build stage-1 "$stage0"; then
    echo "::error::stage 0 ($("$stage0")) cannot build this source: either the source uses something the released native compiler does not accept, or the native compiler has a fault the .NET one does not"
    exit 1
fi

build stage-2 "$work/stage-1/ghul"

final=stage-2

if ! same stage-1 stage-2; then
    echo "stage 1 and stage 2 differ, as they can where stage 0 is an older compiler; building stage 3"

    build stage-3 "$work/stage-2/ghul"

    if ! same stage-2 stage-3; then
        echo "::error::the chain did not settle: stages 2 and 3 differ, so the build is not reproducible"
        diff "$work/stage-2/ghul.ll" "$work/stage-3/ghul.ll" | head -40 || true
        exit 1
    fi

    final=stage-3
fi

echo "the chain settled at $final"

echo "$final" > "$work/final"

(cd "$work/$final" && sha256sum ghul.ll ghul) > "$work/final.sha256"
