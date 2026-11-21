#!/bin/bash

# Format the compiler's own source and build the result.
#
# The formatter is the AST serializer, so its output has to parse back to
# the same tree. Nothing else tests that: the formatter's unit and
# analysis-mode tests each check one construct against a snapshot, and a
# snapshot only says the output is what it was last time, not that it is
# still ghul. This runs the whole compiler through it and builds what
# comes out, which is the check the tool actually exists to pass.
#
# It also requires the formatter to be a fixpoint on its own output: a
# formatter that is not rewrites files that were already formatted, so
# every reformat shows up as a diff and the tool cannot be run on save.
# The first pass is allowed to change things, since it is normalising
# source a person wrote; it is the second pass onwards that must not.
#
# Those checks miss a change of layout: a formatter that lays something out
# differently still builds and is still a fixpoint. build/format-corpus/
# holds sources already laid out as the formatter writes them at 76 columns,
# copied from ghul-rosetta-code, and formatting them must change nothing. A
# deliberate change of layout updates the corpus in the same change, with
# --format-in-place --format-width 76 over it.

set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here"

compiler=${GHUL_COMPILER_DLL:-publish/ghul.dll}

if [ ! -f "$compiler" ]; then
    echo "no compiler at $compiler - run 'dotnet publish --output publish/' first" >&2
    exit 1
fi

# The build has to run against this checkout's project file, tool manifest
# and dependencies, so the formatted sources are put in place and the
# originals restored with git afterwards. Uncommitted work in either tree
# would be destroyed by that restore.
if ! git diff --quiet -- src analysis-protocol; then
    echo "src/ or analysis-protocol/ has uncommitted changes" >&2
    echo "this script restores them with 'git checkout', which would discard the changes" >&2
    exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "Formatting a copy of src/ and analysis-protocol/ ..."

mkdir -p "$work/pass1"
cp -r src analysis-protocol "$work/pass1/"

dotnet "$compiler" --format-in-place "$work/pass1/src" "$work/pass1/analysis-protocol"

echo "Checking the formatter is a fixpoint ..."

cp -r "$work/pass1" "$work/pass2"
dotnet "$compiler" --format-in-place "$work/pass2/src" "$work/pass2/analysis-protocol"

cp -r "$work/pass2" "$work/pass3"
dotnet "$compiler" --format-in-place "$work/pass3/src" "$work/pass3/analysis-protocol"

if ! diff -rq "$work/pass2" "$work/pass3" > "$work/fixpoint.diff"; then
    echo "formatting already-formatted source changed it:" >&2
    cat "$work/fixpoint.diff" >&2
    exit 1
fi

echo "Checking the formatter keeps the corpus's layout ..."

cp -r build/format-corpus "$work/corpus"
dotnet "$compiler" --format-in-place --format-width 76 "$work/corpus"

if ! diff -ru build/format-corpus "$work/corpus" > "$work/corpus.diff"; then
    echo "formatting build/format-corpus/ changed its layout:" >&2
    cat "$work/corpus.diff" >&2
    exit 1
fi

echo "Building the formatted source ..."

# Build in place, then put the original sources back however this exits:
# the build has to run against the project file, its dependencies and the
# tool manifest that belong to this checkout.
restore() {
    git checkout -- src analysis-protocol
}
trap 'restore; rm -rf "$work"' EXIT

cp -r "$work/pass2/src/." src/
cp -r "$work/pass2/analysis-protocol/." analysis-protocol/

dotnet build -verbosity:quiet -nologo

echo "The compiler's own formatted source builds."
