#!/usr/bin/env bash
#
# install-llvm-tools.sh - install LLVM 23's command-line tools, the release
# ghul-llvm is built from, for the checks that ask LLVM whether it accepts
# the text the llvm target writes.
#
# The packages come from <dir> where an earlier run left them there, and
# otherwise from apt.llvm.org, after which they are copied into <dir> for the
# next run. Under GitHub Actions the outputs `downloaded` (true where they came
# from apt.llvm.org) and `version` (the llvm-23 package's version) say what to
# keep.
#
# Usage: build/install-llvm-tools.sh <dir>

set -euo pipefail

dir=$1
mkdir -p "$dir"

downloaded=false

if compgen -G "$dir/*.deb" > /dev/null && sudo apt-get -o Acquire::Retries=5 install -y -qq "$dir"/*.deb; then
    echo "installed the LLVM tools from $dir"
else
    # The key is downloaded whole, with retries, before gpg reads it, and
    # apt retries its own fetches, so an apt.llvm.org that is briefly
    # unavailable doesn't fail the job.
    curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 --connect-timeout 30 -o "${RUNNER_TEMP:-/tmp}/apt.llvm.org.key" https://apt.llvm.org/llvm-snapshot.gpg.key
    sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/apt.llvm.org.gpg "${RUNNER_TEMP:-/tmp}/apt.llvm.org.key"
    codename=$(lsb_release -cs)
    echo "deb [signed-by=/usr/share/keyrings/apt.llvm.org.gpg] https://apt.llvm.org/${codename}/ llvm-toolchain-${codename}-23 main" | sudo tee /etc/apt/sources.list.d/llvm-23.list
    sudo apt-get -o Acquire::Retries=5 update -qq

    # Downloaded first into a directory of its own, since an image may delete
    # what apt leaves in its own cache, then installed from what is kept.
    stage=$(mktemp -d)
    mkdir -p "$stage/partial"
    sudo apt-get -o Acquire::Retries=5 -o Dir::Cache::archives="$stage" install -y -qq --download-only llvm-23
    rm -f "$dir"/*.deb
    cp "$stage"/*.deb "$dir"/
    sudo rm -rf "$stage"
    sudo apt-get -o Acquire::Retries=5 install -y -qq "$dir"/*.deb
    downloaded=true
fi

version=$(dpkg-query -W -f='${Version}' llvm-23)
echo "llvm-23 $version"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "downloaded=$downloaded" >> "$GITHUB_OUTPUT"
    echo "version=$version" >> "$GITHUB_OUTPUT"
fi
