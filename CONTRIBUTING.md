# Contributing to the ghūl compiler

Thanks for your interest. Bug reports, language questions, documentation fixes
and code are all welcome.

This is the compiler for the [ghūl programming language](https://ghul.dev), and
it is written in ghūl itself. That shapes almost everything below, so it is
worth reading the [self-hosting](#self-hosting-and-the-bootstrap-rule) section
even if you skip the rest.

Automated contributors have a few extra rules in [AGENTS.md](./AGENTS.md); the
requirements on this page apply to them too.

## Reporting a bug

Open an [issue](https://github.com/degory/ghul/issues/new/choose). The most
useful bug report is a short program that shows the problem, plus what you
expected to happen and what happened instead. A program that is a few lines long
and compiles on its own is worth far more than a description of a problem inside
a large project.

If the compiler reported an internal error, include the whole message.

## How bugs are prioritised

Every open bug carries one of `P0`, `P1`, `P2` or `P3`. The band is about how a
bug reaches you, not how hard it is to fix or how much of the compiler it
touches: a one-line fix to something that silently miscompiles outranks a large
piece of work on something that fails loudly.

**P0 - silently wrong, or destroys work.** Nothing tells you anything is wrong,
so the damage is already done by the time you find out. Code that compiles clean
and emits an assembly that will not load, or that throws when a type is first
touched. Code that compiles clean, loads, runs, and computes the wrong answer.
Tooling that damages the source it was pointed at - a rename that breaks the
program, a format-in-place that produces something the compiler rejects. A
released change that breaks working code without a major version bump and
without saying so.

**P1 - blocks work loudly, or the editor is wrong.** You can see that something
is wrong, and you are stopped or misled until it is fixed. A program that should
compile and does not, especially where the diagnostic does not point at the
cause, or where the compiler reports an internal error. An analyser crash.
Analysis mode giving wrong answers about a code pattern, and incremental
analysis disagreeing with a full build - incremental analysis is on by default
and nearly every edit goes through it, so a wrong answer there is the normal
case rather than an edge one.

**P2 - a real defect, with a way around it.** The behaviour is wrong or missing,
and there is something you can do instead in the meantime. Analysis mode
declining to answer at all for some pattern belongs here rather than in P1: no
answer is visibly no answer, where a wrong one gets acted on. Build noise,
stray artefacts and diagnostics that are unhelpful but not misleading also sit
here.

**P3 - everything else.** Cosmetic problems, and bugs parked behind larger work.

Two of these orderings are deliberate and are worth stating outright. Wrong
output outranks no output, in the compiler and in the analyser alike, because
silence is legible and a wrong answer is not. And tooling that damages source
sits at the top with miscompilation rather than below it, because both destroy
work that was correct when it was written.

## Asking about the language

If you are not sure whether something is a bug or the language working as
designed, ask. [GHUL.md](./GHUL.md) is the language reference and the
[website](https://ghul.dev) covers the same ground at more length, but both are
works in progress and the compiler does not always agree with them. A question
that turns out to be a documentation gap is a useful contribution in itself.

## Setting up

You need the [.NET 10 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/10.0).
Nothing else is required - the compiler that builds this repository is itself a
.NET tool, restored into the working tree:

```sh
git clone https://github.com/degory/ghul.git
cd ghul
dotnet tool restore
dotnet build
```

[Visual Studio Code](https://code.visualstudio.com) with the
[ghūl extension](https://marketplace.visualstudio.com/items?itemName=degory.ghul)
gives you diagnostics, hover, completion and go-to-definition while you work.

## Self-hosting and the bootstrap rule

The compiler compiles itself. When you change `src/`, your change is compiled by
the **previously published** release of `ghul.compiler`, not by the compiler your
branch produces.

The practical consequence catches everyone out once: **a compiler feature cannot
be used in `src/` in the same change that adds it.** The published compiler has
never heard of it, so the build fails before your version exists. Add the
feature in one pull request; start using it in `src/` in a later one, after the
first has been released.

The version pinned in `.config/dotnet-tools.json` is only a local fallback so
that `dotnet tool restore` has some compiler to run. CI resolves the latest
published release at run time and builds with that, so that is the version your
change actually has to satisfy. To match CI locally:

```sh
dotnet tool update --local ghul.compiler
```

Never commit a manifest pinned to a `0.0.0-*` local version - it breaks the
build for everyone else.

`./build/bootstrap.sh` is the check that self-hosting still works. It builds the
compiler with itself three times over and compares the assemblies passes 2 and 3
produced, which must be identical. Where they differ it runs a fourth pass and
compares that with pass 3 instead, which is what a source change that fixes the
compiler's own emission looks like.

## Testing

Everything below must pass before a pull request can merge. A pull request's
own CI run is the entry check for the merge queue - the bootstrap, with the
unit tests running beside it - and the merge queue then runs all of it on the
pull request merged with `main` and with anything queued ahead of it, before
the merge happens. Run what is relevant to your change locally; there is no
need to run the whole suite yourself, because the queue will.

| Suite | Command | Time | Notes |
|---|---|---|---|
| Unit | `dotnet test unit-tests` | seconds | Deliberately selective - see [Changing the type system](#changing-the-type-system) for the exception |
| Integration | `dotnet publish --output publish/ && dotnet ghul-test integration-tests` | ~3 min | Snapshot-based; see [integration-tests/README.md](integration-tests/README.md) |
| Cross-assembly | `dotnet publish --output publish/ && dotnet ghul-test --use-dotnet-build cross-assembly-tests` | ~1 min | Real MSBuild projects; see [cross-assembly-tests/README.md](cross-assembly-tests/README.md) |
| Analysis | `dotnet test analysis-tests` | seconds | Drives the language-service mode the editor extension uses |
| Bootstrap | `./build/bootstrap.sh` | ~1-2 min | Self-hosting; produces little output until each pass finishes |

**Publish before running the integration or cross-assembly tests.** Both find the
compiler under `publish/`. Skip the publish step and they quietly test the last
*published* compiler instead of your change, and pass regardless of what you did.

Times are from a reasonably fast machine, and can be several times longer in a
container or on a small VM.

### Adding a test

Any change in behaviour needs a test. Integration tests are the main net, and
`./integration-tests/create.sh` scaffolds one. They live in four groups by what
they assert:

- `integration-tests/execution` - the program builds, runs, and prints the
  expected output.
- `integration-tests/il` - the emitted IL.
- `integration-tests/parse` - parse errors and warnings.
- `integration-tests/semantic` - semantic errors and warnings.

Each test is a directory of ghūl source plus `*.expected` snapshot files;
`./tasks/capture.sh <test-directory>` promotes what the compiler currently
produces into those snapshots. Check what it captured before committing it - 
capture records the behaviour that exists, which is only the behaviour you want
if your change is already correct.

A test for a bug fix should fail before your fix and pass after it. Check that
it does, rather than assuming.

### Changing the type system

The type system and inference machinery - `src/semantic/types/`,
`src/semantic/symbols/`, `src/semantic/overload_resolver.ghul`, the inference
paths in `src/syntax/process/compile-expressions/compile_expressions.ghul`, and the IR value gates
around them - are the most fragile part of the compiler. A patch that works in
isolation can still interact badly with constraint accumulation, least-upper-bound
widening, retry-loop convergence, or IL emission. So the bar here is higher than
"the integration tests pass":

- **Put new logic in its own class, with a single clear responsibility.** Prefer
  a small new class to another long method on an existing one.
- **Consolidate duplication the change reveals.** Don't refactor speculatively,
  but when one change shows you the same logic in two places, move it somewhere
  focused rather than copying it a third time.
- **Add unit tests under `unit-tests/src/`** pinning the behaviour you care
  about. A fast fixture around a small class is far easier to maintain than an
  integration test through the whole pipeline, and it documents what the class
  is supposed to guarantee.
- **Pin behaviour that looks wrong, too.** If you find a corner case that
  behaves oddly and you are not fixing it here, still add a test recording what
  it does today, with a comment saying what looks wrong and what the right
  answer would be. A later change then either flips the test deliberately, with
  the reasoning visible in the diff, or notices it broke something.

Unit tests go in `unit-tests/src/`, one file per class under test, named
`<class>_tests.ghul`. Test classes carry `@TestClass()` and test methods
`@Test()` — aliases of the MSTest attribute types imported with `use` — and
assertions are global functions declared in `assertions.ghul`. See the files
already there for the conventions.

## Documentation

If you work something out that should have been written down, write it down.
When a `README.md`, `AGENTS.md`, `GHUL.md`, this file, or the explanatory
comment at the top of a source file turns out to be wrong or unclear, fix it as
part of your change.

Don't delete instructions from those files without asking first - something you
can see no reason for is often load-bearing.

Code comments are a different matter: the default is not to write one. Comment
where a reader who knows the codebase would still need the context - a
non-obvious invariant, an ordering requirement, a workaround whose reason isn't
visible from the code. Don't narrate what the code does, and don't write
comments that only make sense to someone who read the pull request.

Doc comments (`///`) are the exception, and are required rather than
discouraged on anything that is, or is meant to become, a stable interface: the
public types and members of the runtime and the core library, the `wasm/`
library, the IR nodes, the `Backend` trait and its peers, the analysis
protocol, and the `ghul-cli` surface. New public declarations there ship with
one, and a change that touches an existing undocumented one adds it. They are
not needed on `_`-prefixed declarations, locals or test code.

A doc comment says what a user of the declaration needs: what it does, its
arguments as `- name: description` bullets, and its contract and edge cases. It
does not say how the declaration is implemented or why it changed. Keep it
brief, since it is what an editor shows on hover: a sentence or two plus the
argument bullets. The format is described under "comments" in
[GHUL.md](./GHUL.md).

## Pull requests

Pull requests are squash-merged, so **the description becomes the commit message
and the release-notes entry**. It is the one part of a pull request that lasts,
and it is worth more care than the individual commit messages.

Write it for someone reading `git log` in a few years with no other context.
Use one or more of these sections - they are plain text, not markdown
headings:

```plaintext
Enhancements:
- Something a user of the language or the compiler would notice (closes #1234)

Bugs fixed:
- What was broken, phrased as the issue title is (closes #1235)

Technical:
- An internal change: a refactor, a test, a build tweak
```

Use only the sections you have content for, and keep every bullet to one line.
A typical description is under fifteen lines in total.

A brief introductory paragraph before the first section is allowed, and is the
right shape when the bullets are individually unremarkable but add up to
something worth saying in a sentence. Two or three sentences at most. It is
held to the same standard as everything else here: written for the changelog
reader, not for the reviewer. Read it back with the pull request forgotten - if
it only makes sense as one half of a conversation with a reviewer, it belongs
in a comment instead.

What does **not** go in the description:

- `## Summary`, `## Overview`, `## Test plan` or `## Testing` headings. The
  description is the summary, and passing CI is implied.
- Justification. State what changed; don't argue that it was right.
- A preamble that walks a reviewer through the problem, or that takes a
  paragraph to say what a bullet says in one line.
- Measurements or evidence offered to show the change was warranted. That is an
  argument for the reviewer, and it ships whether or not they read it.
- Links that won't outlive the pull request.

Anything a reviewer needs but a changelog reader does not - why this approach
over an obvious alternative, an oddity that is deliberate, an invariant the diff
doesn't reveal - is genuinely useful, and belongs in a **comment on the pull
request**. Comments aren't part of the squashed commit, so nothing there is
constrained by the rules above. Most pull requests need no comment; reach for
one when a reviewer would otherwise reasonably flag something that is fine.

Other things worth knowing:

- Keep the title under about seventy characters. Don't append the pull request
  number - GitHub does that on merge.
- Every pull request needs a passing CI run and an approving review before it
  can enter the merge queue, which tests it against `main` as it will land
  and merges it as one squashed commit. Pull requests that are ready at the
  same time are tested and released together.
- Source files use Unix line endings. The one deliberate exception is
  `integration-tests/parse/carriage-returns/test.ghul`, which is test data.
- If a test fails and you cannot see how your change caused it, say so in the
  pull request rather than working around it. The same goes for a test that
  passes and fails at random.

## Contributing from a fork

You do not need write access to this repository. Fork it, push a branch to your
fork, and open a pull request against `main` here.

```sh
git clone https://github.com/<you>/ghul.git
cd ghul
git remote add upstream https://github.com/degory/ghul.git
dotnet tool restore
git switch -c my-change
```

When `main` moves on underneath you, bring your branch up to date - the merge
button stays disabled until you do:

```sh
git fetch upstream
git rebase upstream/main
```

CI behaves differently for a pull request from a fork, in ways that are worth
knowing before they surprise you:

- **The first one you open waits for a maintainer.** GitHub holds workflow runs
  from a new contributor until someone approves them, so expect no checks at all
  for a while. This is normal and is not a problem with your branch.
- **The tests run on GitHub's runners rather than this repository's**, so they
  are slower than the timings above. Everything else about them is the same, and
  the full suite still has to pass in the merge queue.
- **Two jobs are skipped.** GitHub withholds repository secrets from a fork - 
  correctly, since anyone can open a pull request. The automated code review and
  the beta package publish both need them, so both sit out. A maintainer reviews
  your change by hand instead, which is also how it gets the approval it needs to
  merge.

Nothing about a fork stops a change being merged. It just means a person, rather
than a workflow, does the reviewing.

## Licence

The compiler is licensed under the
[GNU Affero General Public License v3.0](./LICENSE). Contributions are accepted
under the same licence.
