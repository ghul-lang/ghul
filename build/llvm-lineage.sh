#!/bin/bash
# Builds the compiler for llvm from the released native compiler, as
# bootstrap.sh builds it for .NET from the released .NET compiler: stage 0,
# the released compiler, builds this source (stage 1), and stage 1 builds it
# again (stage 2). Stage 2 is what the tests run on and what a release ships.
#
# Stage 2 must rebuild itself. Where stages 1 and 2 are identical, module and
# executable, it does: stage 1 built stage 2 and is the same compiler. Where
# they differ, as they do when this source changes the code the compiler
# generates for itself, `fixed-point` builds stage 3 with stage 2, which must
# be identical to stage 2.
#
# usage: build/llvm-lineage.sh stage-2 <work> <stage 0 compiler> [<ghul-runtime>]
#        build/llvm-lineage.sh fixed-point <work> [<ghul-runtime>]
#
# `stage-2` writes <work>/stage-2/ghul and <work>/stage-2/ghul.ll, hashes
# both into <work>/stage-2.sha256, and writes `same` or `different` to
# <work>/stage-1-vs-2. `fixed-point` reads those and needs only the stage 2
# executable, so it can run on another machine from the same checkout. The
# runtime defaults to the checkout under libraries/, where CI puts it.
# ghul-llvm has to be on the PATH, or named by GHUL_LLVM.
#
# Every stage is built by build/llvm-build-pass.sh, the command
# llvm-bootstrap.sh builds its passes with, so stage 2 can be compared byte
# for byte with the native compiler the .NET compiler builds.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

usage() {
    echo "usage: build/llvm-lineage.sh stage-2 <work> <stage 0 compiler> [<ghul-runtime>]" >&2
    echo "       build/llvm-lineage.sh fixed-point <work> [<ghul-runtime>]" >&2
    exit 2
}

[ $# -ge 2 ] || usage

step=$1
work=$2
mkdir -p "$work"
work=$(cd "$work" && pwd)

build() {
    (cd "$root" && "$root/build/llvm-build-pass.sh" "$work" "$@")
}

same() {
    cmp -s "$work/$1/ghul.ll" "$work/$2/ghul.ll" && cmp -s "$work/$1/ghul" "$work/$2/ghul"
}

case $step in
stage-2)
    [ $# -ge 3 ] || usage
    stage0=$3
    runtime=${4:-$root/libraries/ghul-runtime}

    "$root/build/llvm-self-sources.sh" "$work" "$runtime"

    echo "stage 0: $("$stage0")"

    if ! build stage-1 "$stage0"; then
        echo "::error::stage 0 ($("$stage0")) cannot build this source: the source uses something the released native compiler does not accept, or trips a fault in it"
        exit 1
    fi

    build stage-2 "$work/stage-1/ghul"

    (cd "$work/stage-2" && sha256sum ghul.ll ghul) > "$work/stage-2.sha256"

    if same stage-1 stage-2; then
        echo same > "$work/stage-1-vs-2"
        echo "stages 1 and 2 are identical, so stage 2 rebuilds itself"
    else
        echo different > "$work/stage-1-vs-2"
        echo "stages 1 and 2 differ, as they do when this source changes the code generated for it; stage 3 has to match stage 2"
    fi
    ;;
fixed-point)
    runtime=${3:-$root/libraries/ghul-runtime}

    for file in stage-1-vs-2 stage-2.sha256 stage-2/ghul; do
        if [ ! -e "$work/$file" ]; then
            echo "llvm-lineage: there is no $file in $work; run the stage-2 step first" >&2
            exit 1
        fi
    done

    if [ "$(cat "$work/stage-1-vs-2")" = same ]; then
        echo "stages 1 and 2 are identical: stage 2 rebuilds itself, so no stage 3 is needed"
        exit 0
    fi

    "$root/build/llvm-self-sources.sh" "$work" "$runtime"

    build stage-3 "$work/stage-2/ghul"

    (cd "$work/stage-3" && sha256sum ghul.ll ghul) > "$work/stage-3.sha256"

    if ! diff <(awk '{print $1}' "$work/stage-2.sha256") <(awk '{print $1}' "$work/stage-3.sha256") >/dev/null; then
        echo "::error::stage 2 does not rebuild itself: stage 3 differs from it, so the build is not reproducible"
        paste "$work/stage-2.sha256" "$work/stage-3.sha256"
        exit 1
    fi

    echo "stage 3 is identical to stage 2: stage 2 rebuilds itself"
    ;;
*)
    usage
    ;;
esac
