# WebAssembly module model and writer

The WebAssembly 3.0 module format: a model of what a module holds, and a
writer that encodes one as the binary format the specification defines.
It is the equivalent of the CIL emitter under `ir/emitter/` for the
WebAssembly target, and nothing in the compiler calls it yet.

This folder is a plain library. It depends on nothing else in the compiler
— no `IR`, no `Semantic` — so it can be read, tested and reasoned about on
its own, which is why the WebAssembly backend will be able to be built
against it one piece at a time.

The legacy `try`, `catch` and `delegate` instructions are not planned at all, and neither are memories
or data segments - though the two array instructions that name a data
segment are, since an index into one is written the same way whatever
holds the segment.

## The index spaces

A module's imports and its definitions share an index space per kind: an
imported function comes before every defined one, and the same for
tables, globals and tags. So an index written into an instruction, an
export or a start position is not the position in the module's own list
but a position in that combined space.

`MODULE.add_function`, `MODULE.add_global` and `MODULE.add_tag` hand
back the index the entry takes in that space rather than its position in
the list, so a caller building bodies in order does not have to add the
imported count itself. Nothing is rewritten afterwards: an import added after a body was
built changes what that body means, so a module is built imports first.

## Choices the specification leaves open

**An empty section is left out.** A section with nothing in it is legal
but carries a byte of identifier and a byte of zero length that say
nothing, so a module writes only the sections it has. An empty module is
the eight bytes of the preamble.

**Both forms of `select` are modelled.** The untyped form infers its
operand type from the values, which has to be a numeric or a vector type;
the typed form carries the type and is what lets it work over a reference
type. Modelling only the first would mean widening the instruction when
the reference types arrive.

**A module can carry custom sections.** The `name` section that gives a
function or a local a readable name is one, and it needs somewhere to
live from the start rather than a change to the model when it does.

**Tables are modelled, element segments are not.** `call_indirect` reads
a function reference out of a table, so a module using that instruction
has to declare one; without a declared table there is nothing for it to
read from and the module does not validate. Element segments, which fill
a table in, come with the garbage collection types.

**Function types are deduplicated by shape.** `MODULE.add_type` hands back
the index an identical type was already written at, so a module that
reaches for the same shape twice gets the same index. The comparison is
over the types themselves, never over a rendering of them. A recursion
group is never deduplicated: the group is what a type inside it may name,
which is not the same thing as its shape.

**The two element forms that leave the table out also leave out the
element type.** An active segment on the first table holding function
references is the only one that can, since leaving the type out fixes it
at `funcref`. A segment of any other element type on that table names its
table after all, which is how a table of references to declared types is
filled.

**A field's mutability byte is always written.** The format leaves it out
for a field that cannot be assigned through, and an engine here rejects
the omission.

**A `sub` with no supertypes is written as a `sub`.** The marker, not the
length of the supertype list, is what makes a type open, and an open type
with no supertypes is how a base type other types are declared as subtypes
of is written.

## Testing

The unit tests are under `tests/`, one file per class, and
pin exact bytes for every encoding primitive and for whole modules
whose bytes are written out in full. A mismatch is reported as the two
byte sequences, so a failure names the bytes rather than reporting that
two arrays differ.

Writing a module the specification accepts and writing one an engine
accepts are the same claim, so the whole modules were also checked with
Node's `WebAssembly.validate` while they were written: the empty module,
the whole-module fixtures, and one module per numeric opcode, so that
every opcode the enum names is covered by a module a real engine accepted.
That check is not part of the suite — Node is not a build dependency — and
it is what caught the `br_table` vector counting its default label as one
of its entries, and the short form of a `const` field being rejected.

The garbage collection modules are checked the same way. Every one of
them is accepted: a struct with a field written, a struct read through
`struct.get`, an array read through `array.get`, an array of a fixed
length, a null reference tested for absence, a struct holding a reference
to another struct, and a recursion group whose two members hold a reference
to each other. Two more cover `ref.test` and `ref.cast`, and a cast
branch.

`call_indirect` takes an index into the table it calls through, which is
how the engines available read it, and the `calls` module is the one that
exercises it against an engine.

Two things that check turned up are worth recording, because in both the
instruction index writes the *type* an instruction produces where a reader
can take it for the immediate it takes. `ref.test (ref null ht)` is the
type the instruction produces; the immediate is the heap type alone, and
whether the reference can be absent is in the opcode, which is why there
are four of them rather than one. And `br_on_cast` takes the nullability
of its two heap types in a flags byte ahead of the label, not in the types.

