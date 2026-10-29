# ghūl compiler integration tests

The directories under `integration-tests` form the main test suite for the [ghūl compiler](https://github.com/ghul-lang/ghul). Tests are executed using the [`ghul-test`](https://github.com/ghul-lang/ghul-test) snapshot test runner which is installed as a local .NET tool.

## Publishing the compiler

Each test calls the published compiler via the `ghul.json` file in the test directory. Before running any tests you must publish the compiler:

```sh
dotnet publish --output publish
```

The template `ghul.json` refers to `dotnet ../../../publish/ghul.dll` so the runner finds the freshly built compiler.

## Running tests

To run **all** integration tests:

```sh
dotnet ghul-test integration-tests
```

To run a single test directory:

```sh
dotnet ghul-test integration-tests/<test-folder>
```

If a test fails a `failed` file is left behind. You can rerun only the failed tests with:

```sh
./integration-tests/run-failed.sh
```

## Creating new tests

1. Run `./integration-tests/create.sh` and enter a new test name when prompted.
2. Edit the generated `.ghul` sources and `ghulflags` as needed.
3. Execute the test (it will fail initially):

   ```sh
   dotnet ghul-test integration-tests/<new-test>
   ```
4. Capture the produced output files as expectations:

   ```sh
   ./tasks/capture.sh integration-tests/<new-test>
   ```
5. Re-run the test and verify it now passes.
6. Commit the new test directory.

Each test directory contains a `.vscode/tasks.json` file with `Run test` (test task) and `Capture test expectation` (build task) to streamline this workflow from Visual Studio Code.

## Test folder structure

A test directory must contain one or more `.ghul` source files and a `ghulflags` file. Optional files influence behaviour:

| File | Purpose |
| --- | --- |
| `fail.expected` | If present, the build is expected to fail. The contents are ignored. |
| `err.expected` | Expected compiler error output. |
| `warn.expected` | Expected compiler warning output. |
| `run.expected` | Expected stdout from running the compiled binary. |
| `il.expected` | Expected IL disassembly output. |
| `il.item` | If present, scopes the IL disassembly to one type or member (`Namespace.TYPE` or `Namespace.TYPE::member`). Without it the whole assembly is disassembled. |
| `format.expected` | Expected output of running the formatter over the test's sources. When present, the runner also rebuilds and reruns the formatted copy and asserts it still builds and produces `run.expected`. Not supported under `--use-dotnet-build`. |
| `ghul.json` | Configuration file pointing at the compiler (created from the template). |
| `disabled*` | Any file beginning with `disabled` causes the test to be skipped. |
| `tags` | Zero or more whitespace-separated tag names, used to select a subset of tests with `--tag`. See 'Tags' below. |
| `targets` | The targets the test runs under, from `dotnet`, `wasm` and `llvm`. The runner builds and runs the test once per target. See 'Targets' below. |

## Tags

A test directory can carry a `tags` file naming zero or more of the tags below,
space- or newline-separated. `ghul-test --tag <name>` (repeatable, matched as a
union) restricts a run to tests carrying at least one of the requested tags —
see `ghul-test`'s own README for the flag. Two uses this serves:

- **Cross-cutting feature tags** — run everything that touches a language
  feature regardless of which of `execution`/`il`/`parse`/`semantic` it lives
  in, e.g. `dotnet ghul-test --tag unions integration-tests` for every
  union-related test.
- **`smoke`** — a fixed, deterministic subset (currently ~80 tests, one
  representative per (feature tag, physical group) pair, picked
  alphabetically) intended as a fast pre-push sanity check. It is not a
  substitute for the full suite, which CI always runs regardless — see
  'Local CI' in the workspace `CLAUDE.md`. Run it with
  `dotnet ghul-test --tag smoke integration-tests`.

Current feature tags: `parser`, `narrowing`, `optionals`, `unions`, `generics`,
`traits`, `classes`, `structs`, `enums`, `tuples`, `lambdas`, `async`,
`generators`, `pipes`, `purity`, `inference`, `il-emission`, `interop`,
`exceptions`, `control-flow`, `diagnostics`, `primary-ctor`, `operators`,
`arrays`, `strings`, `namespaces`, `variables`, `literals`.

The initial pass (2026-07-29) assigned these mechanically, from keywords in
each test directory's name — good enough to be useful, not perfectly accurate,
and about 9% of tests matched no keyword and carry no tags at all. There is no
scheduled re-sweep. Instead: **when you touch a test directory for an
unrelated reason and its `tags` file is missing, wrong, or could be more
specific, fix it as part of that change** — add a `tags` file where one is
missing and the test clearly fits an existing tag, correct a stale or
mismatched one, or add a new tag to the list above (updating this section) when
an existing test clearly needs a feature tag that doesn't exist yet. Don't go
looking for mistagged tests outside of what you're already touching — this is
opportunistic upkeep, not a project.

## Targets

The suite is organised by what a test asserts - `execution/`, `semantic/`,
`parse/`, `il/` - and a target is a second axis across it, not a fifth kind.
A test belongs in one of two places:

- **A program that should mean the same thing on every target** lives under
  its kind and carries a `targets` file naming the targets it runs under,
  `dotnet wasm llvm` or any subset. The runner builds and runs it once per
  target, adding `--target <name>` to its `ghulflags` - which must not name a
  target itself - and reports each run as `<test>[<target>]`. Each run
  happens in its own `.targets/<target>/` directory under the test, holding
  copies of the sources, inputs and expectations, so the runs neither collide
  nor leave artifacts in the test directory. One `run.expected` serves every
  target; where a target's result legitimately differs, a
  `run.wasm.expected`, `err.llvm.expected` or `fail.wasm.expected` stands in
  for the plain file in that target's run alone. A test that does not yet
  pass on a target records the difference that way rather than leaving the
  target out, so the gap stays visible.
- **A test about a target's own behaviour** - what it cannot compile yet,
  the shape of the module or IR it writes, a host operation only it has -
  lives under that target's directory, `wasm/` or `llvm/`, with `--target
  <name>` in its `ghulflags`.

Don't copy a program that an execution test already holds into `wasm/` or
`llvm/`: give the execution test a `targets` file instead.

A run under `wasm` needs the runtime library, which a wasm build compiles in
from source rather than loading from an assembly. The `local` configuration in
`ghul-test.json` names ghul-runtime's sources, both its core and its runtime
trees, from a checkout under `libraries/` or beside the repository, and
ghul-test gives them to every wasm run. CI checks it out under `libraries/`,
at the release a user would get, or at its head on the scheduled run.
Without the libraries a wasm run fails to compile, which is the right answer: the
test asserts the program on that target, and silently skipping it would hide
the gap the `targets` file exists to show.

A run under `llvm` links with ghul-llvm, which is not on every machine. So the
`local` configuration, and `ci` through it, lists only `dotnet` and `wasm` in
its `run_targets`, and passes over every llvm run: a `targets` file's `llvm`
variant and a test whose `ghulflags` name `--target llvm` alike, reporting how
many it passed over. Those runs are made by the `llvm` configuration, which
runs them alone, on a machine with ghul-llvm on the PATH; in CI that is the
llvm job. A test author adding `llvm` to a `targets` file runs it that way:

```sh
PATH="$(dirname "$(build/ghul-llvm.sh /tmp/ghul-llvm)"):$PATH" \
    build/llvm-test-objects.sh
PATH="$(dirname "$(build/ghul-llvm.sh /tmp/ghul-llvm)"):$PATH" \
    dotnet ghul-test --config llvm integration-tests
```

`build/ghul-llvm.sh` fetches the latest ghul-llvm release, as a user's build
fetches it, and prints where its executable is. The CI job runs the tests in an image with no C compiler,
linker or C library, and then runs each program again in an empty image with
`build/llvm-programs.sh`, which fails any program that is not fully static.

`build/wasm-validate.sh` and `build/llvm-validate.sh` hand every module the
compiler writes for their target to an engine. They select tests by the target
the `ghulflags` name, wherever the test lives, so a target test outside
`wasm/` or `llvm/` is checked too. A test that runs under the target through a
`targets` file is left to ghul-test: under `wasm`, the configuration that runs
the suite builds it with the core library and runs it; under `llvm`, only a
configuration whose `run_targets` names `llvm` does, as described above.

## Generated tests

`execution/argument-pack-grid` holds one test per cell of a conformance grid
for argument packs: how the combinator is reached, how the function filling a
`T.. -> U` formal is written, where it sits relative to the pack, what pins
the pack, and the arity. The
cells are written by the ghūl program in `tools/argument-pack-grid`, whose
README says how to regenerate them. Edit the generator rather than a cell.

A cell that fails today is kept, with the failure captured as its expectation:
`fail.expected` and `err.expected` for one that does not compile, and
`run.expected` for one that compiles, since each program catches any exception
and prints what it caught and whether its result was right. Fixing a gap
therefore fails the cells it fixes, and recapturing them records the fix.

`tools/inference-oracle` checks the same cells for silent mis-resolution, by
comparing each one's IL against the same program with its inferred types
written out. It is run by hand, not by the suite.

## The IL snapshot tests

Tests under `il/` carrying an `il.expected` snapshot assert the shape of what
the compiler emits. Originally these captured the text-IL emitter's output;
this repository replaced that emitter with direct binary emission, so the
snapshots are recaptured from the emitted assembly disassembled by ildasm
(Microsoft's own, so the snapshot reads what the runtime reads rather than what
the compiler's encoder thinks it wrote).

A re-enabled test builds as a library (`--library`), the emitted assembly is
disassembled by ildasm, and the result is compared to `il.expected`. The scope
of the dump is chosen by the test:

- A whole type or member, via an `il.item` file naming it
  (`Namespace.TYPE` or `Namespace.TYPE::member`). This suits type-level tests.
- The individual statements an `@IL.output("il.out")` pragma marks. The binary
  back end records each marked statement's instruction byte-offset range and
  carries it out of the assembly as a synthetic method attribute; the runner
  reads that, disassembles each method, and keeps only the instructions whose
  offset falls in a marked range, laying them out in source order. This suits
  statement- and expression-level tests, and lets one test cover many constructs
  the way the text emitter's per-pragma output did.

Re-enable a statement-level test by switching its `--assembler` flag to
`--library` (leaving the `@IL.output` pragmas in place), removing its `disabled`
file, and recapturing `il.expected` via `tasks/capture.sh`. The recaptured
snapshot is ildasm's rendering, so locals are slot-indexed (`ldloc.1`) where the
old text-IL snapshots named them (`ldloc 'x.1'`).

Most of the group's 86 tests are still disabled; the mechanism above is proven
on representative statement- and expression-level cases (arithmetic operators,
numeric casts), and re-enabling the rest is mechanical.

Disabled rather than deleted for two reasons: the snapshots record what the
emitter is expected to produce, which is the reference the binary back end is
written against; and keeping the directories in place lets merges from upstream
ghul apply to them cleanly.

## Expectation comparison workflow

1. The runner invokes the compiler using the arguments in `ghulflags` and the test sources. Compiler output goes to `compiler.out`.
2. Error and warning lines are `grep`ed into `err.grep` and `warn.grep`, sorted into `err.sort` and `warn.sort`, then compared to the `*.expected` files.
3. If compilation succeeds the test binary is executed and its output compared to `run.expected`.
4. If `il.expected` exists the generated `il.out` file is diffed as well.
5. Any mismatch leaves the test directory marked with a `failed` file and unified diffs describing the differences.

## Command line usage

```
ghul-test [--config <name>] [--tag <name>]... [--shard <index>/<count>] <test-folder> [...]
```

The configurations are in `ghul-test.json` at the root of the repository:
`local` (the default, the compiler in `publish/`), `published` (the same
without the wasm libraries), `cross-assembly` (MSBuild projects built with the
compiler in `publish/`), and `ci` and `ci-cross-assembly`, which CI runs.

`--tag <name>` (repeatable) restricts discovery to tests carrying at least one
of the requested tags — see 'Tags' above.

Environment variables:

- `TEST_PROCESSES` &ndash; number of worker processes to use.

## Dependencies

`ghul-test` requires the standard Unix utilities `grep`, `sort`, `diff` and `ln` as well as a .NET 8 SDK.
### Visual Studio Code

Each test case is a mini ghul project in its own right and can be opened as a project folder in Visual Studio Code individually. It's generally better to open a test case in a separate Visual Studio Code instance, rather than editing its files from VSCode alongside the compiler (because having files open from multiple different ghul projects in the same VSCode instance can result in confusing/misleading messages from the ghul language extension).

#### Creating a new test case

With the ghul compiler folder open in Visual Studio Code, run the create test task:

`<Ctrl>+<Shift>+P` | `Tasks: Run task` | `Create new test`

Then enter a kebab-case name for the new test when prompted in the terminal window.

A new VSCode window will open pointing at the new test project

#### Running a test case

With a test case folder open in Visual Studio Code, run the default test task to execute the test:

`<Ctrl>+<Shift>+P` | `Tasks: Run task` | `Run test`

The test results will appear in the terminal window

**Note** VSCode has no standard key binding for running the default test, but you can configure a custom binding if you want to access this task more easily

#### Capturing test case expectations

Once you have a test case that generates the appropriate output, you need to capture that output as expectation files. If on a future test run the test produces different output to what was expected, the test runner will flag the test as failed

With a test case folder open in Visual Studio Code, run the default build task to execute the test:

`<Ctrl>+<Shift>+P` | `Tasks: Run task` | `Capture test expectations`

**Note** If you're using the standard VSCode key bindings you can also do this via `<Ctrl>+<Shift>+B`

### Command line

You can also run tests, capture test expectations and create new tests from the command line.

#### Creating a new test case

To create a new test case run `./integration-tests/create.sh` and enter a kebab-case name for the new test case when prompted

#### Running all tests

To run all tests, run `dotnet ghul-test integration-tests`.

#### Running a specific test

To run a specific test, run `dotnet ghul-test integration-tests/<test-folder>`.

#### Capturing test case expectations

To capture a test's expected results, run `./tasks/capture.sh integration-tests/<test-folder>`.

**Note** a test must have been run first. Capture promotes its output when the run left a `failed` marker, or when some produced file differs from its expectation byte for byte. The second case is a change that moves only whitespace, which the runner's comparison ignores, so such a test passes. A passing run deletes its output, so run it with `GHUL_TEST_KEEP_ARTIFACTS=1` to capture one.

**Note** the current working directory must be the repository root when running these scripts.

Capture promotes each produced file to its `*.expected` counterpart, and deletes
any that came out empty — an empty expectation asserts exactly what a missing
one does, since the runner diffs against `/dev/null` when no expectation is
present. `fail.expected` is the exception, being read for its presence rather
than its contents.
