# recovery-fuzz

Writes well-formed programs, breaks one line of each the way an editor breaks
it, and checks that the compiler still parses the rest of the file.

The property under test is not "how many errors" but "how much survived". A
program is written with three markers, each a read of a name that does not
exist: one in a definition ahead of the damage, one in the damaged body after
the damage, and one in a definition behind it. The compiler reports a marker
once it has parsed and resolved the line carrying it, and says nothing at all
about a line it never parsed - so the diagnostics say exactly which of the
three regions survived. The tail marker is the one that matters most: it is
the difference between resynchronising inside a body and dropping the rest of
it, which is what code completion and incremental editing both need.

The second property is that one mistake is reported in one place. Counting
errors cannot see a cascade, because the damage legitimately produces
semantic fallout wherever the code that depended on it was; what is counted
instead is the number of distinct source lines carrying a *parse* error.

## What it varies

Around the damage, seventeen contexts: bare statements at the file root,
global functions with block and expression bodies, methods of both kinds, a
trait's default method, a function literal nested in a function, a generator,
an asynchronous function, a property accessor, an operator, a `partial` block
over a union, a struct method, a primary-constructor class, a namespaced
file, a lambda in argument position, and a `case` used as an expression.

Four scales, because the small end matters as much as the large: `tiny` is a
handful of lines with no nesting and nothing around it, which gives recovery
almost nothing to resynchronise on, and `large` carries five sibling
definitions and four levels of `if`, `while`, `for`, `case`, `elif` and `try`
around the damage.

Half the innermost statements are plain assignments. The rest use the newer
syntax, whose brackets, clause keywords and nested bodies give recovery
different things to resynchronise on: a list comprehension and a lazy `{}`
one, a `T{}` local built with the collection constructors, `use` and
`let use ... in`, a generator literal, an argument-pack call and a call with
named arguments, and `cast(v)` with a scalar constructor.

One to three damage sites per program, since a half-written line rarely waits
for the previous one to be finished. Where several are applied, the oracle
expects only what all of them leave reachable.

The damage itself:

| Mutation | What it models |
| --- | --- |
| `truncate-file` | a method whose second half has not been written |
| `drop-value` | `x = ` with the cursor after it |
| `drop-line-tail` | a line cut at a random column, mid-typing |
| `drop-closer` | a closing keyword not typed yet |
| `swap-closer` | a closer belonging to another construct |
| `duplicate-closer` | a closer left behind by an edit |
| `drop-opener-keyword` | `if c` with no `then`, a header with no `is` |
| `drop-open-bracket` / `drop-close-bracket` | an unbalanced `(`, `[` or `{` |
| `insert-stray` | a token left where a statement should be |
| `delete-token` | one token gone, as a stray backspace leaves it |
| `replace-with-keyword` | a keyword where a name belongs |
| `unterminated-string` | a string with no closing quote |
| `unterminated-interpolation` | an interpolation with no closing brace |
| `drop-type-annotation` | a `: int` not typed yet |
| `drop-arrow` | a `->` or `=>` missing from a header |
| `drop-comma` | a separator missing from a list |
| `duplicate-line` | a line left behind by an edit |
| `swap-lines` | two lines in the wrong order |
| `reindent-block` | a block at the wrong indentation after a reformat |
| `paste-block` | a run of lines pasted in twice, closers and all |
| `join-lines` | two statements run together by a deleted line break |
| `split-token` | a line break in the middle of a token |

Each mutation declares which markers it leaves reachable, so a truncation is
not asked to preserve what it deleted.

## Running

```sh
dotnet build tools/recovery-fuzz
dotnet run --no-build --project tools/recovery-fuzz -- <work-directory> --count 200 --compiler publish/ghul.dll
```

Options: `--count <n>` cases (200), `--start <seed>` the first seed (1), a
seed always producing the same case - its context, scale, damage count and
damage kinds all come from it. `--compiler <ghul.dll>` the compiler to
test (`publish/ghul.dll`). `--spill <lines>` how many distinct lines may carry
a parse error before it counts as a cascade (2 - one place to report the
mistake, and one more for the closer that turned up instead).
`--timeout <seconds>` per compile (20). The exit status is non-zero if any
case failed.

Each case is left in the work directory as `<seed>-baseline` and
`<seed>-damaged`, so a failing one can be compiled by hand.

## Reading the output

| Verdict | Means |
| --- | --- |
| `.` | the markers the mutation left reachable all survived |
| `G` | the undamaged program did not compile as written - a generator bug |
| `H` | the compiler did not finish |
| `I` | the compiler crashed |
| `B` | the damage took out code written before it |
| `T` | the rest of the damaged body was lost |
| `A` | a definition after the damaged one was lost |
| `S` | one mistake was reported on too many lines |

A program is compiled before it is damaged as well as after, and has to
report exactly its three markers and nothing else. A generator bug therefore
shows up as `G` rather than being read as a recovery finding.

A marker counts as surviving only when it is reported as the name it fails to
find (`symbol not found: undefined_tail_marker`) on a line that carries no parse
error. Recovery that tries every stray token as a member can build a member
out of the line holding a marker, and the marker is then mentioned in its
diagnostics. That is not the statement or definition it was written as, and
nothing about it is analysed as one, so it is not counted. The tail marker is
written as `total = total + undefined_tail_marker` in a body that declares
`total`, so it counts only where `total` is found on its line too: a line read
outside its body, after the body ended early, reports `total` as not found.
The check reads lines and not definitions: a marker read into the wrong
definition, on a line with no parse error of its own, still counts.
