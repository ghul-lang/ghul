# WebAssembly module model and writer

The WebAssembly 3.0 module format: a model of what a module holds, and a
writer that encodes one as the binary format the specification defines.
It is the equivalent of the CIL emitter under `ir/emitter/` for the
WebAssembly target, and nothing in the compiler calls it yet.

This folder is a plain library. It depends on nothing else in the compiler
— no `IR`, no `Semantic` — so it can be read, tested and reasoned about on
its own, which is why the WebAssembly backend will be able to be built
against it one piece at a time.

The garbage collection types and instructions, the exception handling
instructions and the `.wat` printer are not here yet. The legacy `try`,
`catch` and `delegate` instructions are not planned at all.

## Files

- `byte_buffer.ghul` — the bytes a module is assembled in, and the
  primitive encodings: unsigned and signed LEB128 for 32- and 64-bit
  values, `f32` and `f64` as their bits little-endian, names behind
  their UTF-8 byte count, and vector lengths.
- `value_type.ghul` — the types a function can take and return and a
  local or global can hold, as the single byte each is encoded as.
- `block_type.ghul` — what a `block`, `loop` or `if` produces.
- `opcode.ghul` — every opcode, at the byte or bytes the specification
  gives it.
- `instruction.ghul` — the instruction classes, which differ by the
  immediate they carry rather than by meaning.
- `func_type.ghul` — a function's signature, and whether two signatures
  are the same shape.
- `limits.ghul` — a minimum size and, where one is given, a maximum.
- `table.ghul` — a table of references of one type.
- `global.ghul` — a global variable and its constant expression.
- `import.ghul` — the module, name, kind and descriptor an import is.
- `export.ghul` — a name, a kind and an index.
- `function.ghul` — a defined function: its signature index, its locals
  and its body. Also the run-length encoding of locals.
- `custom_section.ghul` — a section under a name the specification does
  not define.
- `module.ghul` — the module itself, and the index spaces its parts
  share.
- `binary_writer.ghul` — writes a module out, its sections in the order
  the specification fixes.

## The index spaces

A module's imports and its definitions share an index space per kind: an
imported function comes before every defined one, and the same for tables,
globals and, later, tags. So an index written into an instruction, an
export or a start position is not the position in the module's own list
but a position in that combined space.

`MODULE.add_function` and `MODULE.add_global` hand back the index the
entry takes in that space rather than its position in the list, so a
caller building bodies in order does not have to add the imported count
itself. Nothing is rewritten afterwards: an import added after a body was
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
the index an identical signature was already written at, so a module that
reaches for the same shape twice gets the same index. The comparison is
over the parameter and result types themselves, never over a rendering of
them.

## Testing

The unit tests are under `unit-tests/src/wasm/`, one file per class, and
pin exact bytes for every encoding primitive and for whole modules
whose bytes are written out in full. A mismatch is reported as the two
byte sequences, so a failure names the bytes rather than reporting that
two arrays differ.

Writing a module the specification accepts and writing one an engine
accepts are the same claim, so the whole modules were also checked with
Node's `WebAssembly.validate` while they were written: the empty module,
both whole-module fixtures, and one module per numeric opcode, so that
every opcode the enum names is covered by a module a real engine accepted.
That check is not part of the suite — Node is not a build dependency — and
it is what caught the `br_table` vector counting its default label as one
of its entries.