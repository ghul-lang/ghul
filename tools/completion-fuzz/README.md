# completion-fuzz

Asks for member completion where a program is being typed, and checks the
answer against the program as it was finished.

The corpus is real code: the Rosetta Code solutions and the ghul.dev
examples. At a member access `x.name` the name was valid, so member
completion at the dot should offer it. That is the whole oracle, and it needs
no judgement: the removed name is either in the list or not.

Each site is asked about in three states:

| state | the text | models |
| --- | --- | --- |
| `control` | the finished file | completion in code that compiles |
| `line-cut` | the name and the rest of its line removed | typing a line in the middle of a file |
| `file-cut` | everything after the dot removed | typing at the end of a file |

A site where the control does not offer the name is a gap in completion
itself, whatever the file's state. The other two are judged only where the
control offers the name, so what they count is completion lost to the file
being incomplete.

## running it

The tool builds the compiler from the current source and spawns it as the
analyser, as the analysis tests do:

```sh
cd tools/completion-fuzz
dotnet build
dotnet bin/Debug/net10.0/completion-fuzz.dll \
    ../../../ghul-rosetta-code/tasks ../../../ghul-dev/examples \
    --limit 300 --per-file 2 --seed 7 --out completion-fuzz.tsv
```

Each argument that is not an option is a corpus root whose subdirectories
each hold one `.ghul` file. Files using the raster library are skipped, since
the analyser is given only the runtime's references, and so are examples
marked `// expect: error`. `--per-file` caps the sites taken from one file,
`--limit` caps the sites in the run, and `--seed` fixes which ones are taken.

To fuzz a published compiler rather than the current source, build with
`-p:SkipCompilerProjectRef=true` and set `ANALYSIS_TESTS_COMPILER_DLL` to
its `ghul.dll`.

The run prints a summary: for each of the two cut states, how many sites
offered the name, how many came back empty, and how many returned a list
without it. The TSV has one row per site and state, with the receiver text
before the dot, so failures can be grouped by what surrounds them.
