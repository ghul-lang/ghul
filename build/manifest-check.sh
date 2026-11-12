#!/bin/bash
# Checks that ghul-project.json still loads and describes the compiler as
# its native build compiles it: ghul reads the manifest and writes its
# response file, the manifest's source globs select exactly the files
# build/llvm-self-sources.sh lists, and the options carry the underscore
# access the native build passes.
#
# usage: build/manifest-check.sh
#
# Needs ghul (the ghul.cli tool) on the PATH.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cd "$root"

ghul project response-file --output "$work/manifest.rsp" --source-globs "$work/globs.txt"

runtime=$(sed -n 's/^--library-source ghul-runtime@[^=]*=//p' "$work/manifest.rsp")

if [ -z "$runtime" ]; then
    echo "ghul-project.json: the response file names no ghul-runtime library" >&2
    exit 1
fi

if ! grep -qx -- '--underscore-access legacy' "$work/manifest.rsp"; then
    echo "ghul-project.json: the options do not set --underscore-access legacy, as build/llvm-build-pass.sh does" >&2
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
