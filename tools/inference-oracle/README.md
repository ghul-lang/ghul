# inference-oracle

Checks that a program resolved the way its inferred types say: the argument-pack grid, and any directory of programs.

A cell that compiles and prints the right answer can still have been resolved
wrongly, as long as the wrong resolution happens to compute the same thing.
For each grid cell that compiles, the oracle writes a second program with
every type the compiler would infer written out: lambda parameter and return
types, local variable types, and the type arguments of every generic call. It
compiles both with the same compiler and compares the IL of the two
assemblies. Any difference is a finding.

The explicit programs are rendered from the grid's own cell model,
`tools/argument-pack-grid/src/grid.ghul`, so a new axis value is checked as
soon as the grid has it. The inferred program is the grid's `test.ghul` as
committed, so regenerate the grid first if the generator has changed.

## Running

Publish the compiler, then run from the repository root:

```sh
dotnet publish --output publish
dotnet run --project tools/inference-oracle -- check integration-tests/execution/argument-pack-grid <work-directory>
```

Options:

- `--compiler <ghul.dll>` compiles with a compiler other than
  `publish/ghul.dll`.
- `--ildasm <path>` disassembles with a specific ildasm. Otherwise
  `GHUL_TEST_ILDASM` is used if set, then the newest
  `runtime.linux-x64.microsoft.netcore.ildasm` in the NuGet package cache.
- `--cell <text>` checks only cells whose name contains the text.
- `--json <file>` also writes the run as JSON; see below.

## Reading the output

A table of verdicts per cell:

| Verdict | Means |
| --- | --- |
| `=` | the IL matches |
| `≠` | the IL differs |
| `E` | the explicit program does not compile |
| `C` | the grid cell does not compile, so there is nothing to compare |
| `·` | the language rules the cell out |
| `?` | the cell could not be checked: the grid has no test for it, or its expectations say it compiles but this compiler rejects it |

The exit status is non-zero when any cell's IL differs. Each checked cell
leaves `inferred/` and `explicit/` under the work directory, each holding the
program, `compiler.out`, the raw disassembly `il.raw` and `il.normalised`,
plus `il.diff` beside them where the two differ.

## What the comparison ignores

Only what differs between two compiles of one program:

- The assembly header: ildasm's banner, the MVID, the image base, the extern
  references.
- Instruction offsets and code sizes, which move whenever an earlier
  instruction does.
- The numbers in the names of compiler-generated members (`$anon_N`,
  `$frame_N`, `$packed_N`, `$return_packed_N`), renumbered in order of first
  appearance. Classes identical but for those numbers tie in the class order,
  so the class order and the numbering are settled together.
- The order of a closure frame class's type parameters, which follows the
  order the compiler first meets them and so can change when a type is
  written out. Each frame's parameters are put in name order, and every
  index reference to them follows.
- The same order for a generic literal's method: its declared parameters are
  put in name order, and each reference to it has its instantiation and the
  indices in the signature it writes out reordered to match.

## Checking real programs

The grid is rendered from a cell model, so its explicit programs are rendered
too. Any other program gets its explicit form from the compiler itself:
`--annotate-inferred` builds the program and prints it with the types the
build settled written in at every site that left them to inference - a
function literal's parameters and return, and a `let` local - rendered with
the same scope-relative names diagnostics use. `--annotate-inferred-in-place`
rewrites the files instead. Sites whose type cannot be written at that scope
are left as written and listed on standard error, with the count. So is a
literal's return presented at an argument-pack hop whose tuple carries element
names: the N-ary spelling the source would write there has no place for them.

```sh
dotnet publish/ghul.dll --annotate-inferred program.ghul > program.annotated.ghul
dotnet run --project tools/inference-oracle -- corpus integration-tests/execution <work-directory>
```

`corpus` takes a directory of programs, compiles each as written and again
annotated, and compares the IL as `check` does. A program is one of:

- a subdirectory holding a `test.ghul` (the integration-test layout; a
  options its `test.json` asks for are passed to every compile);
