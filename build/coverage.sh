#!/usr/bin/env bash
#
# coverage.sh — measure how much of the compiler's own ghūl source the test
# suites execute.
#
# The compiler is built with debug information so a Portable PDB is emitted
# mapping IL back to .ghul source. For every suite, coverlet rewrites the
# built compiler assembly to record which sequence points are hit, and runs
# the suite against it: the integration and cross-assembly suites spawn the
# compiler, and the unit tests call into the copy beside their own program.
# This script only captures — it writes each suite's Cobertura report
# to coverage/ and stops there. Turning that into the HTML report is
# ghul-lang/ghul-coverage-report's job: its own scheduled workflow checks out
# this repo, runs this script, and builds+deploys the report.
#
# Coverage is attributed to .ghul files, so any tool that reads Cobertura
# can display it too.
#
# Usage:
#   build/coverage.sh [options]
#
# Options:
#   -s, --suite <name>   Suite to measure; repeatable. One of:
#                          integration     (default) integration-tests
#                          cross-assembly  cross-assembly-tests
#                          unit            unit-tests
#                          analysis        analysis-tests
#                          all             every suite above
#   -f, --filter <path>  Restrict the integration or cross-assembly suite to
#                        one subdirectory, e.g. integration-tests/semantic.
#                        Implies a single suite of one of those two kinds.
#   -n, --no-build       Reuse the existing publish/ tree for the integration
#                        and cross-assembly suites. Only safe when it was
#                        produced by this script (it needs the PDB). Unit and
#                        analysis tests always build fresh; both are quick.
#   -o, --output <dir>   Output directory (default: coverage/).
#   -h, --help           Show this help.
#
set -euo pipefail

die() { echo "coverage: $*" >&2; exit 1; }
usage() { sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; /^set -euo/d'; exit "${1:-0}"; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# ---- parse arguments -------------------------------------------------------
suites=()
filter=""
build=1
output="coverage"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage 0 ;;
        -s|--suite)
            case "${2:?--suite needs a name}" in
                integration|cross-assembly|unit|analysis|all) suites+=("$2") ;;
                *) die "unknown suite: $2 (see --help)" ;;
            esac
            shift 2 ;;
        -f|--filter) filter="${2:?--filter needs a path}"; shift 2 ;;
        -n|--no-build) build=0; shift ;;
        -o|--output) output="${2:?--output needs a dir}"; shift 2 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
