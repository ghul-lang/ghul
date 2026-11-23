# LLVM IR module model and writer

A model of what an LLVM module holds, and a writer that prints one as the
textual IR the LLVM Language Reference defines, the `.ll` form. It is what
the LLVM backend writes through. Nothing in the compiler calls it yet.

This folder is a plain library. It depends on nothing else in the compiler
- no `IR`, no `Semantic` - so it can be read, tested and reasoned about on
its own. The compiler references it and ships it in the `ghul.compiler`
package, as it does the WebAssembly writer under `wasm/`.

The text is written for the LLVM the `ghul-llvm` tool is built from, LLVM
23, with opaque pointers only.

## The files

- `type.ghul` - `Type`, every type a module can name, and `Types`, the
  common ones.
- `value.ghul` - `Value`, an operand: a local or global by name, or a
  constant. Every value carries its type. `Values` makes the common ones.
- `attribute.ghul` - `Attribute`, and the `Linkage`, `UnnamedAddress` and
  `CallingConvention` enumerations.
- `type_definition.ghul`, `global_variable.ghul` - a named struct type and
  a global variable.
- `function.ghul` - `FUNCTION` and `PARAMETER`, and the check a definition
  is held to before it is written.
- `block.ghul` - `BLOCK`, with a method per instruction that appends it and
  returns the value it produces, and `INSTRUCTION`.
- `operation.ghul` - `Operation`, what an instruction does, and the
  enumerations its operands use.
- `intrinsics.ghul` - declarations of the intrinsics the backend calls.
- `metadata.ghul` - `Metadata`, `MetadataNode` and the debug information
  nodes source lines and variables need.
- `module.ghul` - `MODULE`, which holds everything above in the order it
  was added.
- `names.ghul` - how names and quoted strings are spelled.
- `writer.ghul` - `WRITER`, which prints a module or any part of one.

## Choices the format leaves open

**Every value has a name.** LLVM numbers an unnamed value implicitly, and
the numbers have to run in order without gaps, which is easy to break and
hard to see broken. Nothing here is unnamed: a block's methods name each
result from its function's counter, `t0`, `t1` and so on, and a name made
only of digits is quoted, so it can never be read as one of those numbers.
Parameters, blocks and results share one namespace per function, as they
do in LLVM, and `FUNCTION.check` refuses a name used twice.

**A name is quoted only when it has to be.** A name of letters, digits and
`-$._` not starting with a digit is written as it stands; any other is
quoted, with a byte that is not printable ASCII, a quote or a backslash
written `\XX`. Metadata names cannot be quoted, so they escape the same
bytes without quotes.

**An integer constant is written as the signed value of its bits.** The
model holds an integer of any width as a `bigint`, and writes the value its
bits stand for read as signed, so an `i8` of 255 is written `-1`. An `i1`
is written `true` or `false`.

**Floating point constants are written in hexadecimal.** Hexadecimal is
exact, where a decimal form has to be checked for round-tripping. A
`double` is written as its own bits. A `float` is written, as LLVM
requires, as the bits of the `double` of the same value; the conversion is
done on the bits rather than by the hardware, which would quiet a
signalling NaN. A `half` is written `0xH` and its own sixteen bits.

**Attributes are written inline.** LLVM's printer gathers function
attributes into numbered groups, `#0`, but the inline form means the same
thing and needs no second table to keep in step.

**A call writes the callee's whole type only when it is variadic.** That is
the one case LLVM needs it; otherwise the result type alone, as LLVM's
printer writes it.

**A declaration names no parameters.** Only a definition's body can use
them.

**A named struct constant is written packed or not by its definition.**
The writer looks the name up in the module being written. Written on its
own, outside a module, it is taken to be unpacked.

**A subprogram that is not a definition carries `spFlags: 0`.** LLVM reads
a `DISubprogram` with no flags as a definition.

**Metadata can be attached to an instruction and to a function definition,
not to a declaration.** Nothing the backend writes needs the third.

**A block can carry a current debug location.** While `debug_location` is
set, every instruction the block appends carries it as `!dbg`, which is how
an instruction gets the location of the statement it was written for
without each call naming it.

**The writer refuses what it can see is wrong.** A definition whose blocks
do not each end in exactly one terminator, a branch to a block another
function owns, a flag an operation does not take, a declaration with a
linkage only a definition can have. It does not type-check: a module that
gets an operand's type wrong is written as it stands, and LLVM rejects it.

## Testing

The unit tests are under `tests/`, one file per class, and pin exact text
for every type, constant, attribute and instruction, and for small whole
modules.

`tests/matrix.ghul` holds the whole modules the library is checked against
LLVM itself, one named method each, and covers every shape the library can
produce, so adding a shape means adding a module there. `tests/llvm-check.sh`
writes every module of the matrix and runs `llvm-as`, `opt -passes=verify`
and `llc` to an object file on each. LLVM is not a build dependency, so the
check is not part of `dotnet test`; CI runs it after the unit tests. The
script looks for the tools in `$LLVM_BIN`, on the `PATH`, with a `-23`
suffix as Debian's packages install them, and under `/usr/lib/llvm-23/bin`,
and fails when it finds none rather than passing by checking nothing.

One thing the check caught is worth recording, since the Language
Reference does not say it: a `DISubprogram` written without `spFlags` is
read as a definition, which is why a declaration writes a zero.

What the matrix covers:

- `empty`, `header` - nothing at all, and the source file name, data layout
  and target triple.
- `types`, `constants`, `globals` - every type, every kind of constant,
  including a signalling NaN and a subnormal, and every linkage a global
  can take.
- `declarations`, `attributes`, `names` - function declarations, the forms
  of attribute, and names that have to be quoted or escaped.
- `memory`, `integer-arithmetic`, `float-arithmetic`, `comparisons`,
  `conversions`, `aggregates` - every instruction that is not a call or a
  terminator, with every flag each one takes.
- `atomics` - atomic loads and stores, `cmpxchg`, every `atomicrmw`
  operator, and `fence`, with each ordering that each one takes.
- `calls`, `control` - direct, indirect, variadic, tail and fast calls, and
  the terminators.
- `exceptions` - invoke, a landing pad that cleans up and catches, and
  resume.
- `intrinsics` - every intrinsic `Intrinsics` declares, called.
- `metadata`, `debug-info` - plain and named metadata, attachments, module
  flags, and enough debug information that the object `llc` writes carries
  source lines and variables.