- a subdirectory holding a `.ghulproj`, or one level further down when a
  directory keeps several solutions as projects of their own;
- the directory itself, when it holds a `.ghulproj`, so one project such as
  the compiler can be checked on its own.

A project's sources are every `.ghul` its `GhulSources` items glob
(`src/**/*.ghul` when it has none), outside `bin/` and `obj/`, copied to both
working directories so the annotated program keeps the same files. Its
options are its unconditioned `GhulOptions` items, those of the nearest
`Directory.Build.props`, and the flags the ghūl build targets derive from
`GhulUnderscoreAccess`, `GhulGlobalNamespace`, `GhulDefaultUses`,
`GhulLibrary` and `OutputType`. Its references are written out in full,
since a compile given any discovers none: the .NET 10 targeting pack beside
the running .NET, and each package at the version it or the nearest
`Directory.Packages.props` pins, read from the package cache - so restore the
project first. Another project's output comes from `.assemblies.json`, which
has to be current. A project whose references cannot all be found is reported
as `·`.

```sh
dotnet run --project tools/inference-oracle -- corpus ../ghul-rosetta-code/tasks <work-directory>
dotnet run --project tools/inference-oracle -- corpus . <work-directory>
```

The verdicts are `=`, `≠`, `E` (the annotated
program does not compile) and `C` (the program itself does not compile, or is
recorded as not compiling). A program under `≠` or `E` is named in the output;
its two programs, disassemblies and `il.diff` are under the work directory as
for a cell, with the annotator's report in `explicit/annotate.out`.

Two more things the comparison ignores, both from writing a type out: the
purity attribute a literal's proven purity emits on its parameters and
return, and the namespace a file with no namespace declaration takes
from its path, which differs between the two working directories.

The type arguments of a generic call or construction whose callee is a name
are written after the callee, as `apply_n[(int, int), int](f, 1, 2)` and
`BOX[string]("x")`, unless the source already wrote them; a call is left
alone unless every one of its type arguments can be written.

What the annotator leaves to inference: a type still holding a placeholder,
ERROR or a type parameter foreign to the body; a type carrying `MAYBE`, whose
`T?` spelling is a different carrier when written back; a type
parameter another of the same name shadows at that scope; the type
arguments of a call whose callee is anything but a name; and those of a
construction through a type alias, which belong to the type the alias names,
or of `MAYBE`.

## Tests

The normaliser has tests of its own, beside the tool rather than in the
compiler's unit tests, since it reads disassembly text and nothing else:

```sh
dotnet test tools/inference-oracle/tests
```

Like the tool, they are not part of a normal build or the pull-request
suite.

## Machine-readable output

`--json <file>` writes the run as JSON beside the human-readable output:
each program's name, verdict and annotator counts in the order checked, the
verdict counts, and the annotator's totals. `compare-runs.sh` diffs two
such reports and prints, as Markdown, every program whose verdict changed
and every program new to the corpus that did not come out `=` or `·`;
it prints nothing when nothing changed.

## The scheduled run

`.github/workflows/oracle.yml` runs the four corpora nightly at 03:00 UTC
with the latest published `ghul.compiler` - the argument-pack grid,
`integration-tests/execution`, the Rosetta Code solutions at their default
branch, and the compiler's own source - and skips the night when that
compiler is the one the previous run checked. It is not a pull-request
gate: the four corpora take most of an hour, and a difference is worth
knowing about the morning after rather than on every push. A manual
dispatch runs it on demand; its `force` input runs it even when nothing
was published.

Each run writes its totals to the job summary and appends itself to the
`oracle-history` branch: one line per run in `totals.jsonl`, and the four
reports under `runs/<compiler version>/`, which the next run diffs its own
against. The tracking issue's body is rewritten with the latest totals,
and a comment goes on it only when a program's verdict differs from the
previous run. Nothing opens an issue per finding.

## Not in CI

A development tool, like `mdump`. Nothing builds it as part of a normal
build, and the pull-request suite does not run it; the scheduled run above
is the only automated use.
