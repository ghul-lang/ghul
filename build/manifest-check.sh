#!/bin/bash
# Checks that ghul-project.json still loads and describes the compiler as
# its native build compiles it: ghul reads the manifest and writes its
# response file, the manifest's source globs select exactly the files
# build/llvm-self-sources.sh lists, and the options that change what is built
# are the ones build/llvm-build-pass.sh passes. build/llvm-build-pass.sh is
# what CI builds with; the manifest follows it.
#
# usage: build/manifest-check.sh
#
# Uses the ghul.cli release .config/dotnet-tools.json pins, after
# `dotnet tool restore`.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cd "$root"

echo "checking ghul-project.json with $(dotnet ghul --version | head -n 1)"

dotnet ghul project response-file --output "$work/manifest.rsp" --source-globs "$work/globs.txt"

runtime=$(sed -n 's/^--library-source ghul-runtime@[^=]*=//p' "$work/manifest.rsp")

if [ -z "$runtime" ]; then
    echo "ghul-project.json: the response file names no ghul-runtime library" >&2
    exit 1
fi

# The options that change what is built, one a line with its value: from
# the native build's command line, less its outputs and the version it is
# stamped with, and from the response
# file, less what changes only what is reported.
build_line=$(grep -m 1 -- '--target llvm' "$root/build/llvm-build-pass.sh")

for word in $build_line; do
    echo "$word"
done | awk '
    /^--/ { if (option != "") print option; option = $0; next }
    option != "" && $0 !~ /^[@"]/ { print option " " $0; option = ""; next }
    { if (option != "") print option; option = "" }
    END { if (option != "") print option }
' | grep -v -e '^--llvm-output' -e '^-o' -e '^--version' | sort > "$work/build-options.txt"

grep -e '^--target' -e '^--rtti' -e '^--llvm-parallel-gc' -e '^--underscore-access' -e '^--global-namespace' -e '^--define' -e '^--default-use' \
    "$work/manifest.rsp" | sort > "$work/manifest-options.txt"

if ! diff -u --label 'build/llvm-build-pass.sh' --label "ghul-project.json, through $(dotnet ghul --version | head -n 1)" "$work/build-options.txt" "$work/manifest-options.txt"; then
    echo "ghul-project.json: the options that change what is built differ from the native build's." >&2
    echo "A '-' line is passed by build/llvm-build-pass.sh and not by the manifest, a '+' line the other way." >&2
    echo "Where neither file changed, the ghul.cli the tool manifest pins writes the manifest differently." >&2
    exit 1
fi

"$root/build/llvm-self-sources.sh" "$work/self" "$runtime"

shopt -s globstar nullglob

while read -r glob; do
    [ -n "$glob" ] || continue

    for file in $glob; do
        echo "$root/$file"
    done
done < "$work/globs.txt" | sort -u > "$work/manifest-sources.txt"

# The native build compiles a generated file in place of a committed one of
# the same name, which an analyser reads as committed.
while read -r file; do
    case "$file" in
        "$work/self/"*)
            grep -- "/${file##*/}\$" "$work/manifest-sources.txt" || echo "$file"
            ;;
        *)
            echo "$file"
            ;;
    esac
done < "$work/self/sources.rsp" | sort -u > "$work/self-sources.txt"

if ! diff -u --label 'build/llvm-self-sources.sh' --label 'ghul-project.json' "$work/self-sources.txt" "$work/manifest-sources.txt"; then
    echo "ghul-project.json: its sources differ from the files the native build compiles" >&2
    exit 1
fi

echo "ghul-project.json loads and lists the $(wc -l < "$work/manifest-sources.txt") files the native build compiles"
