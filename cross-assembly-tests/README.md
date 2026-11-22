# Cross-assembly tests

Each test here is a real MSBuild project that compiles against a *separate*
assembly — another `.ghulproj`, a C# `.csproj`, or the runtime package. They
exercise what survives the assembly boundary: how a declaration is written into
metadata, and how the compiler reads it back when it is imported rather than
compiled from source. Generic constraints, variance, tuple element names,
nullability, union variants, trait default methods, accessibility and purity all
have a source form and an imported form, and the two can disagree.

That is the distinction from `integration-tests/`, which compiles source
directly and observes the diagnostics, IL, or program output of a single
assembly.

Run the suite with:

```sh
dotnet ghul-test --config cross-assembly cross-assembly-tests
```

The runner builds each project with `dotnet build`, then compares the compiler's
errors and warnings against `err.expected` / `warn.expected` and the program's
output against `run.expected`, exactly as the integration tests do. See
[../integration-tests/README.md](../integration-tests/README.md) for the file
formats and the capture workflow.

## Some tests are disabled in this repository

This fork is replacing the text-IL back end with one that writes metadata
directly, and some of these tests fail against work still in progress. Each
carries a `disabled` file naming the specific reason and what has to land before
it comes back; delete that file to re-enable the test.

They are disabled rather than left failing so that the job can gate the rest.
A suite that always fails gates nothing: a regression in a passing test
is indistinguishable from the failures already there, and this is the only suite
that exercises the *reader* — metadata this compiler writes, read back by a
compiler importing it. The single-assembly tests in `../integration-tests/`
structurally cannot see that class of defect, which is most of what the back-end
work can get wrong.

Unlike the disabled text-IL snapshots under `../integration-tests/il/`, nothing
here can pass vacuously. Each of these is a real build and run, so it fails
loudly or not at all, and re-enabling one proves the thing it names.

## Which compiler the tests are built with

A `dotnet build` run resolves its own compiler, so unlike the integration tests
these projects have no inherent connection to the compiler you are working on.
`ghul-test` therefore chooses one and passes it to MSBuild as the `GhulCompiler`
property: `--compiler` if given, otherwise the compiler in the nearest `publish`
directory at or above the working directory. So

```sh
dotnet publish --output publish/
dotnet ghul-test --config cross-assembly cross-assembly-tests
```

tests the compiler in your working tree, and the run reports which compiler that
was before it starts. Without a `publish/` directory each project falls back to
the `ghul.compiler` version in `.config/dotnet-tools.json`, which is a published
release and not your changes.

None of these projects should set `GhulCompiler` themselves: a project-level
assignment overrides the runner's choice and pins the test to whatever that
assignment resolves.

## Adding a test

Give each test its own directory containing a `.ghulproj`, the `.ghul` sources,
a `test.json` holding `{}`, and the expected-output files. A test that needs a C#
library gets its **own private copy** — never a `ProjectReference` to another
test's `.csproj`. Parallel `dotnet build` invocations of one shared project race
on `bin/Debug/<framework>/<project>.deps.json`, which MSBuild writes under an
exclusive lock, and the loser fails. The race is stochastic, so it tends to pass
on a pull request and fail later on `main`. `inherited-generic-members/lib/` is
the pattern to copy.
