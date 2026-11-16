# argument-pack-grid

Writes the argument-pack conformance grid under
`integration-tests/execution/argument-pack-grid`: one integration test per
combination of how the combinator is reached, how the function filling a
`T.. -> U` formal is written, where it sits relative to the pack, what pins
the pack, and the arity.

The axes are lists in `src/grid.ghul`, so an axis gains a value by adding one
entry there. Cells the language rules out are skipped, and `skip_reason` says
why for each.

Every position is crossed with a global combinator. Only the positions marked
`crosses_callees` are also crossed with the other ways of reaching one - a
static or instance method, a call on `self`, and a class whose type parameter
is the pack - since the rest would multiply the grid for little that the
direct call and the pipe do not already exercise.

## Regenerating

Run from the repository root, after changing the generator:

```sh
dotnet run --project tools/argument-pack-grid -- generate integration-tests/execution/argument-pack-grid
dotnet ghul-test integration-tests/execution/argument-pack-grid
for t in integration-tests/execution/argument-pack-grid/*/ ; do [ -f "$t/failed" ] && ./tasks/capture.sh "$t" ; done
```

`generate` also removes any cell directory the grid no longer has. A cell whose combinators are declared over a .NET type, such as the delegate positions' `System.Converter`, gets a `targets` file naming `dotnet`, so a run that builds every test for another target passes it over.

## Reporting

```sh
dotnet run --project tools/argument-pack-grid -- report integration-tests/execution/argument-pack-grid
```

prints each cell's captured outcome as a Markdown table: `✓` compiles and
returns the right result, `C` does not compile, `W` returns a wrong result,
`X` throws, `·` ruled out by the language. A count of each distinct first
error follows the table.

## Layout

`src/grid.ghul` is the cell model and renders each cell's program.
`tools/inference-oracle` builds from the same file, so keep it free of
anything specific to generating the tests. `src/main.ghul` holds the
`generate` and `report` commands.
