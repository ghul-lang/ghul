# Compiler driver and analyser

The `Driver` namespace contains the entry point used by the stand‑alone
compiler tool.  `Main.ghul` parses command line arguments, configures the build
flags and orchestrates compilation.  When started with the `--analyse` flag the
same executable acts as a language service for Visual Studio Code.

Key files:

- `arguments_parser.ghul` &ndash; parses command line arguments into
  `BUILD_FLAGS`.
- `output_file_name_generator.ghul` &ndash; determines assembly and PDB file
  names.
- `path_config.ghul` &ndash; resolves library locations and working paths.
- `source_file_categorizer.ghul` &ndash; separates ghūl files from other inputs.

The driver is intentionally thin; most heavy lifting happens in the
`COMPILER` class found under `src/compiler`.  If you extend the command line
options or need to trigger additional compiler passes, update the logic here

## Compile server

`--compile-server` keeps one compiler process alive and compiles a series of
submissions in it, so each pays for its own few lines rather than for starting
a runtime and importing the reference set: a first submission takes about as
long as a batch compile, and each later one tens of milliseconds. It is the
backend for an interactive session, where every cell is compiled on its own to
a library assembly and later cells reference earlier ones.

The protocol is one JSON object per line each way. The first line out is
`{"ready":true,...}`. Each request line carries the submission's `name`, either
a `source` path or the source itself as `text` (whose diagnostics then name the
file `<name>.ghul`), the `output` assembly to write, and the `references` to
earlier submissions' assemblies. Each reply carries a `status` (0 when the
assembly was written, 1 when the source has errors, 2 when the request could not
be carried out, with a `message` saying why) and the `diagnostics`, in the
analysis protocol's shape. The request and reply types, and a client that runs
the server, are `COMPILE_REQUEST`, `COMPILE_REPLY` and `COMPILE_SERVER_PROCESS`
in the analysis-protocol library.

A request with `check` set and only `source` or `text` asks instead whether the
source is complete, as `--check-complete` answers it: the reply carries
`completeness`, one of `complete`, `incomplete` or `invalid`. A check parses
with state of its own and compiles nothing, so it leaves the session as it was,
and takes a few milliseconds warm.

Each request is answered as a batch compile of the same file with
`--submission <name> --library` and the same references would be: everything
the previous compile left is cleared first, and the only state kept is the
reference set, which grows as requests bring new references. A reference
naming an assembly the set already holds with different content, such as a
cell rebuilt under the same name, is refused with status 2: the set cannot hold
both, and compiling against the one already loaded would silently use the old
symbols. The analysis tests
hold the server to that by compiling each cell both ways and comparing the
assemblies.

## Build server

`--build-server` keeps one compiler process alive and runs whole builds in it,
one after another, so each pays for its own work rather than for starting the
runtime and compiling the compiler's own code again. Each line read from
standard input is the path of a response file holding a build's arguments. The
build runs with a container of its own, and its diagnostics go to standard
error as a process of its own would write them, followed by a line starting
U+0001 and `build-done` that gives the exit status. A line `quit`, or the end of
the input, ends the server. It is how an interactive session on the llvm target
builds each cell.

## Stripping annotations

`--strip-annotations <selection> <files>` parses each file and prints it through
the formatter with the chosen written annotations left out, for a tool that
rebuilds a program with less than its author wrote. Under a selection of
`list` it prints the numbered sites instead, one per line, each with the span
its annotation occupies, so a tool can edit the source in place rather than
reprint it. A selection is `all`, `list`, or comma-separated site numbers and
`a-b` ranges, and by default numbers locals' types, function literals'
parameter and return types, and calls' type arguments.

Two prefixes number one other kind of site, and only that kind:

- `cast:` numbers the targets of explicit casts: `cast double(n)` as `cast(n)`.
- `signature:` numbers the signatures of the functions in a file with
  top-level statements that could be written with no types at all: named,
  with a body, with no modifier but `memo` or `pure`, and with no `ref`
  parameter. A chosen one is printed with its type parameters, parameter types
  and return type left out, `step(n: int) -> int` as `step(n)`. A listed site reads
  `<n> signature <line>,<column> replace <start line>,<start column>,<end line>,<end column> <text>`:
  the span runs from the start of the name to the end of the last of the
  return type, the modifiers and the parameters (where it ends at a
  parameter, the closing `)` after it isn't in the span), and `<text>`, to the
  end of the line, is what the signature reads as without its types.

The mode is internal: it serves the annotation-stripping tools, and its output
format can change with them.
