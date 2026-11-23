#!/usr/bin/env bash
#
# fetch-ghul-test.sh - fetch ghul-test's Native AOT runner, so a job without
# .NET can run ghul-test.
#
# The version is the one .config/dotnet-tools.json pins for ghul.test, and
# the runner is the release asset ghul-test-linux-<arch>.tar.gz for this
# machine's architecture. It is unpacked into <directory>, and the path of
# the ghul-test executable is printed, as the only thing on standard output.
#
# Usage: build/fetch-ghul-test.sh [directory]
#        (default: hosts/ghul-test; run from the repository root)

set -euo pipefail

directory="${1:-hosts/ghul-test}"
manifest=.config/dotnet-tools.json

if [ ! -f "$manifest" ]; then
    echo "fetch-ghul-test: no $manifest; run from the repository root" >&2
    exit 1
fi

# The version line inside the "ghul.test" entry.
version="$(awk '
    /"ghul\.test"[[:space:]]*:/ { inside = 1 }
    inside && /"version"[[:space:]]*:/ {
        sub(/.*"version"[[:space:]]*:[[:space:]]*"/, "")
        sub(/".*/, "")
        print
        exit
    }
' "$manifest")"

if [ -z "$version" ]; then
    echo "fetch-ghul-test: $manifest does not pin ghul.test" >&2
    exit 1
fi

case "$(uname -m)" in
    x86_64 | amd64) arch=x64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *)
        echo "fetch-ghul-test: no ghul-test runner for $(uname -m)" >&2
        exit 1
        ;;
esac

asset="ghul-test-linux-$arch.tar.gz"
url="https://github.com/ghul-lang/ghul-test/releases/download/v$version/$asset"

mkdir -p "$directory"

if ! curl -sfL --retry 3 -o "$directory/$asset" "$url"; then
    echo "fetch-ghul-test: could not download $url" >&2
    exit 1
fi

tar -xzf "$directory/$asset" -C "$directory"
rm "$directory/$asset"

runner="$(cd "$directory/ghul-test" && pwd)/ghul-test"

if [ ! -x "$runner" ]; then
    echo "fetch-ghul-test: $asset does not hold ghul-test/ghul-test" >&2
    exit 1
fi

echo "$runner"
