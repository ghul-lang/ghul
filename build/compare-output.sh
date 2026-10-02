#!/bin/bash
# Checks that the working tree's compiler produces the same bytes as a base
# commit's compiler. Both are published, then each compiles the selected
# integration tests, in release and with --debug, and the compiler's own
# source. Every assembly and PDB is compared byte for byte, along with
# whether each compilation succeeded.
#
# usage: build/compare-output.sh [--base <ref>] [--jobs <n>] [--all | test-directory ...]
#
# The base defaults to origin/main. Test directories are relative to
# integration-tests/. The default is the il tests and the tests tagged smoke;
# --all is the il and execution tests, without the generated argument-pack
# grid, and takes several times longer. Run from the root of the repository.

set -u

BASE=origin/main
JOBS=4
TESTS=()
ALL=false

while [ $# -gt 0 ] ; do
    case "$1" in
        --base) BASE=$2; shift 2 ;;
        --jobs) JOBS=$2; shift 2 ;;
        --all) ALL=true; shift ;;
        -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) TESTS+=("$1"); shift ;;
    esac
done

ROOT=$(pwd)

if [ ! -f "$ROOT/ghul.ghulproj" ] ; then
    echo "run from the root of the compiler repository" >&2
    exit 2
fi

WORK=$(mktemp -d)
BASE_TREE=$WORK/base-tree

DIFFERENCES=0

# Outputs are kept for inspection when anything differs.
cleanup() {
    git -C "$ROOT" worktree remove --force "$BASE_TREE" >/dev/null 2>&1
    if [ $DIFFERENCES -eq 0 ] ; then
        rm -rf "$WORK"
    else
        echo "outputs kept in $WORK"
    fi
}

trap cleanup EXIT

SMOKE=false

if [ ${#TESTS[@]} -eq 0 ] ; then
    if $ALL ; then
        TESTS=(il execution)
    else
        TESTS=(il)
        SMOKE=true
    fi
fi

{
    for t in "${TESTS[@]}" ; do
        find "$ROOT/integration-tests/$t" -name ghulflags -not -path '*/argument-pack-grid/*' -printf '%h\n'
    done
    if $SMOKE ; then
        grep -rlw smoke "$ROOT/integration-tests" --include=tags | xargs -r -n1 dirname
    fi
} | sort -u > "$WORK/tests.txt"

echo "base: $(git -C "$ROOT" log --oneline -1 "$BASE")"
echo "tests: $(wc -l < "$WORK/tests.txt") directories"

git -C "$ROOT" worktree add --detach "$BASE_TREE" "$BASE" >/dev/null 2>&1 || { echo "cannot check out $BASE" >&2; exit 2; }

publish() {
    (cd "$1" && dotnet publish ghul.ghulproj --output "$2" > "$2.log" 2>&1) || { echo "publish of $1 failed, see $2.log" >&2; exit 2; }
}

echo "publishing base and working tree compilers"
publish "$BASE_TREE" "$WORK/base-compiler"
publish "$ROOT" "$WORK/new-compiler"

compile_one() {
    local compiler=$1 out=$2 test=$3 extra=$4
    local name
    name=$(echo "$test" | sed 's#^.*integration-tests/##; s#/#__#g')
    cd "$test" || return
    local files
    files=$(find . -name '*.ghul' | sort)
    [ -z "$files" ] && return
    # shellcheck disable=SC2086
    dotnet "$compiler/ghul.dll" $extra $(cat ghulflags) $files -o "$out/$name.dll" > "$out/$name.log" 2>&1
    echo $? > "$out/$name.status"
    rm -f "$out/$name.runtimeconfig.json"
}

export -f compile_one

for side in base new ; do
    for mode in release debug ; do
        mkdir -p "$WORK/$side-$mode"
        extra=""
        [ $mode = debug ] && extra=--debug
        echo "compiling tests: $side $mode"
        xargs -P "$JOBS" -I{} bash -c "compile_one '$WORK/$side-compiler' '$WORK/$side-$mode' '{}' '$extra'" < "$WORK/tests.txt"
    done
done

for mode in release debug ; do
    for status in "$WORK/base-$mode"/*.status ; do
        name=$(basename "$status" .status)
        new=$WORK/new-$mode/$name
        if ! cmp -s "$status" "$new.status" ; then
            echo "COMPILATION RESULT $mode $name"
            DIFFERENCES=$((DIFFERENCES + 1))
            continue
        fi
        for ext in dll pdb ; do
            if [ -f "$WORK/base-$mode/$name.$ext" ] && ! cmp -s "$WORK/base-$mode/$name.$ext" "$new.$ext" ; then
                echo "DIFFERENT $mode $name.$ext"
                DIFFERENCES=$((DIFFERENCES + 1))
            fi
        done
    done
done

echo "compiling the compiler source with each compiler"

for side in base new ; do
    (
        cd "$BASE_TREE" || exit 1
        rm -rf obj/Release bin/Release
        dotnet build ghul.ghulproj -c Release -p:GhulCompiler="dotnet $WORK/$side-compiler/ghul.dll" > "$WORK/self-$side.log" 2>&1 || { echo "self compile with $side compiler failed" >&2; exit 1; }
        cp obj/Release/net10.0/ghul.dll "$WORK/self-$side.dll"
    ) || DIFFERENCES=$((DIFFERENCES + 1))
done

if ! cmp -s "$WORK/self-base.dll" "$WORK/self-new.dll" ; then
    echo "DIFFERENT compiler source"
    DIFFERENCES=$((DIFFERENCES + 1))
fi

if [ $DIFFERENCES -eq 0 ] ; then
    echo "identical"
    exit 0
fi

echo "$DIFFERENCES differences"
exit 1
