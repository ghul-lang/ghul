# Assembly emitter

The CIL backend: lowers IR values to CIL and writes the compiled program out
as a .NET assembly, encoding metadata tables and method bodies through
`System.Reflection.Metadata`.

## The two passes, and why there are two

Metadata's run-style tables — a `TypeDef` pointing at the first row of its
field and method runs, with the run ending where the next type's begins — are
not validated. If the rows a type is written with do not match the count it
was numbered for, the assembly still loads, with the surplus members
reparented onto the following type.

So numbering and writing are separate passes over the same recorded sequence
rather than two independent walks of the symbol table. The table changes
between them: compiling a state machine's body declares the frame fields that
body needs, after numbering has run. A member that appears in between is
absent from the plan, and absent fails loudly at the first reference to it,
where misplaced would not fail at all.

`srm_emission_plan.ghul` is that recorded sequence.

## Files

- `cil_lowering.ghul` – lowers IR values to CIL. It implements the IR's
  value visitor; a value without a visit there yet still lowers itself in its
  own `gen`.
- `structured_lowering.ghul` – lowers structured nodes to the labels and
  branches the body emitter encodes.
- `cil_operations.ghul` – the opcodes the target-neutral operations encode
  as.
- `srm_assembly_emitter.ghul` – owns the metadata builder and the blob, string
  and user-string heaps; resolves references to imported types and members;
  writes the PE file.
- `srm_structure_walk.ghul` – walks the symbols to number the rows in the
  first pass and to write them in the second, including the synthesised
  members a lowering adds and the `MethodImpl` rows that bind a method to the
  interface member it implements.
- `srm_member_order.ghul` – the order types and their members are written in.
  A scope stores members in a map keyed by name, which is neither declaration
  order nor stable against unrelated edits, so this sorts on source position
  to recover declaration order — which a struct's sequential layout depends
  on. It also stands a namespace in for the `$globals` carrier holding its
  global functions and variables, since no symbol declares that type.
- `srm_method_body_emitter.ghul` – instruction-level surface for one body,
  backed by SRM's `InstructionEncoder`, returning the body offset the method
  row records.
- `srm_signature_encoder.ghul` – argument and return types as ECMA-335
  signature blobs.
- `srm_attribute_blob_encoder.ghul` – custom attribute value blobs, encoded
  from the resolved arguments.
- `srm_flags.ghul` – the metadata flag words for a definition, derived from
  the symbol's own predicates and kept out of the symbol classes.
- `srm_handles.ghul` – handles for the members a state-machine frame carries
  that no declaration names.
- `srm_pdb_builder.ghul` – the portable PDB: sequence points mapping
  instruction offsets back to ghūl source.

## Determinism

Emission is deterministic, which is what lets the bootstrap check
self-hosting by comparing two assemblies byte for byte (see
`../../../build/README.md`). The module version id is a content hash and the
PE timestamp comes from the same hash, so nothing carries the clock. Anything
added here that varies between two runs over identical input breaks that
check rather than showing up as a wrong program.
