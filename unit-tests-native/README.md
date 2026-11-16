# Unit tests on the ghul-testing runner

The compiler's unit tests, moving here from `../unit-tests/` a batch at a
time. Each test file is in exactly one of the two projects: a file moves with
`git mv` and `build/convert-unit-tests.sh`, which writes its `@Test()` marks
as `@test()` and drops MSTest. The assertions keep their names:
`src/assertions.ghul` declares them over `assert`. Once every file has moved,
this project takes the name `unit-tests`.

The same sources build for two targets:

- .NET: `dotnet run --project unit-tests-native`, with ghul-testing found
  under `../libraries/ghul-testing`, or else beside this checkout or beside the
  primary checkout of a worktree; `-p:GhulTestingRoot=<path>` names another.
- llvm: `build/llvm-unit-tests.sh <work> <ghul-testing> <native compiler>`,
  which compiles them with the compiler's own sources, as listed in `<work>` by
  `build/llvm-self-sources.sh`, and runs them.

A test is a method marked `@test()` on a class with a public `init()` that
takes no arguments; the runner makes a new instance for each. Arguments after
`--` go to the runner: `--filter <pattern>`, `--shard <i>/<n>`, `--list` and
`--format text`. A file that can only run on .NET starts with
`@@IF.dotnet()`.
