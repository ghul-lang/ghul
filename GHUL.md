# ghūl language tutorial and reference

ghūl is a statically typed, general-purpose programming language that targets .NET 10. It is a hobby project, but expressive enough for general-purpose work — the ghūl compiler is itself written in ghūl. It produces ordinary .NET assemblies and NuGet packages, and ghūl code can consume any .NET library.

Apart from a slightly quirky syntax, ghūl is a fairly conventional language. The syntax is influenced by ALGOL 68 and Pascal: blocks are delimited by keywords rather than braces or indentation, and the keywords come in pairs whose closing half mirrors the opening one — a class or function body runs `is` ... `si`, a conditional runs `if` ... `fi`, a `try` ends with `yrt`.

This file is a condensed single-file reference. The full documentation, with a page per topic, is at <https://ghul.dev>; setup instructions are at <https://ghul.dev/getting-started.html>. Each section below links to the page that covers it in depth.

## naming conventions

ghūl keywords are lowercase. Identifiers follow a convention that the compiler partly enforces:

- `snake_case` — variables, functions, methods, properties
- `PascalCase` — namespaces, traits, abstract classes, unions, enums
- `UPPER_SNAKE_CASE` — concrete classes, structs, variants, enum members

A `static` field or property reads as a named constant, so it accepts either `snake_case` or `UPPER_SNAKE_CASE`.

A leading underscore (`_name`) marks a declaration as non-public — there are no `public`/`private` keywords, the naming convention carries that information. Whatever it is attached to, an underscore-prefixed name is **private to the assembly it is declared in**: another assembly cannot see it at all, and a reference to one from outside is a compile error.

Within the assembly the rule differs by kind. A **member** — method, field or property — is restricted further, by default to its own declaring class. A **type**, **global function** or **global variable** has no declaring class to be narrower than, so for those the underscore means exactly "private to this assembly" and nothing more.

How far the member restriction reaches is chosen with a compiler flag:

- `--underscore-access private` (the default) — an underscore member is visible only to its declaring class.
- `--underscore-access protected` — widens that to the declaring class and its subclasses within the same assembly.
- `--underscore-access legacy` — the historic behaviour: no compile-time enforcement at all, and underscore methods and types are emitted public, so they escape the assembly.

An out-of-policy reference from elsewhere *inside* the assembly is reported as an error, but the access is allowed through rather than being cut, so the diagnostic never cascades.

The compiler warns when a ghūl-source declaration doesn't match the convention for its kind. Each rule has its own slug, suppressible per declaration, per file, or project-wide:

- `non-snake-case-name` — variables (including `let`, `for` and `catch` locals, and function arguments), functions, methods, properties.
- `non-pascal-case-name` — abstract classes, traits, unions, enums.
- `non-upper-snake-case-name` — concrete classes, structs, variants, enum members.

An identifier is written in whatever script its author writes in. A letter of any script starts one, and a letter, a digit, a combining mark or a connecting punctuation mark continues one, which is the set C# admits less the format characters: a zero-width joiner or a bidirectional control renders as nothing, so a name carrying one reads as a name it is not, and one inside an identifier is an error naming the character. Only the basic plane is covered, since a character above it is written as a surrogate pair and the scanner reads that as two characters. A symbol is an operator character and a letter is an identifier character, so no character is ever both, and an operator spelled `×` and an identifier spelled `naïve` are each what they look like.

The conventions above are read with Unicode case. A character that has an upper and a lower form is checked whatever script it is in, so `ТИП` is a concrete class and `μέγεθος` a property. A character with neither form says nothing about case, so a name written entirely in a script that has none — Chinese, Japanese, Arabic, Hebrew — is correct as any kind and draws no warning.

A class with only `static` members (and no primary-constructor parameters) is a static-utility container — never constructed — and accepts either PascalCase or UPPER_SNAKE_CASE.

## namespaces and `use`

See <https://ghul.dev/definitions.html#namespaces>.

Code is organised into namespaces — `namespace`, a name, and an `is` ... `si` body:

```ghul
namespace MyApp.Utilities is
    class HELPER is
        ...
    si
si
```

Namespaces nest, and a dotted name (`namespace Outer.Inner is ... si`) is shorthand for nesting. A namespace definition is an *instance* of that namespace; instances are aggregated across every source file, so a definition made in one file's `namespace Example` is visible unqualified from every other `namespace Example` block in the project.

A source file with no namespace declarations has its definitions placed in a namespace the compiler synthesises, private to that file — convenient for small programs and tests. Compiling with `--global-namespace` instead aggregates every such file's definitions into a single unnamed global namespace shared across the project, so a global defined in one file is visible from the others. Once a file declares any namespace, every definition in it must sit inside a namespace.

A namespace-less file may also carry bare statements at the file root. They run, in source order, as the program's entry point — so a short program needs no `entry` function — and may be interleaved with global definitions, which are visible regardless of where they appear. A file cannot both carry top-level statements and declare a namespace.

