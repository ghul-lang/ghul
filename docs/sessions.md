# ghūl: sessions and submissions

Read this file when you are working on the REPL, a notebook kernel or the playground. It continues sections of [GHUL.md](../GHUL.md), the language reference, under the same headings. GHUL.md is loaded with every session. This file is not.

## namespaces and `use`

`--submission <name>` compiles the file as one step of an interactive session. A step is the unit that a read-eval-print loop compiles. The file's namespace is `<name>`, not a namespace private to the file. A later step is compiled separately, against this step's assembly, and uses this step's definitions with `use <name>.thing`.

The steps of a session behave as one file. A step compiled with `--reference` naming an earlier step's assembly can see that step's underscore-named globals and types, as well as its public ones, as a later part of the same file could. An underscore-named member is still private to its class. This needs `ghul.runtime` 21.4.0 or later. With an older runtime, the underscore names of earlier steps are not visible.

The synthesised entry returns the value of the file's final expression to the code that runs it. When the file ends with a statement that has no value, the entry returns nothing.

A class or trait declared in a step is closed, as anywhere else. So a hierarchy declared across a session narrows, and is checked for exhaustiveness, exactly as a hierarchy declared in one file. The else edge of an `isa` test reaches the sibling, and a `case` that covers every subclass needs no `else`. A session adds one thing: a later step can extend such a type, which an ordinary consumer cannot. A step compiled with `--reference` naming an earlier step's assembly can subclass a closed class that the earlier step declared, and can implement a closed trait that the earlier step declared, because the steps are one program written in parts. Unions are not affected, because a union can never be extended.

So an earlier step's compiled code can have a view of a hierarchy that a later step has made incomplete. A submission build adds two checks for this:

- A narrowing that reached its type by excluding every other alternative is checked where the value is used. A value of a type added later throws `Ghul.InvalidCastException`, which names both types. The value is never used as a type it is not.
- A `case` that covered every alternative, and so has no `else`, throws `Ghul.AssertFailedException` when no arm matches. It never continues without running an arm.

The compiler emits these checks only under `--submission`. An ordinary build knows every alternative, and emits neither check.

A top-level `let` whose initializer names the variable it declares, as `let total = total + 1` does, reads the variable of that name declared by an earlier step, when the file imports it. A step uses this to redefine a name in terms of its old value. In any other place, and in a submission that has no such import, the name does not exist inside its own initializer, and reading it is an error. A submission is built with `--library`, because the session's host decides when its entry runs, not the runtime.

`--cells` builds a whole session as one program. Every file with no namespace is a cell, and the cell's namespace is its file name. So a later cell uses `cell1.thing` with `use cell1.thing`. A cell's top-level statements become `cell1.entry(args, env)`, which returns the value of the cell's final expression, or nothing when the cell ends with a statement that has no value. A cell is never the program's entry point. The program declares its own entry point, which calls each cell's entry in the order that the session ran the cells.

The command line names the cells in that same order. A cell's inferred variables get their types as the cell's statements compile, and a later cell that reads one needs its type to be known. A cell can define a variable in terms of an earlier cell's variable with the same name, as a submission can.

A build with `--cells` or `--session` also writes each cell's importable names next to the output, as `<stem>.cells.json`. The file has one entry for each cell. Each entry holds the cell's namespace name, and the public types, global functions and global variables that a later cell can write after `use cellK.`. Underscore names are included, because a later cell of the same session can use them. A host that cannot read an assembly from the build builds its prelude from this file.

`--session` builds the cells as `--cells` does, and adds what code kept across cells needs. A session keeps its earlier cells in use while it adds later cells. Each cell was written against the hierarchy that the cells before it declared. So the compiler makes a closed-hierarchy decision in a cell's code over the alternatives that those earlier cells declare. A `case` that covers every alternative that its cell could see is exhaustive. The else edge of an `isa` test narrows to the one alternative left.

What a cell could not see is checked at run time, exactly as in a submission build:

- The `case` throws `Ghul.AssertFailedException` when no arm matches.
- A narrowed value is checked where it is loaded, and throws `Ghul.InvalidCastException`, which names both types.

Plain `--cells` has no such checks, because there the whole session is one view.

A session also compiles its classes as open, for the dispatch that the compiler reasons about. The compiler treats a call to a method that nothing overrides as a call to a method that a later cell could override. So a session's classes do not get the store-free proofs, and the narrowings that last across calls, that an ordinary closed class gets.

The cells are compiled against the cells before them only for these closed-hierarchy decisions. A name that any cell declares is visible to every other cell, as under `--cells`.

`--cell-link <n>` builds one cell of a session whose cells are separate objects. Each cell is compiled on its own, and loaded into one running process after the cells before it. This is for the llvm target, with `ghul-llvm --emit=cell` and its cell host.

- The `n` cells named before the last cell are the cells already loaded. The compiler reads their sources to learn what they define, and emits none of their code. It names their functions, variables, classes and descriptors as externals, which the loader resolves when it loads this cell.
- The last cell's definitions are exported for later cells. Its entry is the entry that the host runs.
- A cell that only defines things has no entry to run, and the compiler does not report a missing entry.
- A cell's final expression is not returned as an exit status. When the final expression has a value, the entry writes the value to standard output as `Ghul.inspect` shows it. The value follows one byte U+0002 at the start of a line, and is followed by a newline. A host or front end finds the value by that mark.
- A source library that the cells share, such as ghul-runtime, is not a cell. Each cell includes the parts of the library that it uses, and shares them with the other cells by name. So a library class, and a generic type instantiated with the same type arguments, are one type in every cell.

`--cell-link` implies `--session`, so the rules above apply. Its types and classes follow the rules of a build whose classes a later cell can extend. A later cell can subclass a class that an earlier cell declared and override its methods, and code compiled earlier dispatches to the override. Everything that the cells print, hold and change lasts as long as the process does.

These are not supported across cells, and each is reported where it is written:

- a type test or cast against an array type
- a call to a trait method that is itself generic
- a trait instance that only a later cell widens to by variance

`--cell-link 0` compiles the first cell.
