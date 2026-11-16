#!/usr/bin/env bash
#
# convert-unit-tests.sh - rewrite unit test files from MSTest to the
# ghul-testing runner, in place.
#
# Usage: build/convert-unit-tests.sh <file.ghul>...
#
# Drops the MSTest attribute aliases, the `use` of MSTest's Assert and the
# `@TestClass()` marks, and writes each `@Test()` as `@test()`; an empty
# array from .NET's `System.Array.empty` becomes one the core has too. The
# assertions keep their names: unit-tests-native/src/assertions.ghul
# declares them over `assert`. A file is converted as it moves from
# unit-tests/ to unit-tests-native/.
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "usage: build/convert-unit-tests.sh <file.ghul>..." >&2
    exit 2
fi

for file in "$@"; do
    sed -i -E \
        -e '/^[[:space:]]*use (TestClass|Test|MSTEST) = Microsoft\.VisualStudio\./d' \
        -e '/^[[:space:]]*use Microsoft\.VisualStudio\.TestTools\.UnitTesting\.Assert;?[[:space:]]*$/d' \
        -e '/^[[:space:]]*@TestClass\(\)[[:space:]]*$/d' \
        -e 's/^([[:space:]]*)@Test\(\)/\1@test()/' \
        -e 's/System\.Array\.empty\[([^]]*)\]\(\)/Collections.LIST[\1]().to_array()/g' \
        "$file"

    # The lines taken out leave blank lines behind; keep one.
    squeezed="$(cat -s "$file")"
    printf '%s\n' "$squeezed" > "$file"

    if grep -q 'Microsoft\.VisualStudio' "$file"; then
        echo "$file: still names MSTest" >&2
        exit 1
    fi
done
