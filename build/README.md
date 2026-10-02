# Build scripts
Scripts required for local and CI builds. Most of these scripts are internal to the build process, but `bootstrap.sh`, `compare-output.sh` and `coverage.sh` can be run directly.

## `bootstrap.sh`
Bootstraps the compiler by compiling it with itself, then checks that the result reproduces itself: it runs three pack-and-install passes and compares the assemblies passes 2 and 3 produced byte for byte, which must be identical. Where those differ it runs a fourth pass and compares that with pass 3 instead, since a source change that fixes the compiler's own emission reaches the fixed point a pass later. That is a fair comparison only because emission is deterministic — the module version id is a hash of the content and the PE stamp comes from the same hash, so nothing carries the clock, and every pass stamps the same assembly version. Must be run with the working directory set to the root of the repo.

## `compare-output.sh`
Checks that a change leaves the compiler's output byte-identical. It publishes the compiler from the working tree and from a base commit (`origin/main` unless `--base` names another), compiles a set of integration tests with each, in release and with `--debug`, and compiles the compiler's own source with each. Every assembly and PDB is compared byte for byte, along with whether each compilation succeeded. It prints `identical`, or each difference followed by where the outputs were kept.

```sh
build/compare-output.sh                      # il tests and the smoke set
build/compare-output.sh --all                # il and execution tests, several times longer
build/compare-output.sh semantic/some-test   # chosen directories under integration-tests/
```

Use it for any change meant to leave output unchanged, such as a refactor of the IR or the CIL backend. It needs a clean enough checkout for `git worktree add` to work, and must be run from the root of the repo.

## `coverage.sh`
Measures how much of the compiler's own ghūl source each test suite executes: unit, integration, cross-assembly, and analysis.

The compiler is built with debug information so that a Portable PDB maps the emitted IL back to `.ghul` source. Unit tests call into the compiler in the same process, so coverage comes from `coverlet.collector` (referenced from `unit-tests.ghulproj`) through the standard VSTest data-collector protocol. The other three suites spawn the compiler as a separate process, so coverlet instruments the built assembly itself and every spawned process — including MSBuild's, for cross-assembly — runs the instrumented copy. This script only captures — each suite's Cobertura report lands in `coverage/` and the script stops there.

```sh
build/coverage.sh                                   # integration tests only
build/coverage.sh --suite all                       # every suite
build/coverage.sh --filter integration-tests/parse  # one subdirectory
```

Turning the captured reports into the HTML report is [degory/ghul-coverage-report](https://github.com/degory/ghul-coverage-report)'s job, not this script's: its own scheduled workflow checks out this repo, runs this script, and builds+deploys the report to [GitHub Pages](https://ghul-lang.github.io/ghul-coverage-report/) — `coverage-data-tool` builds the namespace/type/method breakdown and drives the compiler's own analyser for syntax highlighting and hover info, and `site/` (a VitePress project) renders that into the report.

Instrumentation slows the integration suite by roughly an order of magnitude, so coverage capture is a periodic job rather than part of the pull-request gate. Debug information is turned on per invocation through MSBuild properties, so ordinary builds and the released package are unaffected.

`--help` documents the remaining options.
