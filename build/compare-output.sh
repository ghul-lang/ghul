#!/bin/bash
# Checks that the working tree's compiler produces the same bytes as a base
# commit's compiler. Both are published, then each compiles the selected
# integration tests, in release and with --debug, and the compiler's own
# source, with the arguments ghul-test builds each test with. Every assembly,
# PDB and wasm module is compared byte for byte, along with
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
        find "$ROOT/integration-tests/$t" -name test.json -not -path '*/argument-pack-grid/*' -not -path '*/.targets/*' -printf '%h\n'
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

# read_command: reads one command test-commands.mjs wrote into test,
# target, dir, executable, output, options and sources.
read_command() {
    local count i value
    IFS= read -r -d '' test || return 1
    IFS= read -r -d '' target
    IFS= read -r -d '' dir
    IFS= read -r -d '' executable
    IFS= read -r -d '' output
    options=()
    IFS= read -r -d '' count
    for ((i = 0; i < count; i++)); do IFS= read -r -d '' value; options+=("$value"); done
    sources=()
    IFS= read -r -d '' count
    for ((i = 0; i < count; i++)); do IFS= read -r -d '' value; sources+=("$value"); done
}

# compile_one <out> <extra> <command-file>: runs the build command in
# <command-file>, with <extra> added to its options and its output in <out>,
# named after the test.
compile_one() {
    local out=$1 extra=$2 file=$3
    local test target dir executable output options sources name extension
    read_command < "$file"
    name=$(echo "$test" | sed 's#^.*integration-tests/##; s#/#__#g; s#\[[a-z]*\]$##').$target
    if [ "$target" = dotnet ] ; then extension=dll ; else extension=${output##*.} ; fi
    [ -n "$extra" ] && options+=("$extra")
    (cd "$dir" && "$executable" "${options[@]}" "${sources[@]}" -o "$out/$name.$extension") > "$out/$name.log" 2>&1
    echo $? > "$out/$name.status"
    rm -f "$out/$name.runtimeconfig.json"
}

export -f read_command compile_one

# The command ghul-test builds each test with, for every target but llvm,
# whose builds link with ghul-llvm.
for side in base new ; do
    mapfile -t tests < "$WORK/tests.txt"
    read -r -a ghul_test <<< "${GHUL_TEST:-dotnet ghul-test}"
    (cd "$ROOT" && "${ghul_test[@]}" --config published --compiler "$WORK/$side-compiler/ghul.dll" --commands "$WORK/$side-commands.all" "${tests[@]}") > "$WORK/$side-commands.log" 2>&1 || { echo "ghul-test could not list the $side build commands, see $WORK/$side-commands.log" >&2; exit 2; }
    mkdir -p "$WORK/$side-commands"
    node "$ROOT/build/test-commands.mjs" "$WORK/$side-commands.all" --not-target llvm > "$WORK/$side-commands.records"
    index=0
    while read_command ; do
        {
            printf '%s\0' "$test" "$target" "$dir" "$executable" "$output" "${#options[@]}" "${options[@]}" "${#sources[@]}" "${sources[@]}"
        } > "$WORK/$side-commands/$index"
        index=$((index + 1))
    done < "$WORK/$side-commands.records"
done

for side in base new ; do
    for mode in release debug ; do
        mkdir -p "$WORK/$side-$mode"
        extra=""
        [ $mode = debug ] && extra=--debug
        echo "compiling tests: $side $mode"
        find "$WORK/$side-commands" -type f | xargs -P "$JOBS" -I{} bash -c 'compile_one "$1" "$2" "$3"' _ "$WORK/$side-$mode" "$extra" {}
    done
done

COMPARED=0

for mode in release debug ; do
    for status in "$WORK/base-$mode"/*.status ; do
        name=$(basename "$status" .status)
        new=$WORK/new-$mode/$name
        if ! cmp -s "$status" "$new.status" ; then
            echo "COMPILATION RESULT $mode $name"
            DIFFERENCES=$((DIFFERENCES + 1))
            continue
        fi
        for ext in dll pdb wasm ; do
            [ -f "$WORK/base-$mode/$name.$ext" ] || continue
            COMPARED=$((COMPARED + 1))
            if ! cmp -s "$WORK/base-$mode/$name.$ext" "$new.$ext" ; then
                echo "DIFFERENT $mode $name.$ext"
                DIFFERENCES=$((DIFFERENCES + 1))
            fi
        done
    done
done

echo "$COMPARED test outputs compared"

if [ $COMPARED -eq 0 ] ; then
    echo "no test outputs to compare" >&2
    DIFFERENCES=$((DIFFERENCES + 1))
fi

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
