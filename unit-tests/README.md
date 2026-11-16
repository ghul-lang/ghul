# Unit tests

The compiler's unit tests, run by the [ghul-testing](https://github.com/ghul-lang/ghul-testing)
runner. A test is a method marked `@test()` on a class with a public `init()`
that takes no arguments; the runner makes a new instance for each. Tests use
`assert`, and the assertions in `src/assertions.ghul`, which keep MSTest's
names (`are_equal`, `is_true` and the rest) over `assert`. The fakes and
fixtures more than one test file uses are in `src/shared/`.

The same sources build for two targets:

- .NET: `dotnet run --project unit-tests`, with ghul-testing found under
  `../libraries/ghul-testing`, or else beside this checkout or beside the
  primary checkout of a worktree; `-p:GhulTestingRoot=<path>` names another.
- llvm: `build/llvm-unit-tests.sh <work> <ghul-testing> <native compiler>`,
  which compiles them with the compiler's own sources, as listed in `<work>` by
  `build/llvm-self-sources.sh`, and runs them.

Arguments after `--` go to the runner: `--filter <pattern>`, `--shard <i>/<n>`,
`--list` and `--format text`. A file that only .NET can run starts with
`@@IF.dotnet()`, and a single test that only .NET can run is marked
`@IF.dotnet()`.
