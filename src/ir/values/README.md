# IR values

IR value nodes represent operands and expressions during code generation. Each value has an optional `Type` and a meaning a backend can lower, whatever its target. A backend lowers values through the visitor in `visitor.ghul`; the CIL backend's lowering is `../emitter/cil_lowering.ghul`.

Important concepts:

- `value.ghul` – base class with common properties such as `type` and `has_address`.
- Subfolders `call/`, `load/`, `store/` and `literal/` hold calls, loads, stores and literals.
- `arithmetic.ghul` – built-in operators, described by the operation enumerations in `../operations.ghul`; `decimal.ghul` has the operators on decimal, which the runtime implements.
- `runtime.ghul` – an operation the runtime provides, such as concatenating strings or constructing the exception a failed assertion throws, named by `../runtime_operation.ghul`. Each backend maps these to its own runtime's members.
- Higher level nodes like `tuple.ghul` or `isa.ghul` stand for several steps; a `Composite` expands into simpler values when it is lowered.
- `block.ghul` groups a sequence of values.
- `structured.ghul` holds the structured control flow nodes, `LOOP`, `REGION`, `TRY`, `RESUMABLE`, `DISPATCH`, `RESUME_POINT`, `BREAK` and `CONTINUE`, which the CIL backend lowers to labels and branches.

Values are produced by the `generate_il` pass and handed to a backend a function body at a time.
