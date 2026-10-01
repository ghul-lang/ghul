# Intermediate representation (IR)

This folder defines a small set of classes that model instructions close to .NET IL.  Most IR nodes simply wrap a single IL opcode but a few represent more complex operations such as branching helpers or boilerplate generation.

The `generate_il` compiler pass produces these IR nodes, and the emitter under `emitter/` encodes them into a `.dll` or `.exe`.

Loops, `if` and `case` are built from structured nodes, which say what the control flow is rather than how CIL encodes it: a `LOOP` or a `REGION` holds its body, `BREAK` names the node it leaves, and `CONTINUE` the loop it restarts. A structured node is lowered to labels and branches only when it is encoded. Other control flow is built from labels and branches directly.

Useful files:

- `context.ghul` – the state the emission walk carries: the assembly emitter it is writing through, the body emitter for the method currently being walked, and the entry point once one is seen.
- `block_context.ghul`/`block_stack.ghul` – track nested blocks while emitting code.
- `brancher.ghul` – helpers for conditional and unconditional jumps.
- `structured_lowering.ghul` – lowers structured nodes to the labels and branches the emitter encodes.
- `innate_operation_generator.ghul` – emits built in operator calls.
- `value_boxer.ghul`/`value_converter.ghul` – helper utilities for boxing and type conversion.

IR values themselves live under `values/` and are documented in that folder.