## The `.wat` printer

`wat_printer.ghul` prints a module as WebAssembly text format, in the
flat form: one instruction a line, the structured instructions indented
and closed by the `end` and `else` the binary spells with bytes. Folded
form was considered and not taken - flat is what the standard tools
print by default, which is what makes the output comparable against
them at a glance.

The parts are printed in the order the binary sections have them -
types, imports, tables, tags, globals, exports, the start function, the
element segments, and the functions last - which is what keeps the
printing stable rather than merely correct. A final type with no
supertypes prints as the plain type definition the text format
abbreviates it to. Definitions an instruction can reach by index carry
it as the `(;N;)` comment the standard tools print, and where the
module carries a name section, its names are used: the module's own
name after `module`, a function's after `func`, a local's after
`local`, and a reference to a named function or local reads as the name
rather than the index.

The printed text is checked by reassembling it with a reference
assembler and comparing against the bytes the writer produces, the same
outside-the-suite check the engine run makes.

## The module matrix

`tests/matrix.ghul` holds the whole modules the library is checked
against: one named method each, building a module of one shape. The
per-class tests pin exact bytes for the encodings and for small modules;
the matrix is for the other claim, that the bytes the writer produces are
the bytes an engine accepts, and it holds every shape the library can
produce so that adding one means adding a method here rather than
remembering to write a module for it.

`tests/matrix_tests.ghul` writes every module of the matrix and checks the
preamble, which is what the suite can do on its own. Whether the bytes are
ones an engine accepts is the job of `tests/engine-check.sh`, which dumps
every module of the matrix and hands each to every engine it can find:
Node's `WebAssembly.validate`, and Wasmtime's `compile` with exceptions and
garbage collection enabled when it is on the `PATH`. Neither engine is a
build dependency, so the run is not part of the suite; it is run while the
tests are written and its result recorded in the pull request. A module an
engine rejects is wrong, however carefully the encoding was reasoned about.

Two engines are worth running because each has caught what the other read
past. Node's validator is the strict one on encoding shapes - it rejects
the short form of a field's mutability byte, which the format permits -
and Wasmtime carries the fuller instruction set, which is what confirmed
the four `try_table` clause kinds and the reference instructions end to
end.

What the matrix covers, and why each module is there:

- `empty`, `start` - the preamble alone, and the smallest module that
  names a function, exports it and starts at it.
- `imports`, `globals`, `tables` - one import of each kind, and the index
  spaces the defined entries then join. `tables` names the second table of
  a shared index space, which is the case a table index gets wrong.
- `control` - the three block types, a branch to each, and a branch table.
  The block typed by a signature is there because a block like that has to
  consume its operand in its own body: an empty body leaves the operand on
  the stack at the end, and that is a program that does not validate
  rather than an encoding that is wrong.
- `numeric-i32` to `numeric-f64`, `conversions` - one function per opcode
  of each family, so an engine has read every numeric opcode the library
  can emit, and the conversions with the constant each one reads.
- `struct`, `array` - the reads and writes of both composite shapes,
  including the packed fields, which are the ones that reach the
  sign- and zero-extending instructions.
- `references`, `cast-branches`, `i31-extern` - making and testing
  references, comparing two, the four tests and casts, the branches that
  carry a reference, the i31 instructions and the extern conversions.
- `element` - all eight forms of element segment, which is every
  combination of mode, element type and table the format gives a form to.
- `rec-group` - two types that name each other, which is what a recursion
  group is for and what two groups of unrelated types would not have
  needed.
- `calls` - a direct call, one through a table and one through a reference
  read out of that table.
- `exceptions` - one function per kind of `try_table` clause, each
  throwing the one tag and handling it with the kind it is named for.
  The tag's signature is its payload alone, which is the parameters of
  the type it names and never its results. A clause's label counts the
  instructions around the `try_table` rather than the `try_table`
  itself - label 0 is the block enclosing it - and the handler it names
  takes what the clause delivers in its results: the payload for
  `catch`, the payload and the exception reference for `catch_ref`, the
  reference alone for `catch_all_ref`, and nothing for `catch_all`.
- `name-section` - the names of the module, its functions and their
  locals, attached to a module whose functions and locals are worth
  naming.
- `typed-block` - a block whose signature takes an operand, which the
  block's body has to consume: an empty body leaves the operand on the
  stack at the block's end, and that is not the block's fallthrough.