The top-level statements are collected into a synthesised entry-point function, and a `let` among them declares a global variable: readable by the top-level statements after it, and inside the functions and types the file defines below it. The entry takes the two shapes the runtime can hand an entry point (see [functions](#functions)): the statements can read the command-line arguments as `args` and the process environment as `env`, and a private `_entry(args: string[])` wrapper is what actually carries them in. Those two names are the entry's own parameters, so a `let` declaring a global variable named `args` or `env` is rejected — use another name. A `let` of either name inside a nested block among the statements is an ordinary local and shadows the parameter as anywhere else. Its type is inferred exactly as a local variable's is. A bare `let` stays unassignable everywhere; a `let ... mut` can be reassigned from later top-level statements and from functions alike, so it is genuinely shared state. A `let` among the top-level statements is a statement, so it is in scope from where it is written and no earlier: reading or assigning one anywhere above its `let` is an error, whether from another top-level statement, from a function literal one of them writes, from inside the `let`'s own initializer, or from the body of a function or type the file defines above it. The statements run in order, so above the `let` the value would not exist yet. Writing the reader below the `let` is what says it is meant to see one. This is a rule about where the name is written rather than a guarantee about when the code runs — a function written below the `let` can still be called from above it — but it is the same rule for every reader, and it says what the `let` was for. State the whole file is meant to see regardless of order is a namespace-scope declaration (`count: int;`), which is a definition rather than a statement and so has no position to be read above. A `let` inside a nested block among the top-level statements stays an ordinary local of that block. It shares the file's namespace with the file's other definitions, so a top-level `let` and a global function, global variable or type of the same name are a redefinition error.

The synthesised entry point is a file-private definition like any other, so more than one file in a project may carry top-level statements — an umbrella project globbing a directory of one-file examples, say. Only one of them can be the program's entry point, and what picks it is the same thing that picks any other: an `@entry` pragma first, then a function the `--entry` name matches (`entry` when the flag is not given), then a file's top-level statements. Naming an entry point with `--entry` takes top-level statements out of the running altogether, since a build that asks for one by name does not want statements from some other file instead.

Compiling with `--submission <name>` treats the file as one step of an interactive session, the unit a read-eval-print loop compiles. The file's namespace is `<name>` rather than one private to the file, so a later step, compiled separately against this one's assembly, reaches its definitions with `use <name>.thing`. The session reads as one file across its steps: a step compiled with `--reference` naming an earlier step's assembly sees that step's underscore-named globals and types as well as its public ones, as a later part of the same file would, and an underscore member stays private to its class. That needs a `ghul.runtime` of 21.4.0 or later; with an older one the underscore names of earlier steps are not visible at all. The synthesised entry returns the value of the file's final expression, or nothing where the file ends on a statement with no value, to whatever ran it. A class or trait the file declares is closed as it is anywhere else, so a hierarchy declared across a session narrows and is checked for exhaustiveness exactly as one declared in a file does - an `isa` test's else edge reaches the sibling, and a `case` covering every subclass needs no `else`. What a session adds is that a later step may extend such a type anyway, where an ordinary consumer may not: a step compiled with `--reference` naming an earlier step's assembly can subclass a closed class it declared and implement a closed trait it declared, since the two steps are one program written a piece at a time. Unions are unaffected and always were, as a union cannot be extended at all.

That leaves an earlier step's compiled code holding a view of the hierarchy that a later step has made incomplete, and a submission build guards the two places where that matters. A narrowing that reached its type by eliminating every other alternative is checked where it is used, so a value of a type added later raises `System.InvalidCastException` naming both types rather than being read as the type it is not. A `case` that covered every alternative and so carries no `else` raises `Ghul.AssertFailedException` rather than running no arm and carrying on. Both are emitted only under `--submission`; an ordinary build knows every alternative and emits neither.

The guards say what went wrong rather than making the earlier step right: its compiled code still assumes the hierarchy it was compiled against, and what makes it correct again is running that step again against the hierarchy as it now stands.

A top-level `let` whose initializer names the variable it declares, as `let total = total + 1` does, reads the variable of that name an earlier step declared, where the file imports one; it is how a step redefines a name in terms of what it held. Anywhere else, and in a submission with no such import, the name does not exist yet inside its own initializer and the read is an error. A submission is built with `--library`: the session's host, not the runtime, decides when its entry runs.

Every file whose top-level statements are left unselected is told so, as a `top-level-statements-not-run` warning at its first statement — the statements do not run, so a `let` among them never initializes. Suppress it project-wide with `--suppress top-level-statements-not-run`, or take it as a hint with `--warn-as-hint`, in a project where several script files under one build is the intended shape. Where several files carry top-level statements and nothing names an entry point, none is chosen, every one of them warns, and an executable build reports that it has no entry point.

An ordinary pragma wraps the one definition or statement written after it, which gives it nowhere to reach a warning reported at a top-level statement — there is no wrapping definition to attach to. `@@pragma(...)`, doubled at, is a **file-level** pragma: written before everything else in the file, one or more of them cover the whole file rather than one definition. `@@suppress("slug")` reaches every diagnostic in the file, top-level statements included; `@@precedence(...)` sets an operator's precedence for the rest of the file's parse, with no restore at the end the way the per-definition `@precedence` has. A `@@` pragma anywhere but the very start of the file — after a `use`, a definition, or a top-level statement — is an error:

```ghul
@@suppress("top-level-statements-not-run")

use IO.Std.write_line;

write_line("hello");
```

A file's first two bytes may be a `#!...` line, in the style of a Linux shebang naming an interpreter. The compiler recognises the line only there, as the very first thing in the file, and skips it, so a file carrying one still compiles; it is otherwise invisible to parsing, including to the rule above that a file-level `@@` pragma must be the first thing in the file, so a `@@` pragma is written immediately after the shebang line rather than instead of it.

The `use` statement brings names into scope so they can be referred to without qualification. Applied to a namespace it imports every public symbol; applied to a single symbol it imports just that one:

```ghul
use IO.Std.write_line;            // a single static method
use IO;                           // every public symbol in the namespace
use Console = IO.Std;             // import under a different name
```

A `use` applies only within the current namespace block — if a namespace is split across blocks or files, each block needs its own `use` statements.

`use X.*` imports every usable member of `X` at once, where `X` names a namespace, a class, a struct, a union or an enum. On a namespace this is the same import a bare `use X;` already gives, since a namespace's members are reachable unqualified either way. On a class, struct or union it imports every static field, property, method and operator, and — for a union — every variant; instance members and constructors are never imported, since neither means anything without a receiver. On an enum it imports every member. Each name comes into scope exactly as if it had been `use`d on its own, so a name a wildcard import happens to collide with is the ordinary duplicate-use error:

```ghul
use Collections.*;               // every public symbol in the namespace - same as `use Collections;`
use MATH_CONSTANTS.*;            // every static member of a class
use Suit.*;                      // every member of an enum
use Result.*;                    // every variant (and static member) of a union
```

An alias cannot name a wildcard import — `use name = X.*;` is rejected, since a wildcard stands for several imports rather than one value a name could be given.

One namespace needs no `use` anywhere: `Ghul.Intrinsics` holds the names the language itself supplies — the built-in types such as `int` and `string`, the function and tuple shapes, and the operators on them — and every namespace block sees it as if it had written `use Ghul.Intrinsics;` first. Everything else the runtime provides is declared in `Ghul` and its nested namespaces and is imported like any other library: `use Ghul;` for the functional combinators such as `apply`, `use Ghul.Pipes;` for the pipe combinators. A definition of your own can share a name with one of those — an `apply` of your own, say — and a file that does not import that name sees only its own. A file that imports it as well sees both: a function of your own and an imported function of the same name form one overload group, and each call is resolved between them.

One namespace cannot be named at all. `Ghul.Internal` holds the attributes that carry language facts, such as whether a class is closed or which variant of a union a type is, from the assembly that was compiled to the one that reads it. They state what the compiler established rather than something a program chooses, so naming one from source reports that the symbol is not found, and none of them is offered in completion. The assembly that declares them sees its own declarations as ordinary symbols.

A `use` with a type expression on the right names a type rather than importing a symbol — a *type alias*:

```ghul
use IndexedString = (index: int, value: string);
use Handler = (int) -> void;
use Names = string[];
use MaybeName = string?;
use Numbers = Collections.LIST[int];
```

An alias is a spelling for the type it names, not a type of its own, so the two are interchangeable in both directions: a `(index: int, value: string)` value is an `IndexedString` and an `IndexedString` is accepted wherever the tuple type is. That holds for every kind of target, so nothing that already accepts the underlying type has to learn about the alias. Constructing through an alias constructs what it names, so `Numbers()` builds a `Collections.LIST[int]`. A generic alias is constructed with its type arguments written, `StringMap[int]()`, and with them left off only when it passes its own type parameters straight through to a class, as `use Box[T] = BOX[T]` does, where `Box(42)` infers them as `BOX(42)` would. A tuple has no constructor, so neither does an alias of one.

An alias can take type parameters, which its target uses like any other type parameter:

```ghul
use Pair[A, B] = (first: A, second: B);
use StringMap[V] = Collections.MAP[string, V];

swap[A, B](p: Pair[A, B]) -> Pair[B, A] => (first = p.second, second = p.first);
```

`StringMap` names `MAP` with its first type argument already supplied, which nothing else in the language can express. Aliases can be written in terms of each other (`use IntPair = Pair[int, int];`) in any order, since an alias is resolved wherever it is first named rather than where it is written.

Because an alias is transparent, it cannot be defined in terms of itself — directly or through other aliases — since the type it stands for would have no end. Such a definition is reported as an error; a type that refers to itself is a `class` or a `union`, both of which are types in their own right.

An alias is scoped like any other `use`: it belongs to the namespace block it is written in, and a block elsewhere that wants the same shorthand declares it again. Consumers are unaffected either way, since a signature written with an alias is a signature written in the type it names.

`use default` stands for a set of imports rather than naming one: the clause expands to the imports most files want before they want anything specific, which by default are `IO.Std.write_line`, `Ghul.Pipes` and `Collections`. It is an ordinary `use` in every other respect, so it applies to the namespace block it is written in and imports nothing implicitly: a file that does not write it gets none of them.

```ghul
use default

entry() is
    let totals = LIST[int]([1, 2, 3, 4])

    write_line("{totals |> filter(x => x % 2 == 0) |> reduce(0, (a, b) => a + b)}")
si
```

Importing something the set already carries is how a file adds to the set rather than a duplicate, so `use default` and `use Ghul.Pipes` together are accepted. A function of your own named like one the set brings in joins it in one overload group, and each call is resolved between the two. Where yours fits the arguments as well as an imported generic function and each of its parameters is at least as specific, yours is chosen; the imported one is chosen where it fits better, or where your parameter is a catch-all such as `object`. To keep every call on your own function, leave that name out of the imports, by replacing `use default` with the narrower `use` statements the file needs, or give your function a different name. A project replaces the set with its own with `--default-use`, which takes a comma-separated list and can be written more than once; naming any name at all leaves the curated set out entirely, so a project that wants the collections and nothing else asks for exactly that. A project built by MSBuild names them in one property: `<GhulDefaultUses>Collections;IO.Std.write_line</GhulDefaultUses>`.

Compiling with `--implicit-default-use` gives every file that declares no namespace an implicit `use default`, placed after the file's pragmas and before everything else, which is how a one-file script run directly gets `write_line`, the pipes and the collections without asking for them. A file that declares a namespace gets nothing implicit, since its namespace blocks choose their own imports. A `use default` the file writes as well is harmless. A function the file defines merges with one of the same name the set brings in, as it does under an explicit `use default`.

## comments

`//` starts a comment that runs to the end of the line, and `/*` ... `*/` encloses one that can span lines. Either counts as the whitespace it sits in.

A line comment starting with exactly three slashes, `///`, and with nothing before it on its line, is a **doc comment**. A block of them written directly above a declaration documents it, and an editor shows the text in hover and completion wherever the declaration is used, including from another assembly:

```ghul
/// Joins `parts` with `separator` between each pair.
///
/// - parts: the strings to join, in order
/// - separator: placed between adjacent parts, not at either end
join(parts: string[], separator: string) -> string => string.join(separator, parts)
```

The block is the run of `///` lines ending on the line directly above the declaration, or, where the declaration has pragmas, directly above its first pragma. A blank line or any other comment or code in between means the block documents nothing. Classes, structs, traits, unions and their variants, enums and their members, functions, methods, properties and global variables take a doc comment; members added in a `partial` or `impl` block take one like any other.

The text is Markdown. Each line loses its `///` and one following space, and is otherwise shown as written, so a `///` line with nothing else on it is a paragraph break. Arguments are described in a bullet list, one `- name: description` line each. Four or more slashes make an ordinary comment, which leaves a row of slashes free to use as a divider.

## statement terminators

Code written in the conventional style, one statement to a line, doesn't need a `;` anywhere except to put two statements on one line.

A `;` separates two statements or simple declarations written on one line. At the end of a line it is not needed: wherever the grammar could accept a `;` and the next token opens a new line, the boundary is inferred. End of file ends a line too, so the last construct in a file needs no terminator either. A construct left incomplete at the end of a line — `a +`, an argument list waiting for its `)` — continues on the next.

The rules that decide where a line break ends a statement, most often met first:

- A line that opens with `.`, `?`, `|>` or `ref` continues the construct above it, so member chains, optional chains and thread-first chains wrap.
- A line that opens with `(`, `[`, `` `[ ``, or an operator starts something new — a destructure assignment `(a, b) = …`, an array literal, a prefix `!` — and never glues to the line above as a call, an index, or an infix operand. A wrapped operator expression puts the operator at the end of the line (`a +` then the newline, not the newline then `+ a`).
- Two string literals chain into one across a line break. Where a statement ends on a string literal and the next begins with one, a `;` between them is the one boundary only a written `;` can make (see the string-literal section below).
- A bare `return` at the end of a line is a void return when the next line opens with a closing keyword (`fi`, `si`, `od`, …), and otherwise takes the next line's expression as its value. A statement after a `return` in the same block would be unreachable, so the two readings never compete.
- In a parenthesised group, a top-level `,` commits the tuple reading and an inferred boundary commits the block reading, exactly as a written `;` does. A compound statement that ends a line is complete, so the boundary falls after it whatever opens the next line, and an operator there begins a new statement. The expression reading needs the operator on the same line: `(if c then 2 else 5 fi - 1)` is 1 when `c` is true, where the same tail written on its own line is a second statement and the group's value.
- A postfix marker attaches on the same line as what it marks: a line-start modifier (`pure`, `static`, …) belongs to the next definition rather than the header above, and a line-start `rec` is the recursive self-reference call, never a rec-lambda marker.
- An `else` opening the line after a bare `assert` is the assert's message clause when its line is indented at least as far as the assert's, and otherwise the `else` of the enclosing `if` or `case` arm. Only the indentation decides: an assert sharing its line with the `if` (`if c then assert x` / `else y fi`) takes an `else` written level with the `if` as its own; a `;` after the assert gives the `else` to the `if`.

`--warn redundant-semicolon` reports a `;` written at the end of a line, for a project moving its terminators out. It is off by default; once enabled it responds to `--warn-as-error` and the other severity flags like any other slug. `--inlay terminator` shows the inferred boundaries as editor inlay hints, a `∘︎` wherever a statement ends without a written `;`: exactly the places `redundant-semicolon` would report one. Also off by default.

## variables

See <https://ghul.dev/definitions.html#variables>.

Local variables are declared with `let`, with an inferred or explicit type and an initializer:

```ghul
let i = 1234;          // type inferred as int
let k: int = 5678;     // explicit type
```

A bare `let` is immutable: the initializer is required, the value is fixed, and reassignment is rejected. To reassign, declare with a trailing `mut`; the initializer can then be omitted, giving a deferred-init local that takes the default value of its type (zero, `false`, or `null`):

```ghul
let counter mut = 0;     // initialised, will be reassigned
counter = counter + 1;

let result: int mut;     // deferred — default-initialised to 0
result = compute();
```

A deferred-init local is still covered by definite-assignment analysis: reading it on a path that has not assigned it draws a `definite-assignment` warning, so the default value is a backstop rather than something to lean on.

`null` says a local can be absent without saying what it holds when present, so an initializer or an assignment of `null` does not settle the local's type. The type comes from the other values assigned to it, or from the fallback a later `??` supplies, and is the optional of that type:

```ghul
let root mut = null;       // NODE?, from the assignment below
root = NODE("first");

let unknown = null;        // bool?, from the fallback
if unknown ?? false then
    ...
fi
```

A local whose initializer, assignments and uses give it no type at all is reported as `cannot infer type here` where it is declared, and needs an annotation.

A `mut` local with an initializer and no written type holds everything assigned to it, so its type is the join of the initializer and every value assigned later: a union variant or a subclass as the initializer does not stop a sibling being assigned.

```ghul
let tree mut = Tree.EMPTY;     // Tree, from the assignment below
tree = Tree.NODE(tree, 1, Tree.EMPTY);

let pet mut = CAT();           // Animal
pet = DOG();
```

The join is only taken where the author wrote a type for the values to share. Where it would be `object`, `System.ValueType`, or a trait neither the initializer nor any assigned value is typed as, or where any of them is a value type, the local keeps its initializer's type and the assignment is reported: `let i mut = 0; i = 1L` is an error, as is assigning an unrelated class. Writing the type out (`let pet: Animal mut = CAT()`) always fixes it.

A `mut` variable still cannot change type once it has one. Either form can also take its value from `_`, the default-value expression — `let i = _` takes its type from the local's own annotation or from later use, with `_[T]` to pin it explicitly. A bare `_` in a call-argument position infers the parameter type from the callee, provided the call resolves to a single unambiguous overload; if the parameter has a declared .NET default value, `_` takes that value rather than the type's zero value, so writing it out positionally behaves exactly like omitting the same argument by name. For a `T ref` parameter, `_` discards what the callee writes: the callee is handed the address of a fresh local holding the default of `T`, so `System.Version.try_parse("1.2", _)` tests the text without keeping the result. A `_` argument is never itself used to infer a generic type variable — one pinned only by the `_` slot, or a call left ambiguous between overloads, is still an error (`cannot infer type of default here`). `_[T]` always means the literal zero value of `T`, in every position — it never picks up a callee's declared default.

Applied to an argument list, `_(...)` *constructs* the type the context expects instead of taking its zero value, so a value can be built without naming its type a second time:

```ghul
let xs: LIST[int] = _();
let b: BOX[int] = _(42);
```

The type comes from the same places the bare `_` takes it from: the annotation on a `let`, the left-hand side of an assignment, or the formal type of a call argument. An untyped immutable `let` initialized with `_()` takes it from how the local is used later in the body, as a local initialized with `[]` does: `let result = _()` followed by `return result` builds the declared return type. An optional context is unwrapped first — `let b: BOX? = _(1)` constructs a `BOX`, which then widens to the optional — and with nothing to infer from, it is an error (`cannot infer the type to construct here`). `_[T](...)` is not accepted: with the type written out, `T(...)` already says it.

`_` in a binding or pattern position — `let _ = expr`, a destructure leaf `(_, b)`, a `for _`, an `if let _`, a lambda discard formal `_ => ...` or `(_, y) => ...`, a typed discard `(_: T)` — is the discard placeholder, a different meaning from the default-value expression above; the positions are syntactically distinct so the two meanings never collide. `_[T]` has no reading as a lambda formal — a formal's type comes from `_: T`, not `_[T]` — so writing `_[T]` where a formal is expected is a compile error rather than a silently-dropped type argument.

A single `let` can declare several variables, mixing inferred and explicit types:

```ghul
let first = 1, second: int = 0, third = "three";
```

The name `_` is a discard placeholder: it stands in for a variable name, but the value that would be assigned to it is discarded. It is accepted in `let` definitions, tuple destructuring, lambda parameters, and `for` loop variables.

Variables are block-scoped — visible from their declaration to the end of the innermost enclosing block — and `let` can only be used inside function, method, or property bodies.

A variable declared at namespace scope is a **global variable**. It is written as a plain name and type, without `let`, and cannot carry an initializer:

```ghul
counter: int;            // a global variable
```

## types and literals

See <https://ghul.dev/language-basics.html>.

ghūl exposes the .NET primitive types under lowercase names:

- integers — `byte`, `ubyte`, `short`, `ushort`, `int`, `uint`, `long`, `ulong`, `word`, `uword`
- floating-point — `single`, `double`, and `decimal`
- `bigint`, an integer of no fixed width
- `bool`, `char`, `void`

`string` and `object` are reference types from the .NET base class library.

Note that `byte` and `ubyte` are inverted relative to .NET: `byte` is `System.SByte` (signed) and `ubyte` is `System.Byte` (unsigned).

```ghul
let count = 12_345;            // int
let hex = 0x1234_ABCD;         // int, hexadecimal
let big = 1_000_000_000L;      // long
let b = 99b;                   // byte
let ratio = 123.456;           // double
let coarse = 123.456s;         // single
let price = 19.99m;            // decimal
let huge = 900719925474099n;   // bigint
let letter = 'c';              // char
let greeting = "hello";        // string
```

Digits may be grouped with `_`. An integer literal can carry a radix prefix (`0x`) and a type suffix built from two optional parts, both case-insensitive: a sign selector — `s` signed or `u` unsigned — followed by a size selector — `b` byte, `c` char, `s` short, `i` int, `l` long, `w` word. So `123b` is a `byte`, `0ub` a `ubyte`, `4567s` a `short`, `7890us` a `ushort`, `222i` an `int`, `0ul` a `ulong`, `123w` a `word`, `123n` a `bigint`. A numeric character literal (`65c`) cannot be unsigned, and neither can a `bigint` one (`123un`) — .NET has no unsigned counterpart to `System.Numerics.BigInteger`.

The digits are read first and as far as they go, so a letter that is a digit of the literal's radix is one. In hex that covers `b` and `c`, which are size selectors as well as hex digits: `0x20AC` is the `int` 8364 and `0xAB` is the `int` 171, with no suffix in either. A suffix that would be read as a digit is attached with a backtick, which marks the boundary and is not part of the value:

```ghul
let euro = 0x20AC`c;       // char, 8364
let byte_max = 0xFF`ub;    // ubyte, 255
let wide = 0x20ACl;        // long — `l` is not a hex digit, so no backtick
```

Backtick is the same escape it is elsewhere: it says to read what follows as itself rather than as its default meaning. Decimal needs it nowhere, since no size selector is a decimal digit.

`bigint` is `System.Numerics.BigInteger` under a built-in name, and only under that name — as `decimal` is `System.Decimal`. It is a name rather than a built-in type: its arithmetic and its ordering are its own static operators and its `IComparable` rather than anything the language supplies, so it has no width to overflow and no literal that is out of range.

```ghul
let factorial mut = 1n;

for i in 1::30 do
    factorial = factorial * bigint(i);
od

write_line("{factorial}");     // 265252859812191058636308480000000
```

Mixed operands stay an error, exactly as `1.0D + 1` is: `total * 2` is rejected where `total` is a `bigint`, and `total * 2n` is what to write. `==` is rejected on it as on every other struct; compare with `=~`.

A fractional literal is a `double` unless suffixed — `s` single, `d` double, `m` decimal, in either case. The `m` suffix is also accepted on a digit-only literal to write an integral decimal (`100m`). Exponent notation is accepted: `1.5e3`, `1.5E-3`.

ghūl does not convert between scalar types implicitly — a mixed-type arithmetic expression is a compile-time error, and a `cast` is required. Upcasting is implicit: a value is assignment-compatible with any ancestor type, so a `string` can be assigned to an `object` with no cast.

```ghul
let a = 1.0 + 1.0;               // ok, both double
let b = 1.0 + cast double(1);    // ok, explicit cast
let o: object = "hello";         // ok, string is an object
```

A scalar type is also a constructor from any other scalar, converting exactly as a cast to it does: `double(n)` is `cast double(n)`, `int(x)` truncates as `cast int(x)` does, and a value out of range wraps the same way. `_(n)` converts to the scalar type the context expects. The source has to be a scalar: `int("42")` is not a parse, and a value held as `object` or a type parameter is converted with `cast`, which unboxes it.

```ghul
let n = 7;
let half = double(n) / 2.0;      // 3.5
let code = int('A');             // 65
let total: long = _(n);          // 7
```

The target type can be left out when the surrounding expression already determines it. `cast(v)` converts `v` to whatever type the position it sits in calls for — a typed `let` initializer, an assignment, a `return` or `=>` body, an argument, an operator's other formal, an index, or the callee of a call:

```ghul
let total = cast(count) + average;   // count converts to double
let d: double = cast(i);             // to double
takes_a_double(cast(i));             // to double
values[cast(index)];                 // to whatever the indexer takes
```

The type comes from the declaration the expression resolves against rather than from any other operand, so a `cast(v)` in an argument or operand position takes the type of the formal it lands on. That means resolution has to reach exactly one candidate: `cast(v)` is refused where the position supplies no type at all, and where more than one overload or operator would accept it. `cast(a) + cast(b)` is an error rather than a guess, as is a call whose overloads differ only in the parameter the `cast(v)` fills. Hover over the `cast` keyword shows the type it resolved to.

A cast that is called supplies its own: the arguments give the parameter types and the surrounding context gives the return, so the target is the function type the call describes.

```ghul
let handler: object = read_handler();

let result: int = cast(handler)(4);    // handler converts to int -> int
```

A parenthesised target reads two ways, and which is meant depends on what the name in it turns out to be. `cast (T)(v)` converts `v` to `T` where `T` names a type, and casts the value `T` and calls the result where it does not. A target that can only be a type — a tuple, a function type — is never read the second way, since a value of it could not be called.

```ghul
let widened = cast (double)(count);    // a type: count converts to double
let called = cast (handler)(count);    // a value: handler is cast, then called
```

A **string literal** may interpolate expressions: `{` opens an expression and `}` closes it, and the expression's value is converted to a string in place. There is no `+` operator on `string`, so interpolation is how strings are joined:

```ghul
let greeting = "hello {name}, you are {age} years old";
let combined = "{prefix}{suffix}";                  // concatenation
```

An interpolated expression can carry an alignment and a format specifier, as in .NET: `{expr, alignment : format}`.

```ghul
let padded = "[{value,12:F3}]";     // [    1500.000]
```

How a value reads depends on its static type. A string, a number, an enum, and any type that declares its own `to_string` read as they always have, through that `to_string`, and so does any value given an alignment or a format. A `bool` reads `true` or `false`, as ghūl spells it. An optional reads as the value it holds, by these same rules, or as `null` when it holds nothing. Anything else - an array, a list, a tuple, a struct or class that declares no `to_string`, a value held as `object`, a trait or a type parameter - would otherwise read as its .NET type name, so the runtime's `$` writes it instead: a sequence as its elements in brackets, a tuple as its parts, and a record as its type and members.

```ghul
struct POINT(x: int public, y: int public);

let xs = [1, 2, 3];
let found: string? = null;

"{xs} {(1, "one")} {POINT(3, 4)} {true} {found}"
                                     // [1, 2, 3] (1, one) POINT(x = 3, y = 4) true null
```

A pipe declares a `to_string` of its own that reads as its elements in brackets, the same text `$` gives it. A type's own `to_string` always wins, so the way to change how a value interpolates is to give its type one.

Adjacent string literals concatenate, so a long string can be split across lines — plain and interpolated literals mix freely. Comments count as the whitespace they sit in, so a commented fragment chains like an uncommented one; only a `;` separates two otherwise-adjacent literals. That `;` is the one statement terminator that carries meaning — where a statement ends on a string literal and the next begins with one, it keeps them from chaining into a single literal, so `redundant-semicolon` never reports it:

```ghul
let band = "top";
"{band} band"        // a new statement — without the `;` the two
                     // literals chain, and band is not defined yet
```

Inside the braces you are in *expression* context, so a nested string literal is written normally — `"{format("hello")}"` needs no escaping of its inner quotes. To write a literal brace, double it: `"{{"` and `"}}"`. The escapes are `\t`, `\n`, `\r`, `\\`, and `\u` followed by exactly four hex digits for an arbitrary character code — so the euro sign is `"\u20AC"` and an escape character is `"\u001B"`. Four digits is one UTF-16 code unit, which is one `char`; a code point above `U+FFFF` is written as its surrogate pair, so `"\uD83D\uDE00"` is one grinning face and two `char` values. The width is fixed so that the escape never reaches into the text after it — `"\u0041cat"` is `Acat`. Any other character after a `\` stands for itself, which is what makes `\"` a quote.

A run of octal digits after a `\` is the older spelling of a character code (`"\33"` for an escape character). It still works and still means the same thing, but it is deprecated — it is greedy and unbounded, so it also swallows the digits after it — and writing one draws a `deprecated-octal-escape` warning. Write `\u` instead.

An **array** type is written `E[]`. Arrays are fixed-size and read-only — there is no assigning indexer. An array's length is its `count`. An array literal is a comma-separated list in square brackets, and its element type is inferred as the most specific type compatible with every element (`object` if there is no closer common ancestor):

```ghul
let primes = [2, 3, 5, 7, 11];          // int[]
let mixed = ["frog", 1234, 12.5];       // object[]
let p = primes[2];                      // indexing, 0-based
```

The empty array literal `[]` is accepted wherever the element type comes from context — an explicitly-typed `let`, a `return`, a call argument's parameter type, a sibling element of an enclosing array literal, or the other arms of an `if` or `case` expression it is an arm of. An untyped immutable local initialized with `[]` takes its element type from its later uses in the same body, such as being passed where an array is expected or placed in an array literal that is; when nothing uses it that way, its element type is `object`.

A sequence of `E`, anything a `for` loop can walk, is written `E{}`: it is `Collections.Iterable[E]`, the .NET `IEnumerable<E>`, spelled the way `E[]` spells an array. The two spellings are the same type, so either is accepted wherever the other is, and diagnostics, hover and inlays show `E{}`. The braces follow the element type in every position a type can appear, and combine with the other suffixes: `int{}?` is an optional sequence, `int[]{}` a sequence of arrays and `int{}{}` a sequence of sequences. A tuple or function type is parenthesised first, as it is for `[]`:

```ghul
total(values: int{}) -> int => values |> sum()

let words: string{} = ["alpha", "beta"]
let pairs: (int, string){} = [(1, "one")]
```

Indexing with a **range** takes a slice of the source rather than a single element. `..` and `::` count both endpoints from the start, as they do everywhere else; `..<` and `::<` count the end back from the end of the source, and `..<<` and `::<<` count both endpoints back. The number of `<` says how many endpoints are counted back, filling from the right. `<0` is the length, so `a..<0` runs from `a` to the end:

```ghul
let xs = [10, 20, 30, 40, 50];

xs[1..3];        // 20, 30
xs[1..<1];       // 20, 30, 40   — up to one back from the end
xs[1..<0];       // 20, 30, 40, 50 — to the end
xs[3..<<0];      // 30, 40, 50   — the last three
```

The slice is a `Collections.List[E]` over the source, so nothing is copied and a later change to a mutable source shows through. Arrays, strings and anything that satisfies `Collections.List[E]` can be indexed this way; a string gives back a string, since there is no non-copying substring to hand out. A range index is a read: there is no slice to assign through. A type may also declare its own `[r: System.Range]` indexer, which is used in preference.

The from-the-end operators build a `System.Range`, whose endpoints are only resolvable against a length, so unlike `..` and `::` they are not iterable — `for i in 1..<1 do` is rejected.

A **tuple** groups two or more values of possibly different types — a single-element tuple is rejected, and a tuple has at most 7 elements. Tuple types and literals both use parentheses; elements may be named, and an unnamed element is named with a backtick and its index. Tuples are immutable, nest, and can be destructured. They compare element by element through `=~`; `==` is rejected on one, as it is on any other struct (see [equality](#equality)):

```ghul
let pair = (10, "hello");                  // (int, string)
let point = (x = 10, y = 20);              // (x: int, y: int)
let x = point.x;
let first = pair.`0;                       // positional access
let (name, age) = ("alice", 30);           // destructuring
```

A tuple is assignable to a tuple type whose elements each accept its own, so a `(CAT, Shape.DOT)` value goes wherever a `(Animal, Shape)` is expected, and an `(int, string)` wherever an `(int, object)` is. The .NET tuple type is invariant, so the value is rebuilt at the wider type where it crosses into it, converting each element as it would be converted on its own, boxing and optional widening included. The rule is for tuple values: a function type returning a tuple is not made assignable by it, so a `(int) -> (int, int)` value is not a `(int) -> (object, object)`.

When an unnamed tuple-literal element is a bare identifier, it takes its name from the identifier: `(a, b)` constructs the same tuple as `(a = a, b = b)`. When the identifier resolves to a field whose name carries the single-underscore private-member convention, the leading `_` is stripped from the inferred element name: `(_count, _total)` packed from private fields surfaces as `(count: ..., total: ...)` to consumers. Locals are not affected, and only a single leading underscore is ever stripped.

Destructuring comes in two forms: **positional** and **by-name**, distinguished syntactically.

A **positional** target list `(a, b, ...)` is matched against the source in this order: a value-tuple of matching arity; a `deconstruct(...)` instance method whose parameters are all `T ref`; the conventionally-named positional members `` `0 ``, `` `1 ``, .... The `deconstruct` route covers .NET types like `Collections.KeyValuePair[K, V]`, ghūl-defined classes that write through each `T ref` parameter with postfix `!`, and classes with a primary constructor that get a synthesised `deconstruct` (see [primary constructors](#primary-constructors)). A type without one of those shapes is not destructurable positionally — use the by-name form below.

```ghul
for (key, value) in dict do          // KeyValuePair.Deconstruct
    write_line("{key}={value}");
od

class POINT is
    x: int; y: int;
    init(x: int, y: int) is self.x = x; self.y = y; si
    deconstruct(a: int ref, b: int ref) is
        a! = x;
        b! = y;
    si
si

let (px, py) = POINT(3, 7);
```

A **by-name** target list `(local = field, ...)` pulls each element from the named field of the source — `local` becomes the new local variable, `field` names the member on the right-hand side. The same `=` reads in both directions: `(x = x, y = y) = point` is no-rename ("local x gets field x"); `(new_x = x, new_y = y) = point` renames the bound locals. Each `(...)` group is either entirely positional or entirely by-name — mixing is a parse error. Nested groups choose independently:

```ghul
let (a, (bb = b, cc = d), d) = triple;   // outer positional, middle by-name
```

In refutable contexts (`if let`, `case`-when patterns), a literal on the left-hand side adds a value-equality test rather than declaring a variable — `("Alice" = name, a = age)` matches when `source.name == "Alice"` and binds `a` to `source.age`. The rule throughout: the LHS of `=` says what to do with the value (bind it, or match it against a literal), the RHS names the field to pull.

Postfix `!` on a `T ref` derefs the pointee: `p!` reads the value, `p! = v` writes through. On a `T?` it asserts presence and projects out the value (see [optional types](#optional-types)); the parser produces the same node in both cases and the meaning is settled by the operand type. Outside `deconstruct` bodies the deref form is rarely needed — ghūl code usually takes refs only to pass them to .NET methods that follow the try-pattern.

## functions

See <https://ghul.dev/definitions.html#functions>.

A function is a name, a parenthesized argument list, an optional return type after `->`, and then either a single-expression body after `=>` or a block body between `is` and `si`:

```ghul
add(a: int, b: int) -> int => a + b;

multiply(a: int, b: int) -> int is
    let result = a * b;
    return result;
si
```

A named function's signature is fully explicit: every argument has a written type, and so does the return — written after `->`, or the `->` left off to make the function `void`. The compiler infers no part of a named function's or method's signature.

A block body produces its value with an explicit `return`, or by ending on an expression: the final statement of a non-void body is the function's return value on the fall-through path whenever its type is assignable to the declared return type, with or without a `;` after it. An expression qualifies, and so do an `if`/`case` expression and a parenthesised block. A tail of an incompatible non-void type is an error at the tail; to genuinely discard such a value, write `let _ = expr`. A void tail — an effect-only call, or an `if`/`case` whose arms diverge or do only effects — is the statement it is: the body falls off the end, returns the default value of the return type, and draws a `definite-return` warning. An asynchronous function accepts a bare-`T` value as its tail exactly where it accepts `return T`. Loops, `let`, assignments and `assert` never provide a tail value, and neither do labelled statements or `try` blocks (until `try` has an expression form). Void bodies tolerate any tail: whatever is left standing at the end of a void method is discarded, and an expression body follows the same rule, so `f(x: int) -> void => g(x);` discards `g`'s result rather than returning it. Generators are exempt from all of this: their fall-through signals end of stream.

A function whose result depends on the values of its arguments can have a `case` over them as its body, one arm per case: the form a function defined by equations takes in Haskell or Elixir. Over more than one argument the scrutinee is a tuple of them, and the arms get the same exhaustiveness checking, narrowing and guards as any `case`:

```ghul
gcd(a: int, b: int) -> int =>
    case (a, b)
    when (_, 0) then a
    else gcd(b, a % b)
    esac
```

A function declared at namespace scope may be overloaded on its argument types. Where a generic and a non-generic overload fit a call equally well, the non-generic one is chosen when each of its parameters is at least as specific as the generic's once the generic's type arguments are bound: `f(items: List[string])` wins over `f[T](items: Iterable[T])` for a `string[]`, and `f(items: List[object])` or `f(items: object)` loses to it. There are no default argument values. Execution of a program begins at a function named `entry`, or — in a file with no namespace — at the bare statements written at its file root, which are collected in source order into that entry point. An `entry` function takes any subset of two recognised parameters, matched by declared type rather than by name: a `string[]` for the command-line arguments, and a `Ghul.Environment` — a ghul-runtime trait giving read/write access to the process's environment variables — for the process environment. So `entry()`, `entry(args: string[])`, `entry(env: Ghul.Environment)` and `entry(args: string[], env: Ghul.Environment)` are all accepted, in either parameter order — and the environment parameter is recognised equally when reached through a `use`: `use Ghul;` then `entry(env: Environment)`, `use Ghul.Environment;` then `entry(env: Environment)`, or an aliasing `use X = Ghul.Environment;` then `entry(env: X)`. It returns either nothing or an `int` exit status. Only declaring the environment parameter changes anything about how the program starts: the compiler then synthesises a private wrapper carrying the real entry-point shape — no parameters, or a lone `string[]` when `args` is also declared — which resolves `Ghul.Environment` and calls through to `entry`; without it, `entry` compiles straight to the program's real entry point exactly as before. This recognition only applies to a global function reached by name — the default `entry`, or the name `--entry` gives — not to a class's static method serving as the entry point, which keeps its plain `string[]`-or-nothing shape. A function of the name the build starts at whose shape is none of those is an error at the function, saying which part of it rules the function out: a return type that is neither `int` nor `void` - which is what an asynchronous `entry` has, since it returns a task, so to run asynchronous work read `.result` on the returned task - more than one parameter, or a parameter of any other type. The file's top-level statements are not run in its place: a program that declares where it starts has said so, and starting somewhere else would be as surprising as not starting at all. The name can be changed with `--entry <name>`, and an `@entry` pragma marks any function as the entry point regardless of name.

A formal parameter can be a tuple-destructure pattern instead of a plain name. It is still one physical parameter, at the written tuple type — the pattern is unpacked into its named elements on entry, the same way a `let (a, b) = pair;` local is:

```ghul
add_pair((a: int, b: int): (int, int)) -> int => a + b;

add_pair((3, 4));    // 7
```

Nesting and mixing with ordinary parameters both work: `f(x: int, (a: int, b: int): (int, int), y: int)`. Because a namespace-scope function's signature is always fully explicit, the aggregate type ascription is required — there is no context to infer it from — and per-element types are optional, exactly as in a `let (a, b) = pair;` local. The aggregate type can be any positionally-destructurable type — a tuple, or a type with a matching `deconstruct(...)` method. The by-name group form (`(x = field, ...)`) is not supported in a formal argument list.

Functions are first-class values. A function literal has the same shape without a name, but its argument and return types are generally *inferred* — from the body and from the context the literal is used in — so they are usually written without annotations (though either can be given explicitly). With a single argument the parentheses are optional. `A -> B` is the type of a function from `A` to `B`. A function *type* — and so a function literal, or a named function referred to as a value — has at most 16 parameters; a named function itself has no such limit, since it need never be represented as a function-type value. Function literals capture references from the enclosing scope, forming closures: an immutable `let` is captured by value (a snapshot at the point the literal is constructed); a `let mut` is captured by reference, so the closure and the outer scope share one live variable that either side can read or reassign. An anonymous function refers to itself through the `rec` keyword:

```ghul
let twice = x => x * 2;
let apply_twice = (f: int -> int, i) => f(f(i));
let factorial = n rec => if n == 0 then 1 else n * rec(n - 1) fi;
```

A block-bodied function literal ends on a tail exactly as a named function does: a final statement whose type is assignable to the return type is the value the literal returns on fall-through. Where the return type is written out, or comes from the slot the literal goes into, the tail is judged against it. Where it is left to be inferred and the body has no `return`, the tail is what settles it - a void tail settles nothing, so such a body is void and may end on a guard `if` like any other.

A slot returning `void` settles the literal's return type as much as any other does, so a literal written into one discards whatever its body produces - by either body form. That is how a call whose result is not wanted is written where a function is expected:

```ghul
names |> each(name => seen.add(name));    // `add` returns a bool, discarded here
```

Where several overloads take a function at the same arity, a body that produces a value goes to the formal that asks for one, and a `void` formal is reached only when no candidate does. So a literal returning a `bool` still picks a `(T) -> bool` formal over a `(T) -> void` one, and writing the return type out (`name -> void => seen.add(name)`) picks the void formal outright.

A function literal's parameter can be a destructure pattern too, written in its own parentheses inside the parameter list — the outer parentheses are the parameter list, the inner ones the pattern. It is one parameter, unpacked into the names the body uses, exactly as for a named function:

```ghul
let pairs = [(1, 2), (3, 4)];

pairs |> map(((a, b)) => a + b);          // element types inferred from the sequence
```

The bare single-parameter shorthand (`x => …`) can't carry a pattern any more than it can carry a type annotation — both need the parentheses. Unlike a named function the aggregate type is usually inferred, from the sequence or slot the literal is written into, or from how the parameter is used; write it explicitly when there is nothing to infer from. As with a named function, the aggregate can be any positionally-destructurable type, so per-element types and the aggregate ascription both take the full type syntax:

```ghul
let add = ((a, b): (int, int)) => a + b;

entries |> each(((key, value): Collections.KeyValuePair[string, int]) =>
    write_line("{key}={value}"));
```

Patterns nest and take discards, so `(((a, b), c)) => …` and `((_, b)) => …` both work, on plain and asynchronous function literals alike.

A function can also be written among the statements of a body, with a name. It is a function literal that the name is a local variable for, so it captures, compiles and is called exactly as the equivalent `let` would be, and the two spellings are interchangeable:

```ghul
process(xs: Collections.List[int]) -> int is
    score(x: int) -> int is
        if x < 0 then
            return 0;
        fi

        x * 2
    si

    xs |> map(score) |> reduce(0, (a, b) => a + b)
si
```

Argument and return types are optional, as they are on any other literal and unlike a namespace-scope function, whose uses are not all in view. Either body form works, and the name may be written wherever a value of its function type is expected, not only in a call:

```ghul
    halve(x) => x / 2;

    let apply_to_ten = (f: (int) -> int) => f(10);

    apply_to_ten(halve);
```

The function refers to itself by its own name, so it needs no `rec`, and a literal written inside its body reaches it the same way:

```ghul
    fact(n: int) -> int => if n <= 1 then 1 else n * fact(n - 1) fi;
```

Being a local, it is defined from its own definition onward: a reference above it, and mutual recursion between two of them, are both reported. Write one of the pair as a `let mut` literal and assign it afterwards where that is what is wanted. A file's bare top-level statements are not a body, so a named function written among those is a namespace-scope function and its argument types are required.

A bare name in call position (`foo(args)`) normally resolves to the nearest enclosing declaration of that name, the same as any other reference. When that declaration is not callable — a local variable, field, or property holding no function — and an enclosing scope has a function or a function-typed value of the same name, the call reaches that one instead, with a `shadowed-non-callable` warning at the call site:

```ghul
tally(xs: int[]) -> int => xs.count;

use_tally(xs: int[]) is
    let tally = tally(xs);   // warns, then calls the function above
    write_line("{tally}");
si
```

A bare name written with type arguments (`foo[int]`, whether or not it is then called) follows the same rule, since a name applied to type arguments can only mean a type or a function.

The fallback only applies when the nearest declaration cannot be called at all — a function whose overloads reject the supplied arguments still reports the ordinary argument-mismatch error rather than reaching for something else. A name that refers to itself from inside its own initializer's function literal (rather than directly, as above) keeps reporting the reference as one to a value that does not exist yet:

```ghul
let f = (x: int) -> int => f(x);   // error: variable is not defined here
```

## type definitions

See <https://ghul.dev/definitions.html#types>. ghūl has five kinds of user-defined type, all declared at namespace scope, never nested inside another type.

### classes

A class defines a reference type. The header is the class name, optionally a superclass and any implemented traits after a colon, then an `is` ... `si` body of properties, methods, and constructors:

```ghul
class PERSON is
    name: string;
    age: int;

    init(name: string, age: int) is
        self.name = name;
        self.age = age;
    si

    describe() -> string => "{name} is {age} years old";
si
```

A class can extend at most one superclass and implement any number of traits. `self` refers to the current instance. An instance is created with a constructor expression — the type name applied like a function — which selects the matching `init` overload (`PERSON("alice", 30)`). A class with no declared superclass extends `object`. `==` on a class is always reference identity and stays that way; to give a type structural equality, define `=~`, or ask for one with `@equality()`. See [equality](#equality).

An `@equality()` pragma before a class asks the compiler to synthesise its `=~` and matching `get_hash_code`, comparing the members that hold the class's state — each auto-property and `field`, in turn, through its own type's equality. A property with a body is derived from that state rather than part of it, and a static member belongs to the type, so neither takes part. Members that are not public take part like any other: the pragma is the author asking for the comparison, so what the members are visible to says nothing about whether they distinguish two values.

Two values compare equal only when they have the same runtime type, so a base and a subclass are never equal in either direction, and the relation stays symmetric however it is written.

```ghul
@equality()
class Shape abstract is
    area() -> int;
si

@equality()
class CIRCLE: Shape is
    radius: int;

    init(radius: int) is
        self.radius = radius;
    si

    area() -> int => radius * radius * 3;
si
```

The pragma applies to the class it is written on and to no other, so each class in a hierarchy asks for its own. An abstract class with no state of its own can ask too, which is what lets a comparison written against the base type resolve — `a =~ b` over two `Shape` variables dispatches to whichever subclass the values actually are, and each subclass compares what it adds on top of its base's.

A synthesised operator serves only the class it was written for: it admits operands of exactly that runtime type and reads only that class's members. So a subclass of a class that has one must supply its own, either by asking with `@equality()` or by declaring `=~` and `get_hash_code`, and a subclass that does neither is an error. That holds however little the subclass adds: the rule is uniform, so that every class in a hierarchy states its own position rather than its obligation depending on whether it happens to declare a field. A subclass whose base declares equality by hand is unaffected — what the author wrote is the author's to answer for.

The synthesised pair settles how .NET itself compares the value, through the `Equals` bridge, so a class that asks becomes a dictionary key that finds an equal value rather than only the same object. A class relied on to compare by identity in a `MAP` or a `SET` simply does not ask.

Asking for equality on a class that already declares `=~`, `<>`, `get_hash_code` or an `equals` over `object` is an error, since the request contradicts what is written. So is asking on an `open` class: enforcing the rule above needs every subclass in view, and an `open` class can be extended from another assembly.

A class without the pragma is unaffected: it has no `=~` at all, and comparing two of its values by `==` asks about identity as it always did. Structs and unions need no pragma, and are given equality wherever they declare none — a struct is a value, so two structs holding equal members already are the same value, and a union is compared by which variant it holds and what that variant carries.

A member whose type says it always holds a value has to be given one. A constructor that leaves one or more such members unassigned on some path out draws a single `field-definite-assignment` warning on the constructor's own name, naming every member it misses, since the object it produces holds null in a slot that cannot be written null anywhere else. Each missed member also carries a related location pointing at its declaration — on the property, not the hidden backing field, when the member is an auto-property — which a capable editor renders as a jump-to link. A constructor is credited with what it assigns itself, and with what the methods it cannot avoid calling on `self` assign in turn — a call reached on only one branch of an `if`, a call on another object, and a call to a method a subclass could override all credit nothing, because none of them is bound to happen. Members of optional type and of value type are not checked: neither has a null to be caught holding. Suppress via `@suppress("field-definite-assignment")` per file, with `--suppress field-definite-assignment` project-wide, or on the constructor itself.

A **static constructor** — `init() static` — runs once, before the type is first used, to initialise its static state. It takes no parameters and no `self`, and is invoked by the runtime rather than called directly; a class or struct may declare one alongside its instance constructors:

```ghul
class COUNTER is
    next_id: int static;

    init() static is
        next_id = 1000;
    si

    id: int;

    init() is
        id = next_id;
        next_id = next_id + 1;
    si
si
```

Two postfix modifiers shape the hierarchy:

- **`open`** lifts the default closed-to-assembly rule. Without `open`, a class can only be subclassed from within the assembly it was declared in; consumers in another assembly that try to extend it are rejected at compile time. `open` opts in to cross-assembly subclassing — the right choice when a library class is genuinely a hook for downstream code, the wrong choice (and the harder one to take back) when it isn't. The closure also feeds type narrowing: the compiler can enumerate a closed root's subclasses on the else edge of an `isa` test.
- **`abstract`** says the class itself can't appear as a runtime instance — only its subclasses can. A direct constructor call (`Animal()`) on an abstract class is rejected at compile time; subclasses still call `super.init(...)` for shared initialisation. Closed-narrowing relies on this: when the root is `abstract`, the else edge of `isa CAT(a)` excludes the root from the in-set and can collapse to the singleton sibling.

```ghul
class Animal abstract is
    init() is si
si

class CAT: Animal is
    init() is super.init(); si
    purr() -> string => "purr";
si

class DOG: Animal is
    init() is super.init(); si
    bark() -> string => "bark";
si

describe(a: Animal) is
    if isa CAT(a) then
        write_line(a.purr());
    else
        // `Animal` is abstract and `CAT`/`DOG` are the only subclasses,
        // so the compiler knows `a` is `DOG` here.
        write_line(a.bark());
    fi
si
```

The two modifiers are independent: `open` controls who can extend, `abstract` controls who can be instantiated. They can be combined (`class Animal abstract open is ... si` is an extensible abstract base) or stand alone.

A method written with no body at all — `foo();` or `foo() -> int;` with no `is … si` — is **abstract**: a contract for a subclass to satisfy rather than a method that does nothing. The class that declares one is abstract too, so constructing it is rejected exactly as `abstract` on the header rejects it, and a concrete subclass that does not implement the method is an error naming the method and the class it came from. Property accessors, `init`, and static methods are excluded — a write-only property leaves its synthesised getter body-less, and its accessors read and write the backing field rather than declaring anything.

The rule holds whether or not a trait behind the class supplies a default for the member. A class writing the member again with no body withdraws that default: the class is abstract, its subclasses owe an implementation, and `super` cannot reach the member, since there is nothing in the class chain to reach. A class that wants the default does not mention the member.

`super.foo()` cannot reach an abstract method: a super call names the base implementation directly, and there is none.

A body-less method that overrides a **class** method with a body is the one case that cannot become an abstract slot, because a caller holding the base type would still reach it. Such a method gets a synthesised body that throws `System.NotImplementedException` naming it, so the call says what the declaration says. It is not a contract, so subclasses owe it nothing. A trait's default is not this case: a class redeclaring one withdraws it, as above, and the redeclaration is a contract like any other.

### structs

A struct defines a value type. The syntax mirrors a class, but a struct has no superclass (it may still implement traits). Copying a struct copies all of its fields:

```ghul
struct POINT is
    x: double;
    y: double;

    init(x: double, y: double) is
        self.x = x;
        self.y = y;
    si
si
```

`==` and `!=` are rejected on every struct operand — a tuple, an imported `System.DateTime`, one of your own — because the single comparison they lower to reads the value's bytes rather than its fields. `=~` is what compares a struct by value.

For a struct that declares no equality of its own, the compiler synthesises `=~` and a matching `get_hash_code`, comparing the members that hold its state: each auto-property and `field`, in turn, through its own type's equality. A property with a body is derived from that state rather than part of it, and a static member belongs to the type, so neither takes part.

```ghul
struct PAIR is
    a: int;
    b: string;

    init(a: int, b: string) is
        self.a = a;
        self.b = b;
    si
si

PAIR(1, "x") =~ PAIR(1, "x")      // true
```

Two conditions. Declaring any half of the pair opts the type out of both: `=~`, `<>`, `get_hash_code`, or an `equals` over `object`. The decision reads the type's own members and nothing else, so a global `=~` declared for the struct does not opt it out: the struct is synthesised all the same, and the member operator is what answers where both exist. Equality that differs from the memberwise answer is declared on the type itself, which opts out of synthesis. A hand-written `=~` is the author's own answer, and a hand-written hash beside a synthesised operator could disagree with it, which is the pair the two are held to. And every member holding state must be public: private state is an implementation detail whose part in equality only its author knows, and comparing the public members alone would answer equal for two values a private member distinguishes. A struct with any non-public state is left as it was, with no `=~` at all until one is written for it. `protected` counts as non-public here.

A synthesised `=~` also settles how .NET itself compares the value, through the same `Equals` bridge a declared operator gets, so a struct is a working dictionary key. The hash reads what the comparison reads: a member compared element by element contributes its count, since two equal sequences are different objects, and a member whose comparison is finer than the hash it answers contributes nothing, so that equal values never hash differently. See [equality](#equality).

A bare member declaration like `x: double;` is an auto-**property**, not a field, and a struct's property getter hands back a *copy*. That matters when a struct is held in a heap object: mutating it through the property mutates the copy and the write is lost, so the compiler rejects a store through one. Declare a real field with the `field` modifier where a struct member is to be mutated in place:

```ghul
class HOLDER is
    origin: POINT field;     // a real field, mutable in place
si
```

A function literal written inside a struct's instance member cannot read `self`
or any of the struct's instance members, and doing so is an error at the read.
A literal becomes a delegate, whose target is an object, and a struct's
instance member holds `self` as a pointer to the value rather than as a
reference to an object, so there is nothing for the literal to bind to. Copy
what the literal needs into a local first, and the literal captures the local
as it captures any other:

```ghul
struct SCALER(factor: int) is
    scale(xs: List[int]) -> Pipe[int] is
        let by = factor

        return xs |> map(x => x * by)
    si
si
```

Static members are unaffected, since they have no `self`, and so is a struct
reached through anything other than `self` - a local, a parameter, a field of
some other object - which is an ordinary value the literal captures.

### primary constructors

A class or struct may declare its constructor parameters directly in the header. Each parameter becomes a parameter of the synthesised `init`. A primary parameter without an explicit body declaration gets a **synthesised** same-named body field/property mirroring its declared visibility:

```ghul
class POINT(x: int, y: int) is
    show() => write_line("({x}, {y})");
si
```

is equivalent to

```ghul
class POINT is
    x: int;
    y: int;

    init(x: int, y: int) is
        self.x = x;
        self.y = y;
    si

    show() => write_line("({x}, {y})");
si
```

A trailing **modifier suffix** on the parameter overrides the default visibility or storage, matching the same rules as a body field/property declaration:

- `x: int public` — public read and write.
- `x: int protected` — readable from the declaring class and its subclasses.
- `x: int private` — captured into the underscore-named member `_x`, non-public under the rules in [naming conventions](#naming-conventions). The parameter itself keeps the plain name `x`, so the member is read as `_x` and the constructor argument stays `x`. A private capture is left out of the synthesised `deconstruct`.
- `x: int field` — plain field rather than auto-property.
- `x: int static` — a static member rather than a per-instance one.
- `x: int init` — **no field synthesised**. The parameter is in scope only inside the synthesised `init` and any explicit `init(..)` body; useful when the constructor consumes its argument to compute something else (`init(.., other)` style).

Naming the parameter with a leading underscore (`_x: int`) is the equivalent convention-driven route, and follows the same rules; `_x: int private` is accepted and adds nothing, the name already carrying the visibility.

An explicit body declaration with the same name as a primary parameter (under the same `_foo` / `foo` matching rule) wins over synthesis — the body decl receives the value the synthesised `init` assigns. This is the *capture* form: writing the field shorthand `_x;` (or a property declaration named `_x` / `x` that supplies neither a read nor an assign body) tells the rewriter "match primary parameter `x` to this declaration." A property that does supply an accessor body is a normal member, not a capture. With explicit body decls you also get to choose private renames (`_x;` on a primary parameter `x`) without using the modifier suffix.

```ghul
class POINT(x: int, y: int) is
    _x;
    _y;

    show() => write_line("({_x}, {_y})");
si
```

is also equivalent to the classic-form `POINT` above, with the fields named `_x` and `_y`.

The form also supports:

- **`super(expr, expr);`** as a class-body declaration — forwards the given expressions to the superclass `init`. Each argument can be any expression whose free identifiers are primary-ctor parameters (literals and module/type-level references are also in scope), so `super(null)`, `super(other.x)`, `super(LIST([elem]))`, and `super(Source.LOCATION.reflected, owner, name)` all work. Primary parameters consumed by `super(...)` get no synthesised member (their value is forwarded to the base, no field needed locally).
- **`init(..)`** — an explicit body for the primary `init`; runs after the synthesised field assignments.
- **`init(.., extras)`** — a secondary `init` overload. The `..` splice expands to the primary parameters and an implicit chain to the primary `init` is prepended to the body, so every captured field is assigned before the secondary's body runs.
- **auto-`deconstruct`** — every public-readable capture surfaces, in primary-header order, as one `T ref` parameter of a synthesised `deconstruct` (exposed under .NET's `Deconstruct` name for cross-language interop), so `let (x, y) = POINT(3, 4)` works without writing the deconstruct out. Suppressed if the class body already declares a `deconstruct(...)` of any arity, or any backtick-numeric (`` `0 ``/`` `1 ``/...) property — both signal that the user is taking responsibility for positional access.

```ghul
class DOG(name: string, breed: string): ANIMAL is
    _breed;

    super(name);

    init(.., trick: string) is
        write_line("the {_breed} can {trick}");
    si
si
```

When the body would be empty, the `is si` may be replaced with a terminating `;`:

```ghul
class POINT(x: int, y: int);

struct VECTOR(dx: int, dy: int);
```

Classes, structs and unions all support primary constructors; the union form is covered under [unions](#unions).

### traits

A trait is ghūl's equivalent of an interface. A class or struct implements a trait by naming it in the header, and must provide every trait member that has no default. A trait member *can* carry a default body; an implementing type inherits the default and need only override it to change the behaviour, reaching the default with `super`:

```ghul
trait Logged is
    log() is
        write_line("(no log message)");
    si
si

class NOISY: Logged is
    init() is si

    log() is
        super.log();
        write_line("plus my own message");
    si
si
```

A class extends one superclass but may implement many traits. Structs and unions implement traits the same way, with the same `: Trait, Other` header syntax — a union's trait members must all be defaulted or satisfied by a property the union itself supplies, since variants have no syntactic place for a method body.

A trait declares properties and methods, but not fields — `field` is rejected in a trait body. A bare trait property is read-only; to make it assignable, give it an explicit assign accessor. An implementing type then satisfies it with a `public` property, which supplies both accessors:

```ghul
trait Counted is
    count: int, = v;      // readable and assignable
si

class TALLY: Counted is
    count: int public;
    init() is count = 0; si
si
```

Inheriting two *concrete* defaults for the same member from different traits is an error rather than a silent pick, so a diamond has to be resolved by overriding the member in the implementing type.

Like a class, a trait is closed to other assemblies unless it carries the postfix `open` modifier. A closed trait can be implemented, and derived from, only within the assembly it is declared in; an attempt from anywhere else is a compile error. `open` opts in to cross-assembly extension, and is the right choice when a trait exists to be implemented by downstream code:

```ghul
trait Displayable open is
    display(state: DISPLAY_STATE);
si
```

Nothing changes inside the declaring assembly, where a closed trait is implemented and derived from exactly as an open one is. A trait imported from an assembly built before the closure existed is treated as open.

An override or trait implementation can narrow its return type to a subtype of the overridden member's, as `make() -> CIRCLE` narrows `make() -> SHAPE`: it is still the override, so a caller holding the base class or the trait reaches it and a caller holding the narrower type gets the narrower return. Only a reference type narrows this way - a value type in place of a reference is a different representation rather than a narrower one - and any other difference in return type is an error at the member.

An override or trait implementation must keep the overridden member's optionality contract. It may strengthen it - a non-optional return or property where the base declares optional, an optional parameter where the base declares non-optional - but weakening it in either position is a compile error: returning `T?` where the base promises `T` would hand null to callers that use the base type, and requiring a non-optional parameter where the base accepts `T?` would receive null from them. A property with an assign accessor faces both directions at once, so its type must match the base's optionality exactly. The equality and order operators `=~` and `<>` are the one exception on the parameter side: presence is settled where the operator is used and the body is only handed present values, so an implementation may declare its parameter non-optional even where the overridden member spells it optional.

### unions

A union is a reference type that holds one of several variants. Each variant has a name and an optional list of fields:

```ghul
union Tree is
    NODE(left: Tree, right: Tree);
    LEAF(value: int);
si
```

A variant is constructed through the union name (`Tree.LEAF(123)`). A variant with no fields — a *unit variant* — is referenced by name without parentheses, and is interned to a single shared instance per generic instantiation:

```ghul
union Color is
    RED;
    GREEN;
si

union Option[T] is
    SOME(value: T);
    NONE;
si

let c: Color = Color.RED;
let n: Option[int] = Option.NONE;
let n2: Option[int] = Option.NONE[int];
```

Type arguments on a unit-variant reference are inferred from the surrounding context (declared LHS type, function-argument slot, return slot) the same way the parenthesised constructor form infers them; the explicit `[int]` is only needed when no context is available. The parenthesised form (`Color.RED()`, `Option.NONE()`) still works and yields the same interned value.

Discriminate a union value with `isa V(x)` or `if let v: V = x` — both test the runtime variant, and `if let` binds the value at the narrower variant type for use in the then-arm:

```ghul
if let node: Tree.NODE = tree then
    write_line("node: {node.left} and {node.right}");
elif let leaf: Tree.LEAF = tree then
    write_line("leaf: {leaf.value}");
fi
```

Both `isa V(x)` and `if let v: V = x` narrow `x` itself inside the then-arm and inside guard-then-return tails, and on a two-variant union narrow the `else` branch to the other variant — member access on the scrutinee in the else arm resolves against the complement variant. A `case` over a union scrutinee is checked for exhaustiveness: missing variants draw a `non-exhaustive-case` warning on the statement form, and are an error on the expression form, which has to produce a value. A `redundant-case-arm` arm fires when a later arm matches nothing the prior arms didn't already cover, and `dead-case-else` fires when the `else` arm is unreachable because the preceding arms cover the domain. The warnings also fire on `bool` and `bool?` scrutinees, on `T?` of a union, on closed class hierarchies (the in-assembly subclasses are the closed set — plus the root type itself when the root is concrete, since it is then constructible) and on enums. An arm that names a unit variant by value (`when Color.RED then`) covers that variant exactly as `when _: Color.RED then` does, since a unit variant has a single shared instance; and a label in a `case` takes its type from the scrutinee, so a generic union's unit variant needs no type arguments there (`when Option.NONE then` over an `Option[int]`).

Exhaustiveness also reaches through a destructure. A scrutinee that destructures — a tuple, or any type with a `deconstruct` — is covered when the arms cover the *combinations* its elements can take, for as long as every element sits in a closed domain of its own; the same rule applies again to a nested destructure. So four arms cover a `(bool, bool)` with no `else`, and two arms cover it when each leaves one element unmatched. Coverage is over the combinations rather than each element separately, so `when (true, _)` and `when (_, true)` together leave `(false, false)` open. An element drawn from a domain that cannot be enumerated (`int`, `string`, an open class hierarchy) leaves the whole scrutinee open, and so does a field the arms only test rather than bind — `when (0): WHOLE` reaches part of `WHOLE`, not all of it.

A `case` whose scrutinee cannot be covered this way, and which has no `else` arm, fires `case-needs-else`: a warning on the statement form, where it just falls through; a warning on an expression form whose expected type has a default (value type or `T?`); and an error otherwise. A destructurable scrutinee left short of its combinations reports the same way, naming the combinations that are still open.

Unions compare by structural equality through the `=~` operator — two union values are `=~` when they hold the same variant with memberwise-equal fields. Each field compares the way `=~` compares two values of its type anywhere else: through the field type's own `=~` where it defines one, through its `<>` read against zero where it defines only that, element by element for an array or a list, and through the runtime's default equality comparer otherwise — a class that overrides `equals` compares through it, one that neither declares nor has a synthesised operator compares by reference, and a struct or tuple field-by-field. A field of bare type-parameter type compares through the runtime's comparer for that type, which reaches whatever equality the type argument provides.

A field whose type is declared in ghūl source, could declare `=~` and does not, draws a `synthesized-equality-fallback` warning on the field's declaration: the union's structural equality compares that field with the default equality comparer rather than an operator. Types that cannot declare an operator — imported types, tuples, sets, maps, function types — fall back without a warning; an array or a list does not fall back at all, since it compares element by element. Suppress via `@suppress("synthesized-equality-fallback")` per declaration or per file, or with `--suppress synthesized-equality-fallback` project-wide.

A union with exactly one variant carrying fields of *its own* behaves as an option type: `u?` tests whether that variant is present and `u!` unwraps its value. Fields inherited from a union primary-constructor header don't count towards this, so a variant that carries only spliced shared fields is still a unit variant for the purpose of the rule. A union with several field-carrying variants can mark one with a trailing `default` to nominate it as the variant `?` and `!` act on:

```ghul
union Result[T, E] is
    OK(value: T) default;
    ERROR(error: E);
si
```

`r?` is then true when `r` holds `OK`, and `r!` unwraps the `OK` payload, throwing if `r` holds `ERROR`. A default variant with one field unwraps to that field positionally — the field name does not have to be `value` — and with several fields, it unwraps to the variant. Inside an `if r?` the variable narrows to the default variant — so its fields read directly, no `!` needed — and the `else` branch narrows to the remaining variant(s), the same narrowing `isa OK(r)` performs.

A union may declare a **primary-constructor header** for state shared across every variant. Each variant then splices the shared parameters into its field list with `..`:

```ghul
union TRIVIA(location: LOCATION) is
    LINE_COMMENT(text: string, ..);
    BLOCK_COMMENT(text: string, ..);
    BLANK_LINE;
si
```

The primary parameters become fields on the union base, so `t.location` reads through on any `TRIVIA` value regardless of variant; variant-declared fields like `text` stay variant-only. The `..` may appear at any position in the variant's field list; field order in the synthesised constructor and in positional destructure (`let (a, b) = trivia`) follows source order. A variant that carries no additional fields can be written without a field list at all (`BLANK_LINE;`) and is treated as if it had written `(..)`. A variant with additional fields must include exactly one `..`. The mechanism mirrors the class secondary-init splice ([primary constructors](#primary-constructors)).

A union may declare traits it implements after its header, with a leading `:` (and after any primary-constructor params):

```ghul
trait NAMED is
    name: string;
    label() -> string => "[{name}]";
si

union COLOUR(name: string): NAMED is
    RED(..);
    GREEN(..);
    BLUE(..);
si
```

`NAMED.name` is satisfied by the property synthesised from the union's `name` primary parameter, and `NAMED.label` is inherited by every variant. A `NAMED` reference accepts any `COLOUR` value, with dispatch going through the union base class. The traits-only restriction is strict: a union may not declare a base class. Every trait member used through this header form must either be defaulted or be a property the union already supplies (typically through a primary parameter), since neither the union body nor its variants can carry method bodies; to give a union method implementations for a trait, use an [`impl` block](#partial-and-impl-blocks).

A method or property accessor supplied to a union, or to one of its variants, through a [`partial` or `impl`](#partial-and-impl-blocks) block must be pure: declared `pure`, or provably store-free. One that stores draws an `impure-union-method` warning.

### enums

An enum is a set of named integer constants, counting from 0 unless given explicit values, reached as `Suit.HEARTS`. The enum type takes a PascalCase name and its members UPPER_SNAKE_CASE; a trailing comma after the last member is allowed:

```ghul
enum Suit is
    HEARTS,
    DIAMONDS,
    CLUBS,
    SPADES,
si

enum Status is
    OK = 200,
    NOT_FOUND = 404,
si
```

Enum values compare with the relational operators as well as for equality (`=~` and `==`), so they order by their underlying integer. `=~` works over an optional enum too, as it does over any other optional. An individual member can be imported by name — `use Some.Namespace.Suit.HEARTS;` — as well as reached through the type.

An enum carrying `System.FlagsAttribute` — via the ordinary .NET-attribute pragma, see [.NET interop](#net-interop) — additionally gets the bitwise operators `&`, `|`, `^`, and the unary `\`, for combining and testing flag-shaped values. Each takes and returns the enum's own type — there is no coercion to or from the underlying integer, and combining two different enum types is a compile error, the ordinary overload-resolution failure. An enum without the attribute has none of the four: an ordinal enum's members were never meant to combine, so `Suit.SPADES & Suit.HEARTS` is rejected the same way as any other undefined operator.

```ghul
@System.Flags()
enum Access is
    READ = 1,
    WRITE = 2,
    EXECUTE = 4,
si

let read_write = Access.READ | Access.WRITE;

if read_write & Access.READ == Access.READ then
    write_line("can read");
fi
```

Unlike C#, where `[Flags]` changes nothing about which operators an enum has — `&`/`|`/`^`/`~` there work on any enum, built into the language — `System.FlagsAttribute` in ghūl gates the four operators as well as its usual effect on `to_string()`: it makes the default rendering of a combined value list its constituent names (`READ, WRITE`) instead of the raw number, exactly as it does in C#. ghūl has no attribute for naming a combined value as a member (`ALL = A | B | C`): an enum member's initializer is restricted to a plain integer literal.

### partial and impl blocks

Members can be added to an already-declared type from a separate block - even a separate file - as long as the type is declared in the same assembly. The added members are real members of the target: full private access and normal virtual dispatch, indistinguishable from members written in the type's own body.

A `partial` block adds members to the type it names:

```ghul
class VISITOR is
    _depth: int;
    init() is _depth = 0; si
si

partial VISITOR is
    visit_expression(e: EXPRESSION) is ... si
si
```

`partial` carries no interface clause - interfaces stay in the type's header. It applies to classes, structs, and unions; for a union, whose body holds only variants, it is the only way to give the type methods.

An `impl` block additionally makes the target implement an interface:

```ghul
trait Printer is print() -> string; si

union List[T] is
    NIL;
    CONS(head: T, tail: List[T]);
si

impl Printer for List[T] is
    print() -> string =>
        if let (head, tail): CONS = self then "{head} {tail.print()}" else "nil" fi;
si
```

The interface's type parameters are the target's own, written on the target after `for` (`impl Printer for List[T]`). Inside the body `self` has the concrete target type, so a union's variants can be matched on directly. The target then satisfies the interface exactly as a header-declared one would - a `List[T]` passes wherever a `Printer` is expected, dispatching through the type's base. A self-relational interface takes the target as its own argument: `impl Eq[List[T]] for List[T]`. The interface must be a trait, and the target must be a same-assembly type - an imported type cannot be reopened. When the target is a union or a single variant, every method and property accessor the block supplies must be pure: see [unions](#unions).

The target (and a `partial` block's target) can be a qualified name: a namespaced type (`impl Printer for Some.Namespace.TYPE`) or a specific union variant (`impl Printer for List.NIL`). Implementing an interface on a single variant attaches it to that variant alone - a value statically typed as the variant satisfies the interface, but the union as a whole does not unless it also implements it.

Inside the block, the target's own members, inherited members, and type parameters are in scope first, exactly as inside the target's declaration body. Every other name - the target name after `for`, the interface name, the types in member headers, anything the bodies reference - resolves where the block is written: its enclosing namespace and that namespace's `use` imports. Names that are only in scope at the target's declaration site (its namespace siblings, its own file's imports) are not visible unless they are also reachable from the block's site. Declaration order does not matter: the block can precede its target in the same file or live in a file compiled earlier.

### properties, methods, and visibility

A property is a name and a type, optionally with getter and setter bodies; a property with no bodies is backed by a hidden field. A property is public to read but only assignable within its defining type — prefixing the name with `_` makes it non-public for reading too, to whatever extent the `--underscore-access` policy in [naming conventions](#naming-conventions) sets.

The storage and visibility modifiers available on a primary-constructor parameter apply to a body declaration too: `x: int public` for public read and write, `x: int field` for a plain field rather than an auto-property, and `x: int static` for a static member. The `field` distinction matters most on value types — see [structs](#structs). `private` is the exception: it renames the member it captures, which only makes sense on a primary-constructor parameter. A plain body declaration has no separate name to rename from, so writing `private` on one without an accessor body is rejected; name the member `_x` directly instead.

```ghul
class COUNTER is
    _count: int;

    count: int => _count,
        = new_value is
            assert new_value >= 0 else "count must be non-negative";
            _count = new_value;
        si
si
```

Methods are functions declared inside a class, struct, or trait; they have an implicit `self`. A constructor is a method named `init`. Methods are public unless their name starts with `_`, which makes them non-public under the `--underscore-access` policy — by default visible only to the declaring class. The compiler enforces that gate.

## operators

See <https://ghul.dev/definitions.html#functions>.

An operator is a run of operator characters, scanned as a single token. The ASCII operator characters are `! $ % ^ & * - + = | : @ ~ # \ < > . ? /`, and so is any non-ASCII character Unicode classifies as a symbol, which puts `×`, `÷`, `∪`, `⊕` and `≠` on exactly the same footing as `*` and `+`. An operator can therefore be spelled with the notation it stands for rather than with an ASCII approximation of it.

A function whose name is an operator is used as one. Declared as a member it takes its left operand as `self` and the right as its argument; declared at namespace scope it takes both as arguments, which is how an operator is given to a type you did not write:

```ghul
struct N(v: int) is
    ⊕(other: N) -> N => N(v + other.v);
si

⊗(a: N, b: N) -> N => N(a.v * b.v);
```

Precedence comes from the operator's first character rather than from anything written on the declaration, so an operator that reads as arithmetic binds as arithmetic. From tightest to loosest:

| level | characters |
|-------|------------|
| multiplication | `*` `/` `%` `×` `÷` `✕` `⊗` `⊘` `⊙` `⋅` `∗` |
| addition | `+` `-` `⊕` `⊖` `±` `∓` |
| bitwise | `&` `\|` `¦` `^` `∩` `∪` `⊻` `⊼` `⊽` |
| shift | `<` or `>` doubled |
| range | `..` `::` |
| thread-first | `\|>` `~>` |
| relational | `=` `!` `~` `<` `>` `≠` `≤` `≥` `≈` `≉` `≡` `≢` `∈` `∉` `∋` `⊂` `⊃` `⊆` `⊇` |
| boolean | `∧` `∨`, and `/\` and `\/` |

The thread-first row is the two operators themselves rather than a first character: see [collections and pipes](#collections-and-pipes). An operator opening with `?` sits looser than all of those, and everything the table does not name sits between shift and bitwise. Associativity is left, except for an operator opening with `?`, which is right so that a chain of them stays open to the one after it.

Where the first character does not say what is meant, a `@precedence` pragma places the operator explicitly. It takes the operator and a level: one of the eight `user-1` to `user-8`, which interleave with the levels above, or one of those levels by name. The pragma written before a definition covers that definition; the file-level `@@precedence` covers the rest of the file.

```ghul
@@precedence("∘", "user-8")

∘(f: (int) -> int, g: (int) -> int) -> (int) -> int => x => f(g(x));
```

An operator is an ordinary function, so its name is a value wherever a function
of its shape is expected. The name is written with the backtick escape, since
an operator is not an identifier:

```ghul
struct N(v: int public);

⊕(a: N, b: N) -> N => N(a.v + b.v);

let totals = values |> reduce(N(0), `⊕);
```

A static member operator is named through its type, and reads the same way:

```ghul
struct V(x: int public) is
    +(a: V, b: V) -> V static pure => V(a.x + b.x)
si

let total = vectors |> reduce(V(0), V.`+);
```

The built-in operators on the scalar types are the exception. They are
instructions rather than methods, so there is no function to take the value of,
and naming one is an error: `cannot take the value of built-in operator '+'`.
An instance member is not a value either, operator or not, since it needs a
receiver. What that rules out is ``int.`+`` and ``string.`=~``; a function literal
says the same thing and is what to write instead.

## equality

ghūl has two equality operators, and they ask different questions.

`==` and `!=` ask whether two values are *the same thing*: identical bits for a scalar, the same object for a reference. They lower to a single machine comparison, and every other property of them follows from that. No type can overload or override `==`, so what it does never depends on which type reaches it. It never recurses into a value's contents, so it never depends on how deeply one nests. It never calls anything, so it never throws — comparing two absent optionals compares two nulls rather than dereferencing them. And it never walks a structure, so it costs the same on a megabyte-long string as on an `int`. `a == b` carries exactly one instruction's worth of meaning, and it can be read without knowing anything about the types involved.

The price of that is a narrow domain. `==` and `!=` accept only:

- primitive scalars — the integer types, `single`, `double`, `decimal`, `bool`, `char`
- enum members
- references — `string`, `object`, any class, any trait, and `null` against one of those
- a bare type parameter, where the instantiation decides which of the above it is

Every other operand is a compile error pointing at `=~`. On a struct — a tuple, an imported `System.DateTime`, one of your own — the single comparison would read the value's bytes rather than its fields, which is silently wrong rather than merely limited: a reference field would compare by identity, and padding would compare at all.

**`==` on a `string` is reference identity, and stays that way.** Two strings with the same characters are `==` only when they are the same object, which for two literals they generally are and for anything computed they generally are not. That surprises people, and it is still the right definition, because it is the only one that keeps the four properties above. Compare characters with `=~`.

`=~` and `!~` ask whether two values *mean the same*, and that is a question each type answers for itself:

```ghul
"hello" =~ "{"hel"}{"lo"}"      // true - same characters
"hello" == "{"hel"}{"lo"}"      // false - different objects
```

`=~` resolves on:

- primitive scalars, `char`, `bool`, `decimal` and enum members, comparing by value
- `string`, comparing by characters
- any type that declares `=~` as a member — a class, struct or trait of your own, and any imported .NET type implementing `IEquatable[T]`, which is how `System.DateTime` and `System.Version` get one
- any type a global `=~` is declared for: `=~(a: T, b: T) -> bool` at namespace scope gives `T` the operator without reopening the type, which is the way to give one to a type you did not write, or to a tuple
- a union, through the operator synthesised for it — see [unions](#unions)
- a struct whose state is entirely public and that declares no equality of its own, through the one synthesised for it: member by member, each member through its own type's equality — see [structs](#structs)
- a class carrying an `@equality()` pragma, through the one synthesised for it: member by member and then its base's, each member through its own type's equality — see [classes](#classes)
- a tuple, element by element, each element through its own type's equality, however deep it nests
- an array, a `List[T]` or a `LIST[T]`, by count and then element by element, each element through its own type's equality - so `[[1, 2], [3]] =~ [[1, 2], [3]]` holds, and two lists of a type declaring `=~` compare through it. An element of a class that declares neither `=~` nor `<>` compares by reference here, although the same comparison written directly on two such values is an error: a list of them still has a sensible equality, where the two values alone have none to offer
- a type that declares `<>` and no `=~`: an ordering defines equality with it, so `a =~ b` is `a <> b == 0`
- a bare type parameter, through the runtime's comparer for whatever it is instantiated at

Where more than one of those could answer, the nearest declaration wins: a member operator first, then a global one, and the element-wise or comparer-based comparison only where nothing is declared.

It is not defined everywhere. A class that neither declares equality nor asks for one with `@equality()` does not get one — the operator does not resolve, rather than falling back to identity — and neither does `object`. Nor does a struct that holds any non-public state, or that declares `get_hash_code` or an `equals` over `object` without an operator to go with it: either leaves the struct as it was, with no `=~` until one is written for it. Writing `=~` where nothing defines it is a compile error naming the operand types. A `SET` is not compared element by element, since its equality is order-insensitive: `set_equals` answers that. A pipe is not compared at all, since reading one consumes it.

Defining `=~` on a type means defining `get_hash_code` alongside it: the two are a pair, and .NET's collections consult the hash first. [.NET interop](#net-interop) covers the `Ghul.Equatable[T]` contract, the `Equals` bridge, and why the hash cannot be synthesised.

`=~` is also null-safe, in a way `==` has no need to be: two absent values are equal, an absent and a present one are not, and neither case reaches an operator body. See [optional types](#optional-types).

That holds wherever `=~` is defined at all: `a =~ b` resolves over `T?` exactly when it resolves over `T`, and answers the same for two present values. So an optional enum, an optional tuple and an optional `T` compare like any other optional, with no narrowing first — and declaring `=~(a: T, b: T) -> bool` is enough to make `T? =~ T?` work, whether that declaration is a member or a global.

So on scalars and enums the two agree, and everywhere else they either differ or only one of them is defined. `=~` is the one that means what "equal" usually means; `==` is worth reaching for when identity is the actual question, or when the cost of the comparison is.

## optional types

See <https://ghul.dev/language-basics.html#optional-types>.

A type followed by `?` is an *optional* type — a value of `T?` may be present or absent; the same type without the `?` is non-optional. The postfix `?` tests whether an optional holds a value and `!` reads it out, though `!` is rarely needed directly — a plain `if x?` narrows `x` to its non-optional form, and `if let` tests an optional and reads its value into a variable in one step.

```ghul
let name: string? = lookup();

if name? then
    write_line("hello, {name}");   // name is non-optional string here
fi
```

Optionals cover reference and value types alike. There are three lowerings — a plain nullable reference, `Nullable[T]` for a value type, and `MAYBE[T]` for an unconstrained type parameter, so `T?` is spellable even where `T` could be either kind. Which one backs a given `T?` is an implementation detail: all three behave the same way, and a value of any of them is accepted wherever another is expected — assigned, passed, returned — with the conversion made at that boundary. The one place the three are distinct is as a type argument of another type: `LIST[T?]` over an unconstrained `T` is `LIST[MAYBE[T]]` and not `LIST[string?]` for any `T`, and a function type is a generic type too, so a `(int) -> string?` value is not a `(T) -> U?` for any `U`. There is no boundary inside a type argument to convert at, so a call that pins `U` from a *stored* function value of fixed type that way does not resolve; a function whose own return is `U?` over a type parameter has the same carrier and is accepted. A function referred to *by name* is accepted whichever carrier its own signature uses: it has no value yet, so where the two shapes describe the same call and differ only in an optional position's carrier, the reference is wrapped in a literal that presents the slot's own shape, and the coercion happens at that literal's boundary. `bind(unit(8), halve)` resolves for a `halve` returning `int?`, and so does the same reference passed the other way, into a slot whose carrier is the reference one. A shape differing anywhere but the carrier is still rejected. A function literal that leaves its return type to be inferred is not fixed: written into a `(T) -> U?` slot, its return settles as the slot's carrier over whatever the body produces, so `bind(4, n => n + 1)` and `xs |> find_map(x => lookup(x))` both resolve, with a `string?` or a bare `int` from the body converted at the literal's own return. A non-optional `T` is assignable to a `T?` without ceremony; the other direction is a hard rejection. To use a `T?` where a non-optional `T` is expected, the caller must narrow first — `if x?` / `if let` flow-narrow inside the guarded region, `x!` asserts present (throws if absent), and `x ?? _` falls back to a non-optional value. Reading a member, iterating (`for x in xs`), or indexing (`xs[i]`) through an optional receiver the flow analysis has not proven present — an un-narrowed local or member path, a call result — is an error, with the same standing as passing a `T?` where a `T` is required: it is the same fact about the same static type, so there is no slug to suppress and no severity to lower. Narrowing first (`if xs?` / `if let`), `x?.y`, `x.has_value`, and `x!` are the ways through. Applying `!` to a value that was never optional is an error (`cannot unwrap this`) — there is nothing to unwrap. Where flow analysis has already proven a value present — inside an `if x?` / `if let` region — a further `!`, `?`, or `?.` on it draws a redundancy warning (`redundant-unwrap`, `redundant-presence-test`, or `redundant-coalesce`); the fix is to drop the operator. Suppress via `@suppress("<code>")` per declaration or per file, or with `--suppress <code>` project-wide. `--warn-as-error`, `--warn-as-info` and `--warn-as-hint` reclassify a slug's severity the same way. A `?` or `?.` applied to a never-optional *value type* is an error too — a struct can never be null, so the test has nothing to check. On a never-optional *reference* a `?` presence test is redundant by its static type and draws a `presence-test-non-optional` warning, since the type already guarantees presence — though not inside an `assert` condition, where the test is taken as deliberate; a `?.` stays legal, reading as a defensive null test for the case where null can still arrive despite the static type, for example from reflected .NET APIs. Comparing one against `null` is not another spelling of that test: `null` is a value of optional types alone, so `x == null` and `x != null` on a never-optional operand are errors rather than warnings, and the way to write the defensive test is `x?` or `x?.y`. Types that provide `has_value` and `value` properties are treated as optional-shaped: `?` consults those properties on any such type, while `!` does so only on a struct.

An operator declared on a type takes its left operand as `self`, which always holds a value, so no such operator accepts a left operand that may be absent: `a - b` over an un-narrowed `a: T?` does not resolve, exactly as passing that `a` to a non-optional parameter does not. Narrow the operand first, or reach the operator through `a!`. `=~` and `!~` are the exception, and not by declaration: their null checks are written around the call, so an absent left operand is answered rather than dereferenced, whatever the operator itself declares. Any other operator that means to answer for an absent left operand is declared globally with an optional first parameter, where the operand really is an argument rather than a receiver.

The `?.` operator is *coalescing* member access: `a?.b` reads `b` from `a` when `a` is present, otherwise yields the optional null. The result is always optional — a non-optional member type `U` is widened to `U?`, an already-optional `U?` stays `U?`. Receivers may be reference- or value-type optional (`T?` backed by `Nullable[T]`). A flow-narrowed non-optional receiver always takes the present branch and draws a `redundant-coalesce` warning — a plain `.` does the same job. A receiver that was never optional is an error for a value type (`receiver is not optional`); a never-optional reference receiver stays legal as a defensive null test.

```ghul
let p: PERSON? = find(id);
let name = p?.name;              // string?
let length = p?.name?.length;     // int? — chained coalesce
let title = p?.describe();       // string? — method call short-circuits too
```

Method calls compose with `?.` the same way: `a?.foo(args)` calls `foo` on a present receiver — argument expressions included in the short-circuit, so they are not evaluated when `a` is absent — and yields the optional null otherwise. A void method is simply skipped on an absent receiver. Function-typed fields and properties invoked through `?.` (`a?.callback()`) short-circuit the invocation the same way.

The `??` operator is *null-coalescing*: `a ?? b` returns `a` when it is present, otherwise evaluates and returns `b`. The right operand is evaluated only when needed. `??` is right-associative, so `a ?? b ?? c ?? d` parses as `a ?? (b ?? (c ?? d))`; each intermediate result stays optional until the chain is closed by a non-optional fallback. The result type is the LUB of the left's underlying type and the right's type, kept optional iff the right is itself optional — so a chain that ends in a plain `T` returns `T`, and a chain that stays all-optional returns `T?`. `??` works across all three optional lowerings — reference `T?`, value-type `T?` (`Nullable[T]`), and the unconstrained-`T?` carrier `MAYBE[T]` — including mixed-kind operands: the result's optional kind is derived from the LUB of the inner types, and each side coerces to it. A `bool?` plugged with `?? false` reads as absent-means-false in condition position.

```ghul
let name: string? = lookup();
let greeting = "hello, {name ?? "stranger"}";   // string

let primary: string?   = first();
let secondary: string? = second();
let chosen = primary ?? secondary ?? "fallback"; // string
```

`=~` can compare values that may be null, with no narrowing first. The compiler writes the null checks around the call: two absent values are equal, and an absent value and a present one are not. `!~` negates that whole answer, so two absent values are not unequal:

```ghul
let present: THING? = THING(3);
let absent: THING? = null;
let also_absent: THING? = null;

present =~ absent;          // false
absent =~ also_absent;      // true
absent !~ also_absent;      // false
```

An absent value on the left is always answered this way, whatever the operator declares: there is no receiver to call a method on. What the operator's declaration decides is the *right* operand. Declared non-optional, an absent one is answered here too and the body is only ever handed present values. Declared optional — as `Ghul.Equatable[T]`'s example below writes it — the body is handed the absent value and answers for it itself.

A `T?` over a value type or over an unconstrained type parameter compares the same way, with one difference: an absent one of those is always answered by the null checks, never handed to the operator, because a value operand has no absent form to pass.

The same applies to a global `=~`. One declaring non-optional parameters gets the null checks written around it, so its body is only handed present values; one declaring optional parameters is answering for absence itself and is called as written.

Not every type reaches its equality through an operator at all — an enum's is an opcode, and a tuple and a bare type parameter have none (see [equality](#equality)). Those get the same null checks around whatever compares them, so an optional one behaves exactly like an optional of a type that does declare an operator. The rule is that `a =~ b` over `T?` resolves whenever it resolves over `T`.

## control flow

See <https://ghul.dev/control-flow.html>. Most control-flow statements delimit one or more blocks, and each block is a scope.

`if` runs `if` ... `then` ... `fi`, with optional `elif` and `else` clauses; an `else` is the last arm, so an `elif` or a second `else` after it is an error. It is also an expression — every branch must then yield a compatible type. Written without an `else`, the expression yields an optional of its branches' type instead: present when a branch runs, absent when control falls through, the same answer a loop expression gives exhaustion. A context expecting the non-optional type still requires the `else`, as does an `if` whose every branch diverges:

```ghul
if x > 0 then
    write_line("positive");
elif x < 0 then
    write_line("negative");
else
    write_line("zero");
fi

let sign = if x >= 0 then "non-negative" else "negative" fi;
```

### type narrowing

When an `if` or `while` condition proves a stronger fact about a local variable's type, the branch (or loop body) sees it at the narrower type. The common cases are `isa` class or variant tests and a `?` presence test on an optional:

```ghul
if isa CAT(a) then
    // a is narrowed to CAT
    write_line(a.purr());
fi
```

For a two-variant union the `else` branch is narrowed to the other variant. The same applies to a class hierarchy declared in this assembly without `open` — eliminating one direct subclass on the else edge narrows to the others. If the root is `abstract` (only its subclasses can exist at runtime) the chain can collapse to a singleton and reach subtype-only members; a concrete root stays in the in-set, so the narrow is sound but reaches only members the root itself defines.

Narrowing is flow-sensitive: if a guard rejects a type and then leaves the block — by `return`, `throw`, `break`, or `continue` — the code after the guard is narrowed too.

Assignment narrows as well: when the assigned value's static type is strictly more specific than the declared type, the variable reads at that type from the assignment on. This covers a local variable, a global variable, and a top-level `let`; a field or property of a type is not narrowed by a write to it:

```ghul
let pet: Animal mut = CAT();

pet = DOG();
write_line(pet.bark());   // pet is DOG here
```

A null right-hand side contributes only the presence fact, a value-type right-hand side does not narrow (a wider slot holds the boxed value, not the bare struct), and a tuple-typed value keeps the declared spelling so named elements stay reachable. When branches assign different types, the views join back to the common ancestor after the `fi`.

Narrowing applies to local variables (including a function's own parameters), to `self` - an `isa`, `if let`, or destructure on `self` narrows it in place, so a method (typically in an [`impl` block](#partial-and-impl-blocks)) can match its own concrete type or a union's variants without first copying `self` into a local; because `self` is never reassigned its narrow is never dropped by reassignment - to fields, to properties, and to member-access paths built from those pieces. Both the presence and type domains lift: after `if x.y? then`, a repeated `x.y` reads at its non-optional type; after `if isa CAT(x.y) then`, a repeated `x.y` reads at `CAT`, so `x.y.purr()` type-checks. `if let p: CAT = x.y` narrows the same way. The else edge narrows to the complement when the receiver is a closed hierarchy (a two-variant union collapses to the sibling variant; a closed class hierarchy eliminates the tested subclass from the in-set), so `if isa CAT(x.y) then x.y.purr() else x.y.bark() fi` type-checks on both arms when `x.y` is a closed `Animal`. Sibling / class-and-trait narrows on a path compose via intersection: after `if isa Purring(x.y)`, `x.y` exposes both `Animal` members and `Purring` members. Every hop must be a field or a property. The facts differ in how long they last. A local's narrow holds until the local is reassigned; the assignment then re-narrows to the new value's static type when that is strictly more specific, and otherwise leaves the local at its declared type. A global variable re-narrows the same way, but its narrow is a heap fact rather than a local one: a callee can name and write it, so the narrow drops at a call the compiler cannot show left it alone. Direct stores are tracked precisely: a field's fact drops at an assignment to that same field through any receiver - the written receiver may alias the one the fact was proven on - a property's fact drops at any assignment to a field, property or element, because its getter may read anything the assignment changed, and a path fact drops at a store to anything it reads through, or when its root is reassigned.

One kind of local is treated as heap state: a local that a function
literal assigns. Such a local does not live on the stack - the
closure body and the enclosing scope share one cell - so a call can
rewrite it where the enclosing scope cannot see. Its facts form
exactly as any local's do and survive calls the way a field's do: a
call that provably leaves the local alone - a store-free callee, or
one whose solved write set does not name it - keeps them, and one
that invokes the assigning closure, directly or through anything that
can reach it, drops them. The remedy is the usual one: test the value
again, or copy it into a local variable first.

```ghul
let s: string? mut = get();

let clear = () -> void is
    s = null;
si;

if s? then
    write_line("{s.length}");    // fine: nothing ran between test and use

    clear();

    write_line("{s.length}");    // error: the call can change s, so s is string? again
fi
```

A fresh local declared by `if let` is out of every closure's reach,
so its facts survive any call:

```ghul
if let present = s then
    clear();

    write_line("{present.length}");
fi
```

A heap fact lives from the test that establishes it to the first call the compiler cannot show left it alone, or the first store that could change it; at that point the value reads at its declared type again. That question is settled once the whole program has compiled, so the narrowed view a call leaves behind is the one the effect relations justify, and every use after the call is typed against it: passing the value where only the non-optional or narrower type is accepted is the ordinary type error, and reading a member through it is the ordinary error for a dereference through an optional. The fix is to test the value again, or to copy it into a local variable before the call - a local no closure assigns is unreachable to any callee, so its facts survive every call. Re-observing the value re-establishes the fact whatever calls came before: a presence test, an unwrap `!`, a coalescing `?.`, an `isa` test and an `if let` all check the value at run time. So `if _f? /\ mutate() then` enters its branch with `_f` at its declared `string?` when `mutate` cannot be shown to leave `_f` alone: passing `_f` where a `string` is required there is an error, `_f.length` is an error, and `_f!.length` is fine. The editor marks the call that dropped the fact with a `◄` hint naming what it can change.

Whether a call left a fact alone is judged member by member, once the whole program has compiled: a call is harmless to a fact when nothing it can reach - overrides and invoked function values included - writes the member the fact describes (for a presence fact, writes it a possibly-absent value), and harmless to a fact read through a getter when nothing it can reach writes anything that getter reads. A store-free callee is harmless to every fact. A small curated set of imported .NET members sits between store-free and unproven: the collection mutators `LIST.add`, `LIST.insert`, `LIST.remove_at`, `LIST.clear`, `STACK.push`, `STACK.pop`, `STACK.clear` and the `StringBuilder` writers store only their own receiver's internal state and call nothing while doing it, so they are harmless to any fact that does not read through a getter of that state. So `if _name? then _items.add(x); _name.length` type-checks, and the same `_items.add(x)` before a leaning use of a property whose getter reads `_items` draws the report. Trust also follows from shape rather than from enumeration: an imported .NET static whose parameters are all scalars, strings or enums has no receiver and nothing overridable to name, and counts as store-free; an imported instance member the CLR binds statically (non-virtual, final, on a struct, or on a sealed owner) with such parameters can only write its own receiver's interior, so field facts survive it while property facts still die. Generic methods, static-virtual interface slots, and members of a generic owner are excluded, since their bodies can dispatch through a type parameter — `LIST[T].sort()` is generic-owned this way even though it takes no arguments to name one. A global function imported from another ghūl assembly is a CLR static too but is not one of these: its body is arbitrary ghūl source rather than a .NET surface, so it earns this trust only by being declared `pure`, the same as code of your own. A static can still route through mutable ambient state its parameters don't name - `Console.write_line(s)` dispatches through whatever writer `Console.set_out` last installed - and this is accepted rather than guarded against: redirecting a stream that pervasive into something that mutates narrowed state is not a realistic hazard, and declining every string-taking static to cover it would cost the tier its point. The set lives in the compiler and cannot be extended from source; `pure` is the declaration to write for code of your own, and it claims something stronger - that the function stores nothing at all. The getter a fact reads through is held to the same standard: the fact is only presented as a narrowing when the getter's own call, treated as any other crossing over the fact, is discharged. Store-free is sufficient but not necessary - a write-only getter, whose writes are disjoint from everything it reads, is self-stable and backs the fact. When the getter cannot back it, the test presents no narrowing at all: no narrowing inlay at the test site, hover reports the declared type, and the editor leaves a hint at the test naming the getter, since such a getter can answer differently on every read; the fix is `if let`, a local variable, or — when adjacent reads genuinely agree — declaring the property `stable` (below). One getter shape is proven rather than refused: a **monotone memoiser**, whose body writes only one field of the receiver, writes it only values that are always present, returns absent only under a guard that proved that field absent, and returns that field on every other path, cannot change its answer from present to absent - so a presence fact through it survives even the getter's own call, and leaning on the presence is sound. A type fact through the same getter is still declined: a rewrite while the field is absent can change the runtime type a wider-typed member holds.

Where proof falls short, declare it: a postfix `pure` modifier on a function or method (`describe() -> int pure is … si`) trusts it as effectively store-free, so a fact survives a call to it, without the body being provable. The declaration is a contract — every override or trait implementation must itself be pure, declared or proven, and violating that is a compile error, enforced even when the pure base was imported from another assembly. A postfix `pure` on a function type (`filter(p: (T) -> bool pure)`) extends the contract to a slot holding a function: only a store-free value is accepted — a literal whose body performs no possibly-storing call, heap store, or local reassignment, a store-free named function, or a value already of pure function type. The slot can be a parameter, a variable, a field, or a return type, and putting anything else in one — passing it, assigning it, initializing with it, returning it — is reported. The two positions carry different slugs, because they are worth different things. Passing one as an argument draws `impure-function-argument`: the enclosing call is judged on its own callee anyway, so narrowing there does not depend on the warning being heeded, and it is advice. Storing one into any other kind of slot draws `impure-function-value`, and that one does carry weight: the value is in the slot from then on, and invoking a value through a pure function type is trusted to leave every fact alone, so a stale fact can be relied on across a call that really does invalidate it. Heed that warning, or don't declare the slot pure.

A property can make a parallel declaration about its getter with a postfix `stable` modifier (`value: string? stable => …`): two adjacent reads with nothing between them agree on presence and runtime type. It is the escape for a getter the crossing question cannot prove — a general memoiser, a cache — the case where `pure` would be false, because the getter stores. Facts narrowed through a declared-stable property are presented although the body is unprovable, and the getter's own re-read discharges for presence and type alike; other calls cross the fact as usual, judged against what they can write and the getter reads. On a member-access path the declaration covers only the property it is on — a stable hop deeper in the path re-reads to the same object, but the getter may write through that object, so a fact about a further member still owes the hop's call; copy the prefix into a local instead. `stable` is orthogonal to `pure` — a memoiser is impure and stable — and it is a contract in the same sense: every override must itself be stable, declared or proven self-stable by the same crossing question, and violating that is a compile error, enforced even when the stable base was imported from another assembly.

Being store-free is a property of the function rather than of the slot it is going into, so a function value's own type reports it: a literal whose body proved store-free, and a reference to a function that is declared `pure` or proved store-free, both have a pure function type, and it shows wherever that type does.

```ghul
double(x: int) -> int pure => x * 2;

let f = double;                      // (int) -> int pure
let g = (n: int) -> int => n * 2;    // (int) -> int pure — proved store-free
```

A variable whose type is a pure function type is trusted to hold a store-free value wherever it is read, which is why it is the store into one that carries the warning, and why the trust is only worth as much as the values put in. It is a declaration in the same sense `pure` on a function is: neither is verified, and both mislead the compiler if they are not true. Reassigning such a variable is unremarkable as long as the new value is store-free too. Purity declarations and pure function types survive compilation into an assembly and are honoured when it is imported.

The same declaration can be made once for a whole type: a postfix `pure` on a class, struct or trait header (`class PARSER pure is ... si`). Every instance member must then be pure - proven store-free, or declared - and a member that stores draws an error naming it. Declaring the member `pure` is the escape: trusted, not verified, exactly as anywhere else. The exemptions are the writes that have to exist: constructors assign fields by definition; static members keep their own state and can be marked individually; and the sanctioned write paths are assign accessors and the ref-parameter writes of the synthesised `deconstruct` - though a getter that stores through an assign accessor still draws the error, because from the outside it reads as a read, and a hand-written `deconstruct` is an ordinary member with no such allowance. What a pure type does not allow is publishing a write: declaring a property `public` makes its assign accessor publicly reachable, and that is rejected on the class, the struct, and the primary-constructor parameter alike. `pure` on a union is an error, since union members are already held to purity through partial and impl blocks.

A member declared with no body in a pure type carries an implicit `pure` declaration: it is a contract rather than an implementation, so implementors inherit the obligation through the ordinary override rules. A class implementing a pure trait cannot supply a storing method any more than it could override a declared-pure member.

The type-level marker is a discipline for the declaring assembly and its readers rather than a cross-assembly contract of its own: members that are declared or proven pure cross assemblies individually and keep their guarantees there, and the override contract binds implementors in exactly the same way.

### if let

`cast T?(x)` views `x` as a `T`, yielding the absent value rather than throwing when `x` is not a `T` - so the result is one a presence test can ask about. Written without the `?` the cast is checked: a value that is not a `T` raises `System.InvalidCastException` there rather than becoming a null in a slot whose type says it is never absent, and the `cast-may-throw` warning says so at the site. Two targets are unaffected and still yield rather than throwing: a value type, which gives that type's default, and a type parameter, which can stand for either kind and so cannot be checked at the cast - inside a generic, `cast T(x)` can still produce an absent value in a non-optional slot. `if let` folds a cast and a presence test into the `if` itself — a `let` in the condition, with the then-branch running only when the value is present and the variable narrowed and in scope just there. A type on the variable makes it a type test; `elif let` chains them:

```ghul
if let c: CAT = a then
    write_line(c.purr());
elif let d: DOG = a then
    write_line(d.bark());
else
    write_line("some other animal");
fi
```

A value type can be the type tested for. Over an `object`, `if let i: int = o` matches a boxed `int`, and over an `int?` it matches a present value. Over a plain `int` or `long` there is nothing to test, and the ascription is an error.

With no type, `if let` simply tests that the value is present — the natural way to consume an optional, since the variable has the non-optional type within the branch. The `let` can also destructure:

```ghul
if let line = reader.read_line() then
    write_line("read: {line}");
fi

if let (name, _) = lookup(id) then
    write_line("found {name}");
fi
```

A destructure leaf can also be a literal — an integer, float, string, character or boolean literal, `null`, or a qualified enum-member name. The leaf is then an equality test against the source position rather than a declaration; the arm only runs when every literal leaf matches and every named leaf binds. The test compares the way `=~` would, so a string leaf matches by content rather than by identity, and a leaf against an optional source position never matches an absent value. A `null` leaf is a presence test rather than a comparison, and matches absence across all three optional representations. This is the same comparison a `case` `when` label makes:

```ghul
if let (1, name) = pair then
    write_line("first is one: {name}");
fi

if let (Color.RED, label) = entry then
    write_line("red: {label}");
fi
```

A bare name in leaf position declares a variable, so it always matches and never tests. A leading `~` says the opposite — match the source position against the value that name already holds:

```ghul
use Colour.RED;

if let (~RED, label) = entry then
    write_line("red: {label}");
fi

if let (~expected, name) = pair then
    write_line("expected: {name}");
fi
```

The marked value is read where the pattern is, so it need not be a constant — a local variable, a parameter, or a field all work, which is what the dotted spelling cannot express. `~` is accepted on any leaf that is a legal value to match, so it can be written on a literal or a dotted name too, where it changes nothing (`(~1, s)` and `(~Colour.RED, s)` match exactly as `(1, s)` and `(Colour.RED, s)` do). A marked leaf counts towards exhaustiveness exactly as the unmarked spelling would: marked enum members and booleans complete their closed domain, while a value from a domain too large to enumerate leaves the `case` needing an `else`.

Matching leaves — literal, dotted, or marked — are only allowed in refutable contexts (`if let`, `while let` and `case`-when patterns); a plain `let` with one is rejected, because the value test would be silently skipped at runtime. For the same reason `~` is rejected on a formal argument or a lambda parameter, where a leaf can only bind, and on a whole destructure group rather than a leaf.

Trailing `/\`-separated *guards* gate entry on additional conditions evaluated after the test, with the new variable in scope:

```ghul
if let c: CAT = animal /\ c.is_friendly then
    write_line("friendly cat: {c.name}");
fi
```

The clause's presence test runs first; if it succeeds, each guard runs in source order under the narrowed environment. Failure at any clause falls through to the next `elif`/`else` arm. The clause's initializer is whatever precedes the first `/\`; anything after is a guard, so a top-level `/\` in `if let` position always reads as a chain — its result would otherwise be `bool`, which is never refutable.

A single `if let` can chain several comma-separated clauses; every clause's presence test and optional `/\` guard must succeed for the then-arm to fire. Later clauses' scrutinees see earlier clauses' variables, so the value flows left to right:

```ghul
if let outer = holder, inner = outer.value then
    write_line("inner: {inner.label}");
fi

if let c: CAT = a, d: DOG = b then
    write_line("a cat and a dog: {c.name} and {d.name}");
fi
```

A failure at any clause's test or guard short-circuits straight to the next `elif`/`else` arm — earlier clauses' variables then aren't in scope.

When the tested value is a member path and the variable should simply take the path's last name, the `name =` can be omitted: `if let x.y.z` declares `z`, holding the value, refutable on the path's own optionality exactly as the full form `if let z = x.y.z` would be. `if let path: T` does the same with a type test. The shorthand composes with guards, comma-chained clauses, and `while let` exactly like the full form:

```ghul
if let order.customer then
    write_line("customer: {customer.name}");     // customer = order.customer
fi

if let zoo.pet: CAT /\ pet.is_friendly then
    write_line("{pet.name} says meow");
fi

while let queue.head do
    process(head);
od
```

The shorthand needs a path — for a bare optional local, `if x?` already narrows the variable itself, with no new name to introduce.

ghūl has no construct spelled `match`; variant tags, narrowing, `if let`, and `case` patterns cover that ground.

### loops

`while` tests its condition before each iteration; `do` ... `od` is an unconditional loop, left through `break`. `for` steps over anything iterable — a range, an array, a list, a map — and the loop variable's type is the element type, which can be destructured:

```ghul
while counter < 5 do
    counter = counter + 1;
od

for i in 1::5 do
    write_line("number {i}");
od

for (key, value) in dictionary do
    write_line("{key} = {value}");
od
```

A value that is a sequence and its own iterator as well, as a generator is, is read through the iterator it hands out, so each loop over it starts from its beginning; a struct iterator such as a range is read directly. Every loop supports `break` to exit and `continue` to skip to the next iteration. A loop disposes nothing it iterated: for a sequence holding a resource, see [collections and pipes](#collections-and-pipes). The range operators work in any expression: `..` is inclusive of its start and exclusive of its end (`0..3` is 0, 1, 2), and `::` is inclusive of both (`1::5` is 1 through 5). The from-the-end forms (`..<`, `::<`, `..<<`, `::<<`) are for indexing rather than iteration — see [arrays](#types-and-literals).

Any loop (`for`, `while`, `do`) can be labelled by prefixing it with an identifier and a colon, and `break` and `continue` can then name the loop they act on, letting an inner loop exit or advance an outer one:

```ghul
outer: for i in 0..3 do
    for j in 0..3 do
        if j > i then
            continue outer;    // next i
        fi

        if i == 2 then
            break outer;       // exits both loops
        fi

        write_line("i {i} j {j}");
    od
od
```

A `break` or `continue` that names no enclosing labelled loop is a compile error.

### loops as expressions

Every loop form is also an expression of optional type `T?`. A `break E` exits the loop producing a value; falling off the end — a false condition, an exhausted iterator — produces the absent value:

```ghul
let found: int? = for x in xs do
    if pred(x) then break x fi;
od;

if let hit: int = found then
    write_line("found {hit}");
fi
```

The loop's type is the least upper bound of every valued break, wrapped in `?`. Exhaustion and `break null` are indistinguishable, and a bare `break` exits without a value — all three yield absence:

```ghul
let name: string? = while remaining do
    let line = read_line();

    if !line? then break null fi;      // same as falling off the end
    if is_interesting(line) then break line fi;
od;
```

When the context already expects an optional — a typed `let`, a call argument, a return — the loop's element type comes from it, and break expressions infer against the unwrapped type like any other expression in that position.

A valued `break` delivers to the innermost enclosing loop *that consumes a value*. Loops that are not expressions are exited through on the way, so one break can carry a value out of several nested loops to the loop whose value it feeds:

```ghul
let hit: (int, int)? =
    for x in rows do
        for y in cols do
            if good(x, y) then break (x, y) fi;
        od;
    od;
```

A valued break with no consuming loop anywhere around it is a compile error, the same as returning a value from a void function.

Labels belong to the statement forms: a loop carrying a `label:` prefix cannot also sit in expression position. For long-range exits out of deeply nested control flow, a parenthesised block with its targeted returns remains available.

A `while` condition narrows the loop body the same way an `if` condition narrows its then-arm. `while xs? /\ i < xs.count do xs[i] …` reads `xs` at its non-optional type inside the body, and `while isa CAT(a) do a.purr() od` calls a `CAT`-only member without an inner cast.

`while let` is the loop counterpart of `if let`: the loop runs while the refutable clause matches, with the declared names freshly in scope on each iteration. The same shapes work — bare presence (`while let line = reader.read_line() do …`), type ascription (`while let c: CAT = a do …`), destructure, `/\` guards (`while let c: CAT = a /\ c.has_whiskers do …`), and comma-separated multi-clause bindings (`while let x = a, y = b do …`) where every clause must succeed each iteration. Loop exit is whenever any clause's test or guard fails.

### case

`case` branches on a scrutinee value. Each `when` carries either a value-equality expression list (literals, enum members, named constants) or a binding pattern; `else` catches the rest; the construct ends with `esac`. There is no fall-through. The body of each arm is introduced by `then`:

```ghul
case status
when 200 then
    write_line("ok");
when 500, 501, 502 then
    write_line("server error");
else
    write_line("other");
esac
```

An expression-list `when` matches its labels by value: `case` compares the scrutinee to each label the way `=~` would (falling back to `<>`), so a `string` scrutinee and a user type that declares `=~` both compare their labels by content rather than by identity. An optional scrutinee compares the same way — `=~` is null-safe, so a `T?` scrutinee matches a non-null label only when it holds a value-equal value, and never throws on an absent one. A `when null` label matches absence — a null reference for a reference-type `T`, an absent `Nullable[T]`/`MAYBE[T]` for a value-type or generic `T` — across all three optional representations.

`case` is also an expression: the last expression of each arm body becomes the arm's value, and the `case` evaluates to whichever arm matched. An expression-position `case` needs either an `else` arm, arms that cover the scrutinee's closed domain (a union's full variant set, both bool branches, every combination of a destructured tuple, etc.), or — over a scrutinee that cannot be covered, with an expected type that has a default value (value type or `T?`) — none of the above, in which case the `case` produces `default(T)` on the no-match path and `case-needs-else` warns:

```ghul
let label = case status
when 200 then "ok"
when 500, 501, 502 then "server error"
else "other"
esac;
```

A `when` arm can also carry a binding pattern instead of an equality list. The patterns mirror those accepted by `if let`:

- `when v: T then` — type-test against `T`; on match, bind `v` to the narrowed value.
- `when (a, b) then` — destructure a tuple scrutinee into bound names. Per-element ascription works (`when (c: CAT, d: DOG) then`); discards are `_`; literal leaves like `when (1, label) then` or `when (Color.RED, label) then` add a value-equality test at that position, and a `~`-marked leaf like `when (~expected, label) then` tests against the value that name holds rather than binding it.
- `when _: T then` — type-test only, no binding.

Pattern arms share `if let`'s contract on refutability — an option-shaped scrutinee binds to the unwrapped value, and a value-type ascription over a plain value-type scrutinee, which has nothing to test, is rejected with one error and ERROR-typed recovery on the bound names:

```ghul
case animal
when null then
    write_line("nothing");
when c: CAT then
    c.meow();
when d: DOG then
    d.bark();
else
    write_line("just an animal: {animal!.name}");
esac
```

A bare identifier without `:` or `(...)` is still an expression — `when v then` tests equality against the value of `v` in scope, it does not bind a new local. Bindings carry shape information.

A pattern arm can carry a trailing `/\`-guard, evaluated after the pattern binds — the bound names are in scope in the guard and in the arm body:

```ghul
case s
when c: CIRCLE /\ c.radius > 3 then
    write_line("big circle {c.radius}");
when c: CIRCLE then
    write_line("small circle {c.radius}");
when q: SQUARE then
    write_line("square {q.side}");
esac
```

A failing guard falls through to the next arm, exactly as if the pattern itself hadn't matched. A guarded arm never counts towards exhaustiveness — it can decline to run even when its pattern matches, so `non-exhaustive-case` still fires for a variant only ever matched by a guarded arm.

An arm's narrowing works like `if let`'s: an ascribed `when v: T` narrows the scrutinee to `T` inside the arm body, and a guard's own test — a `?` presence test or an `isa` — narrows within the body too. Arm narrowing is local; nothing an arm proves reaches a sibling arm or the code after the `case`.

### block expressions

A parenthesised block `(statement; ...; value)` runs a sequence of statements and evaluates to the value of the last one. Use it in any position that accepts an expression — a `let` initializer, function argument, `=>` body, etc.

```ghul
let x = (let y = 5; y * 2);                 // x = 10
let z = (let a = 3; let b = 4; a + b);      // z = 7
let n = (write_line("setup"); 42);          // n = 42

let box = BOX();
let m = (box.v = 7; box.v * 2);             // assignment statement, then the value
```

A parenthesised group commits to the block reading at the first top-level `;` — or immediately, on a token that can only open a statement (`let`, `try`, `return`, ...) — and stays a tuple, a parenthesised expression, or a lambda's formal parameters otherwise. A compound statement (`if`, `case`, `for`, `while`, `do`) opening the group commits the block reading the same way when what follows cannot continue its expression: `(for x in xs do f(x) od 0)` is a block whose tail is `0`, no `;` needed. An operator-headed tail on the same line is the one exception: any operator can also continue the expression, so the group keeps the expression reading there and the compound statement is the operator's left operand (`(if c then 2 else 5 fi - 1)` is 1 when `c` is true). Only the same line does that — the compound statement ends the line it is written on, so an operator opening the next line begins a new statement like any other, and `(if c then 2 else 5 fi` / `-1)` is a block whose tail is `-1` with no `;` needed. So `(a = f(x), b = g(y))` constructs a named tuple while `(a = f(x); b = g(y); a + b)` runs two assignments and yields the sum; the `,`/`;` is the whole difference, and the elements themselves can be any expression in both. A statement whose expression form already exists keeps it: `(let x = 5 in x * 2)` is the `let ... in` expression, unchanged, while `(let x = 5; x * 2)` is a block with a `let` statement and a tail.

A `let use` written directly in a block is rejected: the block has no disposal region to close it in. One written in a statement list nested inside the block - the body of an `if`, of a loop, of a `try` - has a region of its own and is unaffected.

A common use is loop-as-expression — fold an iterable into a value with the loop body updating a `mut` accumulator and the tail expression handing back the result:

```ghul
let sum_1_to_5 = (
    let acc mut = 0;
    for i in 1..6 do
        acc = acc + i;
    od;
    acc
);
```

If the last statement does not provide a value (a `let`, `for`, `while`, `assert`, ...), the block is void. Void blocks are accepted in any context that tolerates void — an expression-statement, the `=>` body of a void-returning function. A value-required position (typed `let` initializer, function argument, `=>` body of a value-returning function) requires the last statement to be value-producing, *unless* every reachable path through the body diverges (via `return`, `throw`, or a divergent inner `if`/`case`/`try`) — then the trailing statement is unreachable and the block's value comes from the divergence sites instead.

`return E` inside a block in expression position exits the **block**, not the enclosing function. The block's value is the least-upper-bound of every `return E` inside it and the tail expression (if any), so an early return can short-circuit out of the block with a value while a different path falls through to the tail. A `null` among those contributions joins as optionality rather than as a type of its own: the other contributors' LUB widens to its optional carrier (`(let s = f(); return s; null)` over a `string` return is `string?`), an all-null block settles at the type the surrounding context expects when there is one, and draws an error (`all val-block contributions are null`) when there is not. Nesting follows the innermost rule — a `return` inside an inner block exits only that inner block, leaving the outer block's walk to continue.

A block is fine as the *entire* body of an expression-bodied function/method/lambda (the `=> body`). The innermost-block rule still applies — `return` inside targets the block — but the block's value flows back out as the function's expression-body value, so observable behaviour matches `is ... si`. `try` / `catch` / `finally` composes the same way as in any function body, including `return` from inside a `try` (the finally fires before the value is delivered), and a body whose every reachable path returns needs no separate value-providing tail:

```ghul
sign_label(n: int) -> string => (
    if n < 0 then
        return "neg";
    fi;
    if n == 0 then
        return "zero";
    fi;
    "pos"
);

divide_or_default(n: int, d: int) -> int => (
    try
        return n / d;
    catch e: System.DivideByZeroException
        return 0;
    finally
        log("done");
    yrt
);
```

Bare `return;` (no value) is accepted in a void block — same rule as `return;` in a void function — and acts as an early exit. In a value-required block it is an error.

`val ... lav` is the historical spelling of the same construct — `val statement; ...; value lav` and `(statement; ...; value)` are interchangeable everywhere — and is headed for removal; write the parenthesised form.

### exceptions

`throw` raises an exception, which must derive from `System.Exception`. Exception handling runs `try` ... `yrt`, with `catch` clauses and an optional `finally`. A `catch` names an exception variable and a type, and handles that type or any subtype; `finally` always runs, including before a `return` leaves the `try`:

```ghul
try
    risky_operation();
catch e: FileNotFoundException
    write_line("not found: {e.message}");
catch e: IOException
    write_line("io error: {e.message}");
finally
    cleanup();
yrt
```

`throw` can also stand alone as the body of an expression-bodied function, property, or indexer, which is handy for stubbing out code that is not written yet:

```ghul
not_done() -> int => throw System.Exception("not implemented");
```

The body always diverges, so it satisfies any declared return type — explicit, generic, or void — and an inferred return type settles as void.

### assert and return

`assert` checks a condition and throws if it fails. The `else` clause is optional: without one, the thrown message is built from the source location and the condition text.

```ghul
assert index >= 0;
assert index < array.count else "index out of range";
```

A string after `else` is prefixed with the source location and wrapped in a `Ghul.AssertFailedException`; a `System.Exception` value is thrown as it stands. Anything else is a compile error.

In expression position, `assert cond else "msg" in expr` guards a value and chains like `let X in expr`: a failing assert throws, a passing assert yields the inner expression. The narrowing applied by the condition flows into the inner expression, so the guarded value can be used there directly:

```ghul
lookup(key: string?) -> int =>
    assert key? else "key is null" in
    table[key];
```

`return value;` returns from a block-body function, `return;` from a void one.

### asynchronous code

A function is asynchronous when its declared return type is `Tasks.TASK[T]` (the .NET `Task<T>`) or `Tasks.TASK` (the non-generic `Task`). Inside such a function, `await e` is an expression that waits for the task `e` to complete and evaluates to its result, so `let x = await e;` initializes `x` to that result and the rest of the function continues:

```ghul
compute() -> Tasks.TASK[int] is
    let a = await double_async(10);
    let b = await add_async(a, 1);
    return b;
si
```

The source reads top-to-bottom even though execution suspends at each `await`. `await e;` on its own is the value-less form — it waits for the task to complete and discards any result. A function declared `-> Tasks.TASK[T]` may `return` a bare `T`; the compiler delivers the value to the completed task, wrapping it as `Tasks.TASK.from_result(...)` where the body lowers without a suspension. It may also `return` a task, or anything else awaitable, whose result is a `T`. Where the body does not await, that task is what the caller receives. Where it does, the caller already holds the function's own task and a returned one can only complete it, so the return is taken as the task's awaited result - `return t` and `return await t` are the same program there. A void body accepts a task that awaits to nothing the same way.

The operand of `await` need not be a task. Anything following .NET's awaiter pattern is accepted: a type with a parameterless `get_awaiter()` whose result has a `bool` property `is_completed`, a parameterless `get_result()`, and implements `System.Runtime.CompilerServices.INotifyCompletion` (or `ICriticalNotifyCompletion`). The `await` expression takes the type `get_result` returns, void included. `Tasks.ValueTask[T]`, `Tasks.TASK.yield()` and `task.configure_await(false)` all qualify, and so does a type written in ghūl - a struct awaitable that hands its continuation to a scheduler is how cooperative multitasking is built without allocating a task per suspension:

```ghul
use System.Runtime.CompilerServices.ICriticalNotifyCompletion;

struct PAUSE: ICriticalNotifyCompletion is
    _ready: Collections.Queue[() -> void];

    init(ready: Collections.Queue[() -> void]) is _ready = ready; si

    get_awaiter() -> PAUSE => self;
    is_completed: bool => false;
    get_result() is si
    on_completed(continuation: () -> void) is _ready.enqueue(continuation); si
    unsafe_on_completed(continuation: () -> void) is _ready.enqueue(continuation); si
si
```

An `await` over a value that does not follow the pattern is reported, naming the first missing member.

What an asynchronous function *produces* is not fixed to `Tasks.TASK` / `Tasks.TASK[T]` either. Any type carrying .NET's `AsyncMethodBuilderAttribute` is a *task-like* return type: the attribute names a builder type, and the compiler drives that builder instead of the Task one. `Tasks.ValueTask[T]` and `Tasks.ValueTask` work this way, and so does a type declared in ghūl source, which is how a library gives its coroutines a return type of their own rather than a Task:

```ghul
@System.Runtime.CompilerServices.AsyncMethodBuilder(typeof(COROUTINE_BUILDER))
class COROUTINE[T] is
    value: T public;

    init() is si
si
```

A builder written in ghūl declares its members under their ghūl names: a static `create()`, a `start` taking the state machine by reference and calling its `move_next`, a readable `task` property returning the task-like, a `set_result` taking the result (or nothing, for a task-like with no result), a `set_exception` taking `System.Exception`, and `await_on_completed` / `await_unsafe_on_completed` each taking the awaiter by reference. That is the same shape .NET's own builders use.

An `async` function declared `-> COROUTINE[int]` awaits, suspends and returns a bare `int` exactly as a `Tasks.TASK[int]` one does. A generic task-like has exactly one type argument and it is the result type, matching `Task` and `ValueTask`; a non-generic one carries no result. A builder missing one of the required members, or declaring one without the by-reference parameter the lowering passes, is reported at the function that returns its task-like, and a return type that is not a task-like is reported too.

A function literal is asynchronous on the same terms. One that declares a task-like return type is driven through that type's builder, as a named function is. One that declares none takes its task-like from the slot it goes into - a typed local variable, a parameter, a return - and where the slot leaves the result type open, as `spawn[T](body: () -> COROUTINE[T])` does, the result is inferred from the body's returns. Where several overloads share the arity, the body settles which is meant: one that produces a value goes to a formal whose task-like carries a result, and one that produces none to a formal whose task-like does not. A literal with nothing to say otherwise returns `Tasks.TASK` or `Tasks.TASK[T]`.

```ghul
let tick = (name: string) -> COROUTINE is
    write_line("{name} before");
    await scheduler.pause();
    write_line("{name} after");
si;

let handle = scheduler.spawn(s is
    await s.pause();
    return 42;
si);                                   // COROUTINE[int], through spawn[T]
```

An asynchronous function whose return type carries no result - `Tasks.TASK`, or a task-like with no type argument - completes when its body falls off the end, so it needs no `return` and draws no `definite-return` warning for lacking one. One whose return type carries a result still warns, as any value-returning function does. The completion holds whether or not the body awaits - the declaration alone makes the function asynchronous - and a bare `return;` is sugar for the same completed handle. A `Tasks.TASK` function completes through `Tasks.TASK.completed_task`; a task-like declared in source completes through its builder, whose members are driven directly.

`await` may appear inside the body of a `for` or `while` loop, and `return` from inside such a body propagates back through the loop. A `try`/`catch`/`finally` around awaiting code works as expected, including a `return` from inside the `try`; what is not yet supported is an `await` inside a `catch` or `finally` *handler*. Reading `.result` on a returned task surfaces a faulted task as a `System.AggregateException`.

### generators

A function that returns `T{}` — an `Iterable[T]` — and contains `yield` is a *generator*: each `yield` hands the next element to the consumer and suspends, resuming where it left off when another element is asked for. The elements are produced lazily, so a generator can be unbounded.

```ghul
counting(limit: int) -> int{} is
    let i mut = 0;
    while i < limit do
        yield i;
        i = i + 1;
    od
si

for n in counting(4) do
    write_line("{n}");
od

let evens = counting(6) |> filter(x => x % 2 == 0);
```

The pipe combinators chain onto the result with `|>`. Each read of it starts the body from the beginning, with the arguments the generator was called with, and two reads in progress at once are independent: the first read from the thread that called the generator runs it in place, and any other read runs a fresh copy.

`yield in E` yields every element of `E` in turn, where `E` is anything a `for` loop can iterate — a pipe, an array, a list, an iterator. The elements are pulled one at a time as the consumer asks for them, exactly as writing the loop out by hand would, which is what makes it the natural shape for a recursive generator:

```ghul
preorder[T](tree: Tree[T]) -> T{} is
    if let (value, left, right): Tree.NODE = tree then
        yield value;
        yield in preorder(left);
        yield in preorder(right);
    fi
si
```

`E`'s element type has to be assignable to the generator's, and a value that cannot be iterated is rejected the same way a `for` over it would be.

A bare `return` ends the stream early, exactly as falling off the end of the body does. It carries no value: the declared `Pipe[T]` describes the stream the generator produces, not something a `return` inside it hands back.

A function literal whose body contains `yield` is a generator too. It captures the variables around it as any literal does, so a `let` is read as it stood when the literal was constructed and a `let mut` is shared, and each read of what it returns runs the body again, reading them again. Its element type comes from its declared return type, or from the slot it is written into when that expects a `Pipe[T]`, `Iterable[T]` or `Iterator[T]`, or otherwise from its first `yield`; one that no `yield` settles is an error. A nested named function that yields is a generator literal as well, and reaches itself by name for `yield in`:

```ghul
let evens = (limit: int) is
    let n mut = 0

    while n < limit do
        yield n
        n = n + 2
    od
si

walk(t: Tree) -> Pipe[int] is
    if let (left, value, right): Tree.NODE = t then
        yield in walk(left)
        yield value
        yield in walk(right)
    fi
si
```

A generator's return type has to be `T{}`, `Iterator[T]` or `Ghul.Pipes.Pipe[T]` — `yield` in a function declared otherwise is an error. One returning an `Iterator[T]` is read once: the iterator it returns is the one read. A function cannot be both a generator and asynchronous. And as with `await`, `yield` is not yet supported inside a `catch` or `finally` handler.

## collections and pipes

See <https://ghul.dev/functional-programming.html>.

`Collections.Iterable[T]`, written `T{}`, is any sequence (the .NET `IEnumerable<T>`). `Collections.List[T]` is the read-only list trait (the .NET `IReadOnlyList<T>`); `Collections.LIST[T]` is the mutable list. `MAP`/`Map` pair the same way for dictionaries, and `SET` is the mutable hash set, with `Set` (the .NET `IReadOnlySet<T>`) as its read-only trait and `MutableSet` (`ISet<T>`) as its mutable one. `MutableList`, `MutableMap`, `Bag`, `MutableBag` and `STACK` round out the mapping. There is no map literal syntax. A map with fixed contents is written as a list literal of key and value pairs, collected with `collect_map()`, which throws if a key is given twice:

```ghul
let scores = [("alice", 1), ("bob", 2)] |> collect_map();
let total = scores["alice"];
```

A map computed from a sequence takes a key and a value function instead, `words |> collect_map(w => w, w => w.length)`, and one that starts empty and is filled later is constructed with no arguments, `MAP()`, its types taken from how it is used.

A sequence is closed off into a collection by constructing the collection from it: `ARRAY(p)`, `LIST(p)` and `SET(p)` take any sequence, and `MAP(p)` a sequence of key and value pairs, throwing on a repeated key as `collect_map` does. The element types come from the sequence, so a constructor can end a `|>` chain, and `_(p)` constructs whichever of them the context expects:

```ghul
let names = people |> map(p => p.name) |> ARRAY();
let by_name = MAP(people |> map(p => (p.name, p)));
let seen: SET[string] = _(names);
```

A sequence closes off into text the same way. `string(p)` renders each element as `join` does and puts nothing between them, and `string(p, separator)` puts `separator` between each pair, so `word |> reverse() |> string()` is the word reversed, `[1, 2, 3] |> string()` is `123`, and `names |> string(", ")` is the names joined with commas. A sequence's own text, with its brackets, is still what `$` and interpolation give.

The sequence combinators are global functions in `Ghul.Pipes`, each taking the sequence as its first argument, so the thread-first operator `|>` chains them. ghūl provides the usual set, in the manner of LINQ, and none of them mutate the source. They split into lazy stages that return a new sequence — `map`, `filter`, `flat_map`, `skip`, `take`, `cat`, `index`, `zip`, `sort` — and terminals that consume it and produce a value: `reduce`, `sum`, `product`, `collect` / `collect_mutable` / `collect_set` / `collect_map`, `count`, `find`, `find_map`, `first`, `only`, `any`, `all`, `each`, `join`, `append_to`. `collect` produces an array, and `collect_mutable` a `LIST` that can be changed.

```ghul
let numbers = [1, 2, 3, 4, 5];
let evens = numbers |> filter(x => x % 2 == 0);
let doubled = numbers |> map(x => x * 2);
let total = numbers |> sum();                       // 15
let folded = numbers |> reduce(1, (acc, x) => acc * x);
let odd = numbers |> count(x => x % 2 == 1);        // 3, the elements the predicate accepts
```

`sum` and `product` total a sequence of any of the numeric types, taking the
element type from the sequence, so neither needs a seed. Addition and
multiplication each have an identity, so the total of an empty sequence is `0`
or `1` rather than an absent value, which is where the two differ from `min` and
`max`: those answer with a `MAYBE[T]`, since there is no least element of
nothing.

Every read of a pipe starts from the beginning, and two reads in progress at once are independent. That holds however it is read — through `for`, a combinator, a terminal or interpolation — so `for x in p` twice sees every element twice, a read that stops part way leaves nothing behind for the next, and `p |> count()` followed by `p |> only()` walks the whole sequence both times. `p |> take(2)` yields the first two elements every time it is read, and `skip` is how to page. The combinators return `T{}`, and each read of what they return reads its source afresh in turn. A terminal that stops before the end, such as `first` or `find`, disposes the iterator it read, as .NET's own LINQ operators do; a `for` loop does not (below). A generator's `dispose()` releases nothing - it does not run the body's `finally` clauses or dispose an iterator the body is walking with `yield in`. `memo` reads its source once, and every read of it replays what it cached, asking the source for more only past the end of the cache.

A `for` loop does not dispose what it iterated, so a sequence that holds a resource is disposed by naming its iterator and letting `let use` close it. That covers the few that hold one: file and directory enumeration, a database reader, a PLINQ query, and a .NET iterator written with a `using`. It matters where the loop can be left early, since the iterator is then still open.

```ghul
let use lines = IO.File.read_lines(path).iterator

for line in lines do
    if line.starts_with(wanted) then
        return line
    fi
od
```

A pipe can also be started from nothing. `repeat(value)` yields `value` without end and `repeat(value, count)` yields it `count` times; `from(start)` counts upwards from `start` without end, and `from(start, step)` counts in steps of `step`. Collected, a bounded `repeat` is how a list of a given size is made:

```ghul
let seen = repeat(false, 100) |> collect_mutable();      // LIST[bool], a hundred of them
let squares = from(1) |> map(n => n * n) |> take(5);  // 1, 4, 9, 16, 25
```

Lazy and infinite sequences are built with `Ghul.Pipes.stream(initial, advance)`, where `advance` steps from the current state to the next element and state. Nothing forces `advance` to be free of side effects, but it is called lazily and on demand, so it is much easier to reason about when it is. The `||` infix is the step expression — `value || next_state`. A `stream(...)` is an ordinary `Pipe[T]`, so the pipe combinators chain onto it with `|>`. See <https://ghul.dev/functional-programming.html#lazy-sequences>.

The thread-first operator `|>` calls a function with the left value threaded in as its first argument: `x |> f(a)` is `f(x, a)`, and `x |> f()` is `f(x)`. The right-hand side is resolved exactly as an ordinary call, so it can be a free function, a method on an explicit receiver (`x |> box.combine(a)` is `box.combine(x, a)`), or a generic whose type argument is inferred from the left value. Chains associate left to right, so `x |> f(a) |> g(b)` is `g(f(x, a), b)`. It is a plain call, and its right-hand side must be a function call or the name of a function spelled as an operator:

```ghul
double(x: int) -> int => x * 2;
add(x: int, y: int) -> int => x + y;

let a = 5 |> double();           // double(5) is 10
let b = 5 |> add(3);             // add(5, 3) is 8
let c = 5 |> double() |> add(1); // add(double(5), 1) is 11
```

`|>` and `~>` are a precedence level of their own, below range and above relational (see [operators](#operators)), so the subject is everything to the left that binds tighter: `1 + 2 |> double()` is `double(1 + 2)`, and `0..n |> map(f)` maps the whole range. A comparison or a boolean operator stays outside the chain, so `xs |> count() > 3` compares the count and `ready /\ xs |> any(p)` tests `ready` first.

A prefix operator applies to its operand before the chain does, so `!xs |> any(p)` negates `xs` rather than the answer, and `await t |> f()` is `f(await t)`. Parenthesise the chain for the other reading: `!(xs |> any(p))`.

The subject goes into the last call written on the right-hand side, so `x |> box.combine(a)` is `box.combine(x, a)` and `x |> BOX(1).combine(a)` is `BOX(1).combine(x, a)`. Member access, indexing, `!` and `?` written after that call apply to its result, as they would after any call: `xs |> collect_mutable()[0]` is the first element and `xs |> collect_mutable().count` the count. An operator written after the call applies to the result of the whole chain, so `xs |> count() % 2` is `count(xs) % 2`.

A function named with an operator is the one right-hand side that can be written without an argument list, since there is nothing else the bare name could mean. The threaded value is then the only argument, and an argument list is still accepted alongside it:

```ghul
$(o: object?) -> string => "<{o}>";

let d = 5 |> $;                  // $(5)
let e = 5 |> $();                // the same call, written out
```

The operator and the `|>` have to be separated by a space. A run of operator characters scans as a single token, so `5 |>$` is one operator named `|>$` rather than two.

The propagating thread-first operator `~>` is `|>` combined with absence propagation, the way `?.` is member access combined with it. The left value has to be optional; an absent one skips the call — argument expressions included, as `?.` skips them — and yields the absent value, while a present one is threaded in unwrapped, exactly as `|>` threads a value. The result is always optional: a callee returning a non-optional `U` is widened to `U?` as `?.` widens a member's type, and a void callee is simply skipped:

```ghul
parse_port(s: string) -> int?;
clamp_port(n: int) -> int?;
label(n: int) -> string;

let port = text |> trim() |> parse_port() ~> clamp_port() ~> label() ?? "closed";
```

The two operators chain together — a `|>` stage runs unconditionally, a `~>` stage propagates — and `~>` works over every optional kind, including an unconstrained `T?` in a generic. The diagnostics are `?.`'s: a `~>` whose subject was never optional is an error on a value type (`receiver is not optional`) and stays legal as a defensive null test on a reference, and where flow analysis has proven the subject present the operator draws a `redundant-coalesce` warning. Inside a generic the callee sees the unwrapped `T` and its result widens back to the optional of whatever it returns.

A `|>` or `~>` at the end of a line carries the chain onto the next one, which is how a long chain is wrapped. Only a name continues it that way, so a line beginning with anything else leaves the operator without a right side and is reported as one — the next statement is never read as the call.

### list comprehensions

A list comprehension builds an array from one or more sources, in square brackets: the element first, then one or more `for` clauses, each optionally followed by `if` clauses:

```ghul
let squares = [x * x for x in 1::5]                  // [1, 4, 9, 16, 25]
let pairs = [(a, b) for a in 1::3 for b in a::3 if a != b]
let lengths = [name.length for name in names if name?]
```

A `for` clause reads a source the way a `for` loop does, so anything a loop can iterate works, and its variable can destructure (`for (key, value) in map`). Each clause sees the variables of the clauses before it, and the element sees them all. An `if` clause keeps only the elements for which its condition holds, and narrows what it tests, so `name.length` above reads `name` as a `string`. Clauses need no separator, so a long comprehension can be written across several lines.

The result is an array of the element's type, or of the type the context expects: `let objects: object[] = [x for x in ints]`. The `: T[]` annotation a list literal takes works here too. The closing bracket ends the comprehension, so it composes with pipes on either side: `[x for x in xs |> filter(odd)] |> sum()`. A comprehension builds its whole array before anything reads it, so it needs a source that ends: `[n * n for n in from(1)]` never finishes, and draws an `unbounded-comprehension-source` warning. An unbounded or lazily read sequence takes the lazy form below.

The same clauses written in braces make a lazy comprehension, a `Pipe[T]` of the element's type rather than an array:

```ghul
let primes = {n for n in from(2) if is_prime(n)}

primes |> take(10)                                   // the first ten primes
```

A lazy comprehension produces its elements one at a time as the pipe is read, so its source can be one that never ends, and nothing is computed for elements that are never read. It is a generator literal (see [generators](#generators)), so it captures what it reads as any function literal does, and reading it again re-runs its clauses. It composes with `|>` in the same way the array form does. Inside an interpolated string, `{{` is an escaped brace, so an interpolation that starts with a lazy comprehension needs a space: `"{ {x * 2 for x in xs} }"`.

A comprehension's loops belong to it. A `break` or `continue` inside one cannot leave it, and it cannot contain a `yield`, an `await` or a `try`. A function literal written inside it is a body of its own and is not restricted.

## displaying values

The runtime formats any value as text in two ways. `$(value)` gives the text a program shows its user, and is what string interpolation uses for a value its type gives no text of its own (see [types and literals](#types-and-literals)). `inspect(value)` gives the detailed form a REPL or a debugging session wants: the same structure, with strings and characters quoted wherever they appear inside a value. Both take anything, including an absent value, which reads `null`. `$` needs no `use`; `inspect` is in `Ghul`.

```ghul
use Ghul.inspect

struct POINT(x: int public, y: int public)

$(["one", "two"])                 // [one, two]
inspect(["one", "two"])           // ["one", "two"]
inspect("top")                    // top
$(POINT(3, 4))                    // POINT(x = 3, y = 4)
inspect((1, "one", 'c', true))    // (1, "one", 'c', true)
```

A string or character is quoted only inside a value, and only by `inspect`: at the top it is the whole answer, and reads as itself. `$` and `inspect` write a value by these rules, in order:

- `null` for an absent value, and `true` or `false` for a `bool`
- a type that implements `Ghul.Displayable` writes itself, as below
- a tuple as its parts in parentheses, and a map entry as `(key, value)`
- a type that declares its own `to_string` reads as that `to_string`, even when it is also a sequence. The runtime's own pipes, and generators, are the exception: their `to_string` writes their elements, and they are written as sequences
- a sequence, such as an array, a list or a pipe, as its elements in brackets
- a class, struct or union variant ghūl compiled, with no `to_string` of its own, as its type and members: `POINT(x = 3, y = 4)`, `Shape.DOT(size = 2)`
- a value of a type from another language, with no `to_string` of its own, as its .NET type name. Its members are not read, since a property getter can do anything - a task's result waits for the task

A sequence stops after 100 elements with `, ...]`, so an unbounded pipe is written too; stopping there leaves nothing behind for the next read of the value. A value that contains itself reads `<cycle>` where it recurs, and the same value in two places is written in full both times.

A type chooses how it is displayed by implementing `Ghul.Displayable`, whose one method writes the value through a `Ghul.DISPLAY_STATE`. Write a child value with `state.render(child)` rather than with `$(child)`: the state carries the element limit and the values already being written, which a fresh call to `$` starts without. `state.mode` says whether the text is for `$`, `DisplayMode.CLEAN`, or for `inspect`, `DisplayMode.DETAILED`:

```ghul
use Ghul

class SCORE(points: int): Displayable is
    display(state: DISPLAY_STATE) is
        state.append("[")
        state.render(points)
        state.append(if state.mode == DisplayMode.DETAILED then " points]" else "]" fi)
    si
si

$(SCORE(3))                       // [3]
inspect(SCORE(3))                 // [3 points]
```

A `DISPLAY_STATE` can also be made directly, with a mode and a different element limit, and written into: `DISPLAY_STATE(DisplayMode.CLEAN, 3)` writes `[1, 2, 3, 4, 5]` as `[1, 2, 3, ...]`, read back with `to_string()`.

`Displayable` customises the text `$` and `inspect` produce for a value. `Ghul.Renderable` offers other media for the same value, such as an image, which a host like a notebook can show in place of that text: its `representations()` gives each as a MIME type and its content, best first. The host chooses which MIME types it shows, and the text `$` writes is the fallback. A host showing output in a web page does not insert `text/html` or `image/svg+xml` from a value into its own document.

## generics

See <https://ghul.dev/generics.html>.

Classes, structs, traits, unions, methods, and global functions can take type parameters, written in brackets after the name:

```ghul
print_something[T](value: T) => write_line("something is {value}");

struct BOX[T] is
    item: T;
    init(item: T) is self.item = item; si
si
```

A value of an unbounded generic argument type is largely opaque — it can be stored, passed, returned, compared with `=~`, and have the methods of `object` called on it, but little else. Giving the parameter a **bound** — `[T: Bound]` — makes the value behave as its bound, so the bound's members are reachable:

```ghul
trait Named is name: string; si

greet[T: Named](x: T) => write_line("hello {x.name}");
```

A parameter can carry several bounds, joined with `/\` — `[T: Named /\ Sized]`. The value then behaves as every one of them: a member of any bound is reachable, and the actual type argument has to satisfy each bound. The comma spelling declares separate type parameters and is not a way to write two bounds.

A bound's *static* members are reachable through the type parameter itself, written `T.member(...)` — the mechanism .NET's generic-math interfaces (`IParsable[T]`, `INumber[T]`, `IBinaryInteger[T]`, ...) are built on:

```ghul
use System.IParsable;

parse[T: IParsable[T]](s: string) -> T => T.parse(s, null);
```

Consuming such a member is all that is supported. A type cannot *implement* one: nothing binds a type's static to the interface's static slot, and the runtime refuses to load a type that leaves one unfilled, so naming an interface that declares a static member on a concrete type is an error at the declaration. That covers the generic-math interfaces above, which is why a bound on one of them is satisfied by the built-in numeric types and not by a type of your own.

Some of those interfaces declare an **operator** as a static member — `IAdditionOperators[TSelf, TOther, TResult]` declares addition, and `INumber[T]` extends it. Such an operator is written as an operator rather than reached through the type parameter, but only once it has been imported by name:

```ghul
use System.Numerics.INumber;
use System.Numerics.IAdditionOperators.`+;

total[T: INumber[T]](a: T, b: T) -> T => a + b;
```

Without that `use` the operator is not in scope and `a + b` does not resolve, so nothing changes for code that does not ask for it — importing one does not displace the built-in operators either, and `3 + 4` still adds two `int`s the way it always did.

A concrete type needs no import for its own operators. A public static operator a .NET type declares for itself is a candidate wherever a value of that type is either operand (see [.NET interop](#net-interop)), so `Int128.one + Int128.one` resolves as it stands. The import is for a bounded type parameter, whose operators come from the interface rather than from any one type.

A static member imported by name reaches a concrete type as well as a bounded one, so `use System.Numerics.INumber.max;` makes `max(a, b)` available on a bounded `T` and on `Int128` alike.

The arithmetic operators `+`, `-`, `*`, `/` and `%` can be imported this way, and so can the bitwise and shift operators `&`, `|`, `^`, `\`, `<<`, `>>` and `>>>`. The comparison and equality operators cannot: a type says how it orders and compares by defining `<>` and `=~`, and those are what the operators are written in terms of. Each operator is imported from the interface that *declares* it, which for the shifts is `IShiftOperators` however the bound is spelled:

```ghul
use System.Numerics.IBinaryInteger;
use System.Numerics.IShiftOperators.`>>>;

halve[T: IBinaryInteger[T]](a: T) -> T => a >>> 1;
```

A bound can also be a **kind**: `class` for a reference type, `struct` for a value type, `optional` for one that can be absent, and `init` for a type exposing an accessible parameterless constructor. Kinds combine with each other and with a type bound, space-separated, and take no parentheses:

```ghul
make[T: init]() -> T;
find[T: class init](key: string) -> T;
build[T: Named class init](name: string) -> T;
build[T: Named /\ Sized class init](name: string) -> T;   // two bounds plus kinds
```

A trait's type parameter can also declare its **variance**, written after any other constraints: `out` makes it covariant and `in` contravariant. A covariant trait of a subtype is assignable to the same trait of its supertype, so a `Source[CAT]` is a `Source[Animal]`; a contravariant one goes the other way, so a `Sink[Animal]` is a `Sink[CAT]`:

```ghul
trait Source[T: out] is
    next() -> T
si

trait Sink[T: in] is
    take(value: T)
si
```

The compiler checks how the parameter is used: a covariant parameter in an input position, such as a method parameter, is an error, and so is a contravariant one in an output position, such as a return type. Only a trait can declare variance, because .NET allows it only on interfaces; `out` or `in` on a class or struct type parameter is an error. The variance of an imported type, a function type or an array comes from .NET.

The CLR kind constraints on an imported generic (`where T : class`, `struct`, `new()`) are enforced too, at the point a type argument is resolved. Type arguments can be given explicitly (`print_something[int](1234)`) but are usually inferred — from the call arguments of a function or method, from the constructor arguments of a generic class, struct, or variant, from the enclosing context (return type, let-init type, assignment LHS, or the argument slot the call itself fills) when the arguments alone don't pin every slot, from how an untyped immutable local initialized with the call is used later in the body, and — for a generic function referred to as a value — from the function type of the slot it goes into:

```ghul
print_something(1234);                       // T inferred as int
let b = BOX("hello");                        // BOX[string]
let r: RESULT[int, string] = RESULT.OK(42);  // OK's arg pins T = int;
                                             // the LHS pins S = string
takes_int(zero_of(1));                       // zero_of[T](n: int) -> T:
                                             // the slot pins T = int
```

When neither the arguments nor any later use pins a type argument, the construction or call is an error (`cannot infer type here`, or `cannot infer the type of` the local it initializes) — give the type argument explicitly (`BOX[int]()`).

A type parameter written with a trailing `..` is an **argument pack**. `[T..]` in the type parameter list says that where `T` appears in the signature it may, if it is marked with `..` there, be implicitly wrapped and unwrapped, so that the calling code does not have to wrap or unwrap it by hand. It still can: a caller is free to write the tuple out, and a single argument is the value itself rather than a one-element tuple. Writing `T..` within the signature then says that the wrap or unwrap is wanted for that specific argument, should it be needed at the call site.

So the two markers do different jobs. The one on the type parameter is the permission, and nothing is spread because of it alone; the one on a formal is the request. A formal over a pack that is left unmarked takes the pack as the tuple it is.

The pack stands for the arguments of a call, held as a positional tuple. The `..` on the type parameter is that parameter's bound — it says what `T` ranges over — so a type bound cannot be written alongside it.

A formal argument then writes `..` on its own type to say which of the pack's readings it wants. `f: T.. -> U` takes the arguments spread out, as a function of as many parameters as the call supplies; `v: T..` takes them as the call's own remaining arguments; a plain `T` is the tuple. So a function taking a function and the values to call it with declares one of each, and callers write the call out rather than assembling the tuple by hand:

```ghul
apply[T.., U](f: T.. -> U, v: T..) -> U => f(v);

concat(a: string, b: string) -> string => "{a}{b}";

apply((a, b) => "{a}{b}", "x", "y");     // T is (string, string)
apply(concat, "x", "y");                 // the same, by name
apply(concat, ("x", "y"));               // the tuple, written out
apply(double, 123);                      // T is int, as for any parameter
```

A spread formal has to be the last one, since it leaves nothing for the arguments after it. One argument is the value itself rather than a one-element tuple, which is what makes `apply(double, 123)` read the way it does; two or more are the tuple they are spread into. Writing the tuple out goes into the same formal, so both spellings are available and the written-out one is what a caller reaches for when it already holds the tuple.

The pack is the last parameter of the function the formal takes, and that function can take parameters of its own before it. `f: (A, T..) -> A` is the shape a fold's callback has: the running value comes first and is passed as it is, and the rest of the parameters are the pack's elements.

```ghul
fold[A, T..](source: Collections.Iterable[T], seed: A, f: (A, T..) -> A) -> A is
    let running mut = seed

    for element in source do
        running = f(running, element)
    od

    return running
si

let pairs = [(1, 2), (3, 4)]

fold(pairs, 0, (total, a, b) => total + a * b)      // 14
fold(pairs, 0, (total, pair) => total + pair.`0)    // the tuple, written out
```

Only the last parameter can be the pack, and a parameter list holds one pack: `(A.., B) -> C` and `(T.., T..) -> int` are both errors.

The pack binds to whatever the call supplies, and the function written at its own formal is one of the things that supplies it — its parameters are the tuple. So a call that passes nothing but the function still infers, as long as the function says what its parameters are:

```ghul
n_ary[A.., B](f: A.. -> B) -> (A -> B) => f;

add(a: int, b: int) -> int => a + b;

n_ary(add);                        // A is (int, int)
n_ary((a: int, b: int) => a + b);  // the same, written out
n_ary((a, b) => a + b);            // error - nothing says what a and b are
```

Nothing about the parameter itself changes: `T` binds to whatever the call supplies, `f(v)` passes one value, and a consumer in another language sees a method taking a tuple. What the marker on `f` licenses is a **function of two or more parameters written where that formal expects one**. A function literal there is read as destructuring the tuple, and a function named there is wrapped so that it is. A one-parameter function needs no adaptation and is passed as it stands.

`[T..]` is accepted on a class, struct, trait and union type parameter as well as a function or method one, and each formal opts in for itself — so a type declaring `EVENT[T..]` marks its handler formal and its value formal for the readings each wants:

```ghul
class EVENT[T..] is
    subscribe(handler: T.. -> void) is ... si
    raise(v: T..) is ... si
si

let e = EVENT[(int, string)]();

e.subscribe((n, s) => write_line("{n} {s}"));
e.raise(7, "seven");
```

Inside the type, a formal holding the handler has its tuple-in type, `T -> void`. That type is what the handler is stored as, since a type argument can't carry the marker:

```ghul
class EVENT[T..] is
    _handlers: Collections.LIST[T -> void]

    init() is _handlers = Collections.LIST[T -> void](); si

    subscribe(handler: T.. -> void) is _handlers.add(handler); si

    raise(v: T..) is
        for handler in _handlers do
            handler(v);
        od
    si
si
```

The marker can sit on the parameter of any function type along the formal's return spine, not only the outermost. `f: X -> T.. -> U` asks for a function the caller's own lambda returns, which is how a higher-order function takes an N-ary one:

```ghul
run[T.., U](make: (int) -> T.. -> U, v: T) -> U => make(10)(v);

run(n => (a, b) => a + b + n, (1, 2));   // 13
```

A literal written there can spell its types out. Its return is written as the N-ary function type the marker licenses, and the literal is presented in the tuple-in shape the formal takes, exactly as the inferred one is - at whatever depth the marker sits. The tuple-in shape itself is not a type an N-ary literal can be returned as, there or anywhere else:

```ghul
run((n: int) -> (int, int) -> int => (a: int, b: int) -> int => a + b + n, (1, 2));   // 13

run((n: int) -> ((int, int)) -> int => (a: int, b: int) -> int => a + b + n, (1, 2)); // error
```

The marker reads only as a formal's own type, as the last parameter of a function type on that type's return spine, or as the last parameter of a function type in a declared return type. Written anywhere else — inside a bigger type, reached through a parameter rather than a return, or on a type parameter that no `[T..]` declares — it is an error. The tuple limit is the pack's limit too: past seven arguments there is no tuple to bind to, and the call is reported as it stands. A pack is not `params`: a homogeneous variable-length list is a different thing.

What each formal asks for survives into the assembly, so a pack declared in one assembly reads the same way from another.

A return type marked that way hands the pack back out, which is how a combinator preserves the arity of a function it takes:

```ghul
retry[T.., U](f: T.. -> U, attempts: int) -> T.. -> U =>
    v => ( ... call f(v) with retries ... );
```

Inside `retry`, the declared return type still names the tuple-in shape the body's `v => ...` literal has. The presentation happens at each call that binds the pack to a concrete tuple: `retry(parse, 3)` evaluates once, where the call stands, and its value is the N-ary function `f`'s own arity suggests — `let safe = retry(parse, 3); safe("2a", 10)` calls it as a two-argument function. A call that binds the pack to a single argument needs no presentation and returns the function as it is. The same rule applies one level up: a generic whose own return type carries the marker returns the tuple-in value its declaration names, and the call of *that* function does the presenting.


A generic function or method named with no argument list is a *value*, the same way a non-generic name in value position is. Written with its type arguments it is the value at that instantiation; written bare, the type arguments are inferred from the function type of the slot it goes into — from the parameter positions, and from the return slot for a variable that appears only there. It converts wherever a function type or a named delegate is expected, and where the name is overloaded the expected type picks the member:

```ghul
identity[T](x: T) -> T => x;

zero_of[T](ignored: int) -> T => _[T];

let f = identity[int];                    // (int) -> int, explicit
let g: (string) -> string = identity;     // inferred from the slot
let h: (int) -> string = zero_of;         // T pinned by the return slot
```

With no slot type in scope there is nothing to infer from, and the bare name is an error (`cannot infer the type arguments`) — give the type arguments explicitly.

A name can be declared at more than one generic arity in the same namespace — `class BOX` and `class BOX[T]` are two types, as `Tasks.TASK` and `Tasks.TASK[T]` are. Written with type arguments the name picks the sibling of that arity, and written bare it picks the one taking none.

That leaves the generic sibling with no bare spelling, which matters in a `typeof`: an *open* generic — the type before any type argument is supplied — is a thing only reflection can hold, and a bare `BOX` in a `typeof` names the sibling taking no type arguments. `BOX[_]` names the open generic, with one `_` for each type argument it takes:

```ghul
let plain = typeof BOX;         // the sibling taking no type arguments
let open = typeof BOX[_];       // BOX[T], with no argument supplied
let closed = typeof BOX[int];   // BOX[int]

typeof PAIR[_, _];              // a two-argument open generic
```

`open` is the type `closed.get_generic_type_definition()` returns. Because nothing but reflection can hold such a type, `FOO[_]` is accepted only as the whole operand of a `typeof` — not as a declared type, not nested inside another type argument, and not with some arguments supplied and others left as `_`. Where a name has no sibling taking no type arguments, a bare name in a `typeof` yields the open generic too, so `typeof List` is ``IReadOnlyList`1[T]``; `X[_]` is the spelling that means it whatever siblings exist, and the only one accepted anywhere a sibling could be meant instead.

The main use for it is an attribute that names a generic type, where the type it names shares its name with a sibling — a task-like whose builder is generic, for instance (see [asynchronous code](#asynchronous-code)):

```ghul
@System.Runtime.CompilerServices.AsyncMethodBuilder(typeof(COROUTINE_BUILDER[_]))
class COROUTINE[T] is ... si
```

Everywhere else a type is required, a generic named with none of its type arguments is an error saying how many it takes: what the name stands for is the open generic, and an assembly naming one is refused by the runtime at load rather than at compile time. That covers a declared type, a parameter, a cast target, an `isa` test and a type argument alike. Two positions are not affected, because each takes its arguments from somewhere else: a union's variant, whose arguments come from the union and so from the value the variant is tested against or assigned to (`isa Option.NONE(o)` over an `Option[int]`), and a call whose type arguments are inferred (`LIST()`).

## type inference

See <https://ghul.dev/type-inference.html>.

ghūl infers types pervasively, but inference is **function-local**: a namespace-scope function's signature — its parameter and return types — is always written out, and inference works only within the body. Within a body, types are inferred for local variables, loop variables, destructured variables, the parameters and return types of function literals and of nested named functions, and generic type arguments on calls.

Inference also works from later use: a variable with no immediate clue takes its type from how it is used further down the same body — including from operations the body performs on it, and from its own recursive calls if it is a function. The compiler narrows local variables, fields and store-free properties (see Type narrowing above for how long each kind of fact lasts), and a `let` variable's inferred type does not escape the function it is declared in.

## .NET interop

See <https://ghul.dev/dotnet-integration.html>.

ghūl compiles to .NET IL and can consume most types in any .NET assembly. .NET names are mapped to ghūl conventions: method, property, and field names become `snake_case`; enum names and members become `MACRO_CASE`; class, struct, and trait names are left as they are, with .NET's generic arity suffix removed — `KeyValuePair<K, V>` is `Collections.KeyValuePair[K, V]`. The namespace `System.Collections.Generic` maps to `Collections` and `System.IO` to `IO`, and some common types are remapped — `System.Console` is `IO.Std`, `IReadOnlyList<T>` is `Collections.List[T]`, `IReadOnlySet<T>` is `Collections.Set[T]`, `IEnumerable<T>` is `Collections.Iterable[T]`, and `IComparable<T>`/`IEquatable<T>` are `Ghul.Comparable[T]`/`Ghul.Equatable[T]`. The dotnet-integration page has the full mapping table.

Those two interfaces are declared in terms of the operators rather than named methods: `Ghul.Equatable[T]` requires `=~` and `Ghul.Comparable[T]` requires `<>`, so a type implements them by defining the operator. Every .NET type implementing them gains the operator in turn, which is why `=~` compares a `System.DateTime` and the relational operators order a `System.Version`.

```ghul
class BOX: Ghul.Comparable[BOX], Ghul.Equatable[BOX] is
    _v: int;

    init(v: int) is _v = v; si

    <>(other: BOX) -> int => _v - other._v;
    =~(other: BOX) -> bool => _v == other._v;
si
```

The parameter is written non-optional: presence is settled where the operator is used, so the body is only handed present values. On a reference type the optional spelling is accepted too, for a body that wants to defend against a null arriving from a caller in another language without the compiler reporting the test as redundant. A value type has no such choice, since its `T?` is a different type rather than the same one annotated.

`<>` answers how its operands are ordered: negative when the left is the lesser, zero when neither is, positive otherwise. The relational operators are written in terms of it — `a < b` is `a <> b` reduced against zero — so defining `<>` is what gives a type all four.

Defining `=~` also settles how .NET itself compares the type, provided `get_hash_code` is defined alongside it. For a type declaring both, the compiler synthesises a matching `Equals(object)`, so the operator is what runs when the runtime reaches for equality — using the value as a dictionary key, or searching for it in a collection. Without it a class compares by reference there and a struct field-by-field, either way ignoring the operator. Writing an `equals(other: object?)` member explicitly replaces the synthesised one.

Both halves are needed because .NET requires values that compare equal to hash equal, and a hash-based collection consults the hash first. A type that defines neither is consistent as it stands, comparing and hashing by identity, so defining only `=~` is reported as `equality-without-hash` and leaves the type alone rather than breaking that pair. The hash is not synthesised: an operator is free to ignore some of the fields it reads, and a memberwise hash would then disagree with it.

`a =~ b` on a bare, unconstrained type parameter compiles by going through `EqualityComparer[T].Default.Equals`, the same route .NET collections use for a generic instantiation. That reaches the `Equals(object)` bridge above, so the comparison follows whatever the actual type argument does: a type declaring `=~` and `get_hash_code` answers through its own operator, a class with neither declared nor synthesised compares by reference, and a struct, enum, or scalar gets the runtime's ordinary value equality for that type. A bound that itself declares `=~` (`[T: Named]` where `Named` declares the operator) resolves the bound's operator directly and never reaches the comparer.

A tuple takes the same route. `EqualityComparer[T].Default` for a `ValueTuple` is the tuple's own element-wise equality, so each element is compared by the default comparer for *its* type — and so, by the same chain, through a user-written `=~` where the element type declares one.

A member `=~` or `<>` must be `pure` — declared or provably store-free — a compile error otherwise. Both operators are trusted on an operand whose type isn't known until later — a lambda parameter, for instance — and `=~` is trusted again through the `EqualityComparer[T].Default` route above. Nothing at either of those call sites can check what the implementation actually does, so an implementation that could store would make that trust unsound rather than merely unproven. Most bodies — field and property comparisons, delegating to another type's `=~`/`<>` — are provably store-free without any annotation; add `pure` when the body itself is more than the analysis can trace (a loop, a call the analysis doesn't otherwise bound). Overriding a pure `=~`/`<>` requires the override to be pure too, the same rule that governs overriding any other [pure function](#type-narrowing).

A type implementing `Collections.Iterator[T]` that declares no `reset` gets a synthesised one that throws `System.NotSupportedException`, which is what `IEnumerator.Reset` is documented to do and what .NET's own generated iterators answer with; a `reset` the type declares is left alone. `dispose` is not supplied, since what a type holds and must release is its author's to say.

An identifier that collides with a ghūl keyword is escaped with a backtick — `` `class `` is the identifier `class`.

An operator is an ordinary member and can be called as one, which is occasionally clearer than the operator spelling and is how a completion list offers it. The dot needs separating from the operator's name, because a run of operator characters is scanned as a single token and `.` is one of them — so `a.=~(b)` is read as an operator named `.=~` rather than as a member access. A space does it, and so does the backtick escape:

```ghul
a. =~(b)
a.`=~(b)
```

Both are the same call, and both are a plain method call rather than another spelling of the operator. Where the two differ, they differ quietly. The null handling around `a =~ b` is written around the *operator*, so the member call receives an absent operand instead of being answered before it is reached. And an operator that lowers to an IL instruction has no .NET method behind it: on the scalar types the arithmetic operators are instructions, declared as static members of the type, so `a. +(b)` on an `int` finds no overload taking one operand, and `int.`+(a, b)` is the call — while `=~` and `<>` on those types, and on `string`, do reach the .NET method the name maps to, which is not the same thing the operator does. Member syntax is fine to use on a type whose operators you wrote; it is not a general substitute for writing the operator. Naming one of those instruction-backed operators as a *value* rather than calling it - `int.`+`` passed where a function is expected - is rejected, since there is no method to take the address of; an operator you declared yourself is an ordinary static or global function and is named as a value like any other. An instance member named through its type, `BOX.plus` or `int.`<>``, is rejected too: a member reached through a receiver needs one.

A static property or field takes `snake_case` however constant-like it reads, since only enum members become `MACRO_CASE` — `CancellationToken.None` is `System.Threading.CancellationToken.none`.

A type's own **operators** are reached by writing the operator. A public static operator method a .NET type declares — `op_Addition` and the rest, on `bigint`, `System.DateTime`, `System.TimeSpan` and any other type that has them — is a candidate wherever a value of that type is either operand, and both operand types contribute, so `step * 2.0D` and `2.0D * step` find the same operator on `TimeSpan`. The same goes for a static operator declared on a ghūl class or struct: `+(a: VECTOR, b: VECTOR) -> VECTOR static` applies to `v + w` from anywhere `VECTOR` is visible, not only inside its own body. An operator none of whose operands is the declaring type is reached by importing it under its own name — ``use Lib.VECTOR_OPS.`*;`` — the same route the generic-math interface operators take. The arithmetic, bitwise, shift and unary operators are reached this way; comparison and equality come from `<>` and `=~` as elsewhere, so a reflected `op_LessThan` or `op_Equality` is not. The scalar types are the exception: their operators are the language's own, so `decimal`'s reflected `op_Addition` is not a second candidate beside the built-in `+`.

An **indexer** is the one member reached only through its own syntax. .NET does not fix its name — the property carries whatever its declaring language chose, and the type nominates the real one, so `System.String` and `System.Text.StringBuilder` both call theirs `Chars` — but the name never has to be written: `[` and `]` find it whatever it is.

```ghul
let initial = name[0];
```

The accessors behind it are not members in their own right, so naming one directly is an error rather than another way in.

A **nested** .NET type is not addressed through its enclosing type. It lives in the enclosing type's namespace under a name joining the segments with `_`, so `System.Environment.SpecialFolder` is written:

```ghul
let home = System.Environment.get_folder_path(System.Environment_SpecialFolder.USER_PROFILE);
```

A .NET **delegate** type is a slot a function literal can be written into directly, and the literal is compiled as that delegate:

```ghul
let xs = Collections.LIST[int]();

xs.sort((a: int, b: int) -> int => b - a);          // System.Comparison[int]

let is_even: System.Predicate[int] = n => n % 2 == 0;
```

Parameter types are taken from the delegate the slot expects, so they need no annotation. `Func` and `Action` are different: they are how ghūl's own function types are represented, so a `(int) -> bool` value is already a `System.Func<int, bool>` at the IL level and passes into such a slot with no conversion in either direction. Write the ghūl spelling — `(int) -> bool` — rather than naming `Func` directly.

Any other delegate type is a distinct .NET type rather than another spelling of `(int) -> bool`, so an existing function **value** held in a variable is not accepted where one is expected:

```ghul
let compare = (a: int, b: int) -> int => b - a;     // a function value
xs.sort(compare);                                   // error: not assignable to System.Comparison[int]
```

Declare the variable at the delegate type instead, and it is that delegate from the start:

```ghul
let compare: System.Comparison[int] = (a: int, b: int) -> int => b - a;
xs.sort(compare);
```

Or construct the delegate explicitly from the existing value, calling the delegate type as if it were a constructor:

```ghul
let compare = (a: int, b: int) -> int => b - a;     // a function value
xs.sort(System.Comparison[int](compare));
```

A global function, or a static or instance method, referred to **by name** is different from a stored function value: the name converts directly wherever a function type *or* a named delegate is expected, since the compiler reaches for the method itself rather than needing an existing value to wrap.

```ghul
compare_descending(a: int, b: int) -> int => b - a;

apply(f: (int, int) -> int) -> int => f(3, 5);

apply(compare_descending);                          // ok - no lambda wrapper needed

xs.sort(compare_descending);                        // ok - System.Comparison[int]

let f = compare_descending;                         // f: (int, int) -> int
```

An overloaded name is resolved against whichever function or delegate type the reference needs to match, the same way a call's argument types pick an overload; with no such type in scope, an ambiguous name is left as an error rather than guessed at.

A .NET **user-defined conversion operator** (`op_Implicit` / `op_Explicit`) declared on either the source or the target type is reachable through `cast`, alongside the subtype and scalar conversions `cast` already performs:

```ghul
let h = cast System.Half(1.5);      // System.Half declares `explicit operator Half(double)`
let f = cast single(h);             // and `implicit operator float(Half)`
```

`cast T(v)` calls the operator and lets it throw on failure, same as calling it from C# would. `cast T?(v)` never throws: `InvalidCastException` or `OverflowException` from the operator becomes an absent value, and any other exception still propagates.

An auto-property's **backing field** is named `$` followed by the property name, and reflection sees it alongside the property. A reflection-based serializer told to include fields will therefore emit every property twice — with `System.Text.Json`, leave `include_fields` alone unless the type really does have fields to serialize.

Because ghūl has no default argument values, a .NET **optional parameter** has to be supplied explicitly — there is no overload with it omitted. `File.ReadAllTextAsync(path)` is written:

```ghul
let text = await IO.File.read_all_text_async(path, System.Threading.CancellationToken.none);
```

`@IL.name("Name")` sets the name a function, method or property has in the compiled assembly, for a .NET library that finds members by name - Entity Framework Core, for example, looks for an `Id` property and a `DbSet` property named after the table. On a property it also names the accessors `get_Name` and `set_Name`; `@IL.name.read("...")` or `@IL.name.assign("...")` names one accessor on its own. The argument is a single string literal and cannot contain a quote. A type keeps its ghūl name in the compiled assembly, and `@IL.name` written on a class, struct, trait, union or enum is an error. The ghūl name is unchanged, so ghūl code still calls the member by the name it declares:

```ghul
class PRODUCT is
    @IL.name("Id")
    id: int public

    init() is si
si
```

A pragma whose name doesn't match a compiler built-in is taken to name a .NET **attribute**, and emits the attribute on whatever it's written against: a class, trait, struct, union, variant, or enum; a function or method; or a single parameter in a function or method's parameter list, including a lambda literal's. The `Foo` short form resolves to `FooAttribute` when no plain `Foo` exists, in a `use` clause as well as in the pragma — so `use System.Obsolete` brings `System.ObsoleteAttribute` into scope, and `use Marker = System.Obsolete` brings it in as `Marker`. Arguments are positional, named (`name = value`), array-valued, or `typeof`:

```ghul
@System.Obsolete("use PRODUCT instead")
class LEGACY_PRODUCT is
    init() is si
si

get_product(
    @Microsoft.AspNetCore.Mvc.FromServices() store: ProductStore,
    @Microsoft.AspNetCore.Mvc.FromRoute() index: int
) -> Tasks.TASK[IResult] is
    ...
si

app.map_get(
    "/products/{index}",
    (@Microsoft.AspNetCore.Mvc.FromRoute() index: int, store: ProductStore) -> Tasks.TASK[IResult] is
        ...
    si
);
```

A parameter attribute is recognised only where a formal parameter can appear: a named function or method's parameter list, or a lambda literal's — not on a `let` or a primary-constructor parameter. Written on an element of a parenthesised expression that turns out not to be a lambda (an ordinary value tuple), it's rejected with an error rather than silently ignored.

`System.Obsolete` marks a declaration as deprecated, whether it is written as a pragma in ghūl or carried by a .NET assembly. Every use of the declaration from elsewhere is then reported as `<name> is deprecated: <message>`, or `<name> is deprecated` where the attribute gives no message. The report is a `deprecated` warning, suppressible like any other, or an error when the attribute's second argument is `true`. Using a class's constructor counts as using the class. A use written inside a declaration that is itself deprecated is not reported, so an old member can go on using another. Hover shows the message under the signature, and completion marks the item as deprecated.

```ghul
@System.Obsolete("use scaled instead")
doubled(x: int) -> int => x * 2;

@System.Obsolete("removed", true)
tripled(x: int) -> int => x * 3;
```

`System.Runtime.InteropServices.DllImport` on a static method with no body declares a call into a shared library. The method is emitted as the call itself rather than as a method carrying an attribute, so it needs no body and cannot have one:

```ghul
class LIBC is
    @System.Runtime.InteropServices.DllImport("libc")
    abs(value: int) -> int static;

    @System.Runtime.InteropServices.DllImport("libc", entry_point = "getpid")
    process_id() -> int static;

    init() is si
si
```

The name looked up in the library is the method's own, spelled as written, unless `entry_point` gives another: a native symbol is matched exactly, so none of the case conversion that applies to a .NET name applies here. `char_set`, `set_last_error`, `exact_spelling` and `calling_convention` are carried through as written.

What can cross the boundary is what the machine lays out the same way on both sides: the scalar types, a pointer, a `ref` to a scalar, and a `string` argument, which is marshalled to a null-terminated buffer for the duration of the call. A returned `string` is not accepted, since freeing the buffer the library returned is the library's business rather than the runtime's. Anything else, such as a class, a tuple, an array or a function, is reported at the declaration rather than emitted.
