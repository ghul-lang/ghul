# Semantic analysis

The semantic layer sits between parsing and code generation.  It resolves names,
checks types and builds the high‑level intermediate representation (HIR).  Key
concepts include:

- **symbols** – `symbol_table.ghul` stores declarations and scopes.
- **types** – the `types/` subfolder defines `Type` and all concrete type nodes
  used throughout the compiler.
- **dotnet/** – helpers for emitting .NET metadata such as attributes and
  assembly info.
- **capabilities** – `capability.ghul` names the features a target can lack,
  `target_capabilities.ghul` answers for the .NET and WebAssembly targets, and
  `capability_checker.ghul` checks a use against them and reports the ones the
  target does not carry.

Most passes under `syntax/process` rely on these APIs.