done
[[ ${#suites[@]} -gt 0 ]] || suites=(integration)

# `all` anywhere in the list means every suite, and a suite named twice runs
# once, so any combination of repeats does what it looks like.
expanded=()
for suite in "${suites[@]}"; do
    if [[ "$suite" == "all" ]]; then
        expanded=(integration cross-assembly unit analysis)
        break
    fi
    if [[ " ${expanded[*]:-} " != *" $suite "* ]]; then
        expanded+=("$suite")
    fi
done
suites=("${expanded[@]}")

if [[ -n "$filter" ]]; then
    [[ ${#suites[@]} -eq 1 ]] || die "--filter applies to a single suite"
    case "${suites[0]}" in
        integration|cross-assembly) ;;
        *) die "--filter only applies to the integration or cross-assembly suites" ;;
    esac
fi

# ---- tooling ---------------------------------------------------------------
# Kept in a script-private tool path so the committed manifest, and every
# other job that restores it, stay untouched.
tools="$repo_root/.coverage-tools"
ensure_tool() {
    local package="$1" command="$2"
    if [[ ! -x "$tools/$command" ]]; then
        echo "coverage: installing $package"
        dotnet tool install "$package" --tool-path "$tools" >/dev/null \
            || die "could not install $package"
    fi
}
ensure_tool coverlet.console coverlet

# ---- build the compiler with debug information -----------------------------
# Only the integration and cross-assembly suites need publish/: they spawn
# the compiler out of process, from a path each test's ghul.json names
# explicitly. DebugType/DebugSymbols are what the ghūl MSBuild targets
# consult to decide whether to pass --debug to the compiler; setting them
# here rather than in ghul.ghulproj keeps ordinary builds, and the released
# package, free of debug information and the JIT optimization it suppresses.
needs_publish=0
for suite in "${suites[@]}"; do
    [[ "$suite" == "integration" || "$suite" == "cross-assembly" ]] && needs_publish=1
done

if [[ "$needs_publish" -eq 1 ]]; then
    if [[ "$build" -eq 1 ]]; then
        echo "coverage: building compiler with debug information"
        dotnet publish --output publish/ -p:DebugType=portable -p:DebugSymbols=true \
            || die "build failed"
    fi
    [[ -f publish/ghul.dll ]] || die "publish/ghul.dll not found; drop --no-build"
    [[ -f publish/ghul.pdb ]] || die "publish/ghul.pdb not found; publish/ was built without debug information, drop --no-build"
fi

rm -rf "$output"
mkdir -p "$output"

# ---- run each suite under instrumentation ---------------------------------
# The integration and cross-assembly suites spawn the compiler as a separate
# process — directly, or via MSBuild for cross-assembly — many times over,
# so coverlet instruments publish/ghul.dll itself; every spawned process
# runs the instrumented copy and merges its hit counts into one file under a
# mutex, so the suites' internal parallelism is not a problem.
run_out_of_process_suite() {
    local suite="$1" target
    case "$suite" in
        integration)    target="${filter:-integration-tests}" ;;
        cross-assembly) target="${filter:-cross-assembly-tests}" ;;
    esac
    [[ -e "$target" ]] || die "no such test path: $target"

    local args="ghul-test --config published $target"
    [[ "$suite" == "cross-assembly" ]] && args="ghul-test --config cross-assembly $target"

    echo "coverage: running $suite ($target)"
    local start=$SECONDS
    # A failing test still leaves usable coverage, so record the outcome and
    # carry on rather than losing the run to `set -e`.
    local status=0
    # Both configurations run publish/ghul.dll, the file just instrumented
    # above; the ghul-compiler tool would run uninstrumented and leave
    # coverage empty.
    "$tools/coverlet" publish/ghul.dll \
        --target dotnet \
        --targetargs "$args" \
        --format cobertura \
        --output "$output/$suite.cobertura.xml" \
        --include-test-assembly \
        || status=$?
    echo "coverage: $suite finished in $((SECONDS - start))s (exit $status)"
    [[ "$status" -eq 0 ]] || echo "coverage: warning: $suite reported failures; coverage below still reflects what ran"
}

# Unit tests call into the compiler in the same process: the copy of
# ghul.dll the build puts beside their program, which this instruments, and
# then runs the program against. They are run by ghul-testing, which the
# build takes from libraries/ghul-testing; where no checkout is there or
# beside this one, its latest release is fetched there first.
run_unit_suite() {
    if [[ ! -d libraries/ghul-testing/src && ! -d ../ghul-testing/src ]]; then
        local tag
        tag="$(build/library-tag.sh ghul-testing)" || die "cannot find ghul-testing's latest release"
        git clone --quiet --depth 1 --branch "$tag" https://github.com/ghul-lang/ghul-testing libraries/ghul-testing \
            || die "cannot fetch ghul-testing $tag"
    fi

    echo "coverage: building unit-tests"
    local config="Debug"
    dotnet build unit-tests -c "$config" >/dev/null || die "unit-tests build failed"
    local directory="unit-tests/bin/$config/net10.0"
    local dll="$directory/ghul.dll"
    [[ -f "$dll" ]] || die "$dll not found after build"
    [[ -f "${dll%.dll}.pdb" ]] || die "${dll%.dll}.pdb not found; unit-tests was built without debug information"

    echo "coverage: running unit"
    local start=$SECONDS
    local status=0
    "$tools/coverlet" "$dll" \
        --target dotnet \
        --targetargs "$directory/unit-tests.dll --format text" \
        --format cobertura \
        --output "$output/unit.cobertura.xml" \
        --include-test-assembly \
        || status=$?
    echo "coverage: unit finished in $((SECONDS - start))s (exit $status)"
    [[ "$status" -eq 0 ]] || echo "coverage: warning: unit reported failures; coverage below still reflects what ran"
}

# Analysis tests spawn the compiler as a subprocess too (analyser_process.ghul
# launches the ghul.dll that lands in analysis-tests/bin/ via ProjectReference),
# so this instruments that copy directly rather than going through publish/.
# Built explicitly first, and run with --no-build after, so `dotnet test`
# cannot silently rebuild over the instrumented copy mid-run.
run_analysis_suite() {
    echo "coverage: building analysis-tests"
    local config="Debug"
    dotnet build analysis-tests -c "$config" >/dev/null || die "analysis-tests build failed"
    local dll="analysis-tests/bin/$config/net10.0/ghul.dll"
    [[ -f "$dll" ]] || die "$dll not found after build"
    [[ -f "${dll%.dll}.pdb" ]] || die "${dll%.dll}.pdb not found; analysis-tests was built without debug information"

    echo "coverage: running analysis"
    local start=$SECONDS
    local status=0
    "$tools/coverlet" "$dll" \
        --target dotnet \
        --targetargs "test analysis-tests -c $config --no-build" \
        --format cobertura \
        --output "$output/analysis.cobertura.xml" \
        --include-test-assembly \
        || status=$?
    echo "coverage: analysis finished in $((SECONDS - start))s (exit $status)"
    [[ "$status" -eq 0 ]] || echo "coverage: warning: analysis reported failures; coverage below still reflects what ran"
}

for suite in "${suites[@]}"; do
    case "$suite" in
        integration|cross-assembly) run_out_of_process_suite "$suite" ;;
        unit)                       run_unit_suite ;;
        analysis)                   run_analysis_suite ;;
        *) die "unknown suite: $suite (see --help)" ;;
    esac
done

# ---- done -------------------------------------------------------------------
reports=("$output"/*.cobertura.xml)
[[ -e "${reports[0]}" ]] || die "no coverage reports were produced"

echo
echo "coverage: wrote"
for report in "${reports[@]}"; do
    echo "  $report"
done
echo
echo "Turning these into the HTML report is ghul-lang/ghul-coverage-report's job"
echo "(its own scheduled workflow checks out this repo, runs this script, and"
echo "builds+deploys the report) - see https://github.com/ghul-lang/ghul-coverage-report."
