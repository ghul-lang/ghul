#!/usr/bin/env bash
#
# library-tag.sh - print the newest release of a source library, the one
# ghul-cli would build with.
#
# Usage: build/library-tag.sh <library>
#
# <library> is a library repository under github.com/ghul-lang, such as
# ghul-runtime.

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: build/library-tag.sh <library>" >&2
    exit 2
fi

library="$1"

tag="$(git ls-remote --tags --refs "https://github.com/ghul-lang/$library" | sed -n 's|.*refs/tags/\(v[0-9][0-9.]*\)$|\1|p' | sort -rV | head -n1)"

if [ -z "$tag" ]; then
    echo "$library has no release" >&2
    exit 1
fi

echo "$tag"
