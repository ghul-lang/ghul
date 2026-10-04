# Source library tests

Each test here is a real MSBuild project that compiles a program together
with one or more **source libraries** — libraries whose `.ghul` sources are
passed to the same compilation and attributed to a library with
`--library-source <name>@<version>=<root>`, passed through the project's
`GhulOptions` because MSBuild has no property for it yet.

They exercise what the compiler does with those declarations: a program
using a library, a library declared twice under two roots (included once),
and the two conflicting shapes — one library at two versions, and
overlapping roots — which are errors.

Run the suite with:

```sh
dotnet publish --output publish/
dotnet ghul-test --use-dotnet-build source-library-tests
```

As with `../cross-assembly-tests/`, the runner hands MSBuild the compiler
from the nearest `publish/` directory, and compares the build's errors and
warnings against `err.expected` / `warn.expected` and the program's output
against `run.expected`. See
[../integration-tests/README.md](../integration-tests/README.md) for the
file formats. Each test's library sources are its own private copy.
