# Intermediate representation (IR)

This folder defines a small set of classes that model instructions close to .NET IL.  Most IR nodes simply wrap a single IL opcode but a few represent more complex operations such as null-safe access, synthesized equality or fused pipe loops.

The `generate_il` compiler pass produces these IR nodes, and the emitter under `emitter/` encodes them into a `.dll` or `.exe`.

Loops, `if`, `case`, `try`, `use` disposal, `val` blocks, assertions and comprehensions are built from structured nodes, which say what the control flow is rather than how CIL encodes it: a `LOOP`, `REGION` or `TRY` holds its body, `BREAK` names the node it leaves, and `CONTINUE` the loop it restarts. A `TRY` carries its catch handlers or its finally region, and the CIL protected-region markers are added when it is lowered. A generator's body is a `RESUMABLE`, and a state machine finds its place again through `DISPATCH` nodes, which jump to `RESUME_POINT`s. A structured node is lowered to labels and branches only when it is encoded.

A composite value whose IL branches, such as `?.` or a fused pipe loop, expands into the same structured nodes when it is generated, holding anything it needs after a branch in a local.

Useful files:

- `context.ghul` – the state the emission walk carries: the assembly emitter it is writing through, the body emitter for the method currently being walked, and the entry point once one is seen.
- `block_context.ghul`/`block_stack.ghul` – track nested blocks while emitting code.
- `label.ghul` – branch targets and the conditions an exit can test.
- `expansion.ghul` – builds the structured IR a composite value expands to.
- `values/visitor.ghul` – the visitor a backend implements to lower values; the CIL backend's is `emitter/cil_lowering.ghul`.
- `innate_operation_generator.ghul` – emits built in operator calls.
- `value_boxer.ghul`/`value_converter.ghul` – helper utilities for boxing and type conversion.

IR values themselves live under `values/` and are documented in that folder.
