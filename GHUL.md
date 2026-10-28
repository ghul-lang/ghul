# ghūl language tutorial and reference

ghūl is a statically typed, general-purpose programming language. It targets .NET 10, WebAssembly and native executables. It is a hobby project, and it is expressive enough for general-purpose work: the ghūl compiler is written in ghūl. On .NET, the compiler produces ordinary assemblies and NuGet packages, and ghūl code can use any .NET library. The WebAssembly and native targets use ghūl's own libraries. The [compilation targets](#compilation-targets) section says what each target supports.

ghūl is a conventional language with an unusual syntax. The syntax comes from ALGOL 68 and Pascal. Keywords delimit blocks; there are no braces, and indentation has no meaning. Keywords come in pairs, and the closing keyword is the opening keyword spelled backwards: a class or function body is `is` ... `si`, a conditional is `if` ... `fi`, and a `try` block ends with `yrt`.

This file is a condensed reference in one file. The full documentation is at <https://ghul.dev>, with one page per topic. Setup instructions are at <https://ghul.dev/getting-started.html>. Each section below links to the ghul.dev page for its topic.

## the mistakes most often made

These mistakes cost the most rework. A section below explains each one. The last one is explained in the targets file.

- **.NET members are `snake_case`.** Write `Math.sqrt(x)`, `Math.pi`, `s.length` and `list.count`. `Math.Sqrt`, `Math.PI` and `list.Count` are errors. The compiler converts .NET names, and `System.Math` is `Ghul.Math`.
- **`write_line` must be imported.** Write `use IO.Std.write_line` before the code that calls it. Or start the file with `use default`, which imports `write_line`, the pipes and the collections.
- **Strings have no `+` operator.** Join strings with interpolation: `"{a}{b}"`.
- **`==` on a `string` compares references.** Compare text with `=~`. Use `==` for scalars, enums and references.
- **Numbers do not convert implicitly.** `1.0 + 1` is an error. Write `1.0 + double(1)` or `cast double(n)`. A big integer is a `bigint`, written with the `n` suffix. Do not use `System.Numerics.BigInteger`.
- **There is no `new`.** Construct a value by calling its type: `Box(42)`, `LIST[int]()`.
- **The closing keyword of a block mirrors its opening keyword**: `is` ... `si`, `if` ... `fi`, `do` ... `od`, `case` ... `esac`, `try` ... `yrt`. There are no braces.
- **A bare `let` is immutable.** A local declared `let count mut = 0` can be reassigned.
- **An optional `T?` must be narrowed before it is used as a `T`.** Narrow it with `if x?` or `if let v = x`, or assert that it is present with `x!`.
- **A semicolon at the end of a line is not needed.** A semicolon separates two statements on one line.
- **On WebAssembly and native targets, a .NET API exists only if the core library declares it.** These targets do not support `decimal`. See [what differs on the wasm target](docs/targets.md#what-differs-on-the-wasm-target).

## the rest of the reference

GHUL.md covers the language that ordinary programs use. Seven further files cover the detail that specialised work needs. They are not loaded with this file. Read the file that matches your task.

| file | covers | read it when |
| --- | --- | --- |
| [docs/narrowing.md](docs/narrowing.md) | narrowing in depth: heap facts and crossings, `pure` and `stable`, getters, closure-assigned locals, nested optionals and `Result` coalescing | you need to know why a value is or is not narrowed, or you are changing the compiler's flow analysis |
| [docs/generics.md](docs/generics.md) | argument packs, variance, generic-math operator imports, open generics in `typeof`, `size_of` | you are writing generic library code |
| [docs/async.md](docs/async.md) | the awaiter pattern, task-like return types and their builders, asynchronous function literals | you are writing a coroutine library or a custom task type |
| [docs/sessions.md](docs/sessions.md) | `--submission`, `--cells`, `--session` and `--cell-link`, and the checks each one adds | you are working on the REPL, a notebook kernel or the playground |
| [docs/dotnet.md](docs/dotnet.md) | the core type names, attributes and pragmas (`@intrinsic`, `@trusted_store_free()`, `@finalizer()`), `DllImport`, `StructLayout`, `IL.name`, operators declared by .NET types | you are calling .NET libraries beyond the common cases |
| [docs/targets.md](docs/targets.md) | what each target supports, conditional compilation, what differs on wasm, `@extern` on each target, the llvm options | you are building for WebAssembly or native executables |
| [docs/details.md](docs/details.md) | access policy flags, file-level pragmas, doc comment rules, `cast` target inference, synthesised equality and `@equality()`, `@Flags()` operators, `partial` and `impl` blocks, `@precedence`, `Displayable` | you need a specific rule |

## naming conventions

ghūl keywords are lowercase. Identifiers follow a naming convention, and the compiler checks part of it:

- `snake_case`: variables, functions, methods, properties
- `PascalCase`: namespaces, traits, abstract classes, exception classes, unions, enums
- `UPPER_SNAKE_CASE`: concrete classes, structs, variants, enum members

An exception class is `PascalCase`, whether or not it is abstract. An exception class is `Exception` or any class that derives from it, directly or indirectly. Code names an exception class where it throws the exception and where it catches it. Every exception imported from .NET is already `PascalCase`.

A `static` field or property can be `snake_case` or `UPPER_SNAKE_CASE`, because it reads as a named constant. A property with an expression-bodied getter and no setter (`NAME: string => "x"`) can also be either. A property with a block getter or with a setter must be `snake_case`.

A leading underscore (`_name`) makes a declaration non-public. ghūl has no `public` or `private` keyword for this; the name carries it. A name that starts with an underscore is **private to the assembly that declares it**. Another assembly cannot see it, and a reference to it from another assembly is a compile error.

The compiler warns when a declaration in ghūl source does not follow the convention for its kind. Each rule has its own slug. You can suppress each slug per declaration, per file, or for the whole project:

- `non-snake-case-name`: variables (including `let`, `for` and `catch` locals, and function arguments), functions, methods, properties.
- `non-pascal-case-name`: abstract classes, exception classes, traits, unions, enums.
- `non-upper-snake-case-name`: concrete classes, structs, variants, enum members.

A class with only `static` members and no primary-constructor parameters is a static utility container. Nothing constructs it. Its name can be `PascalCase` or `UPPER_SNAKE_CASE`.

*More detail on this section: [language details](docs/details.md#naming-conventions).*

## namespaces and `use`

See <https://ghul.dev/definitions.html#namespaces>.

A namespace groups definitions. A namespace definition is the keyword `namespace`, a name, and an `is` ... `si` body:

```ghul
namespace MyApp.Utilities is
    class HELPER is
        ...
    si
si
```

Namespaces nest. A dotted name (`namespace Outer.Inner is ... si`) is shorthand for one namespace nested in another. A namespace definition is one *instance* of its namespace. The compiler combines all instances of a namespace across every source file. So a definition in one file's `namespace Example` block is visible, without qualification, in every other `namespace Example` block in the project.

A namespace can cover a whole file. Write `namespace` and the name with no `is` ... `si` body, and everything after it in the file is inside the namespace:

```ghul
namespace MyApp.Utilities

use IO.Std.write_line

class HELPER is
    ...
si

entry() is
    write_line("ready")
si
```

A whole-file namespace must be the first declaration in the file, after any `@@` pragmas. It cannot be nested inside another namespace. An `is` after the name still opens a namespace block, whether it is on the same line or a later one. A `use` written after a whole-file namespace declaration applies to the rest of the file.

A file with no namespace declaration can contain statements at the top level of the file, and so can a file whose namespace is a whole-file namespace. These top-level statements run in source order as the program's entry point, so a short program needs no `entry` function. Top-level statements can be mixed with global definitions. A global definition is visible everywhere in the file, wherever it appears. A file with top-level statements cannot declare a namespace block.

A `use` statement brings names into scope, so code can refer to them without qualification. A `use` of a namespace imports every public symbol in it. A `use` of a single symbol imports that symbol:

```ghul
use IO.Std.write_line;            // a single static method
use IO;                           // every public symbol in the namespace
use Console = IO.Std;             // import under a different name
```

A `use` applies only within the namespace block that contains it. If a namespace is split across several blocks or files, each block needs its own `use` statements.

A qualified `use` names its target inside its qualifier: in `use IO.Std.write_line`, `write_line` is a member of `IO.Std`. The qualifier itself is relative, like any name - inside `namespace A.B.C`, `use B.E` means `A.B.E`. A target that is not a member of its qualifier but resolves through an enclosing namespace is accepted with a `use-outside-qualifier` warning; naming the namespace that declares the symbol silences it.

One namespace needs no `use`: `Ghul.Intrinsics`. It holds the names the language supplies: the built-in types such as `int` and `string`, the function and tuple types, and the operators on them. Every namespace block sees `Ghul.Intrinsics` as if the block started with `use Ghul.Intrinsics;`. The runtime declares everything else in `Ghul` and its nested namespaces, and code imports these like any other library: `use Ghul;` imports the functional combinators such as `apply`, and `use Ghul.Pipes;` imports the pipe combinators. Your own definition can have the same name as one of these, such as your own `apply`. A file that does not import that name sees only your definition. A file that also imports the name sees both: your function and the imported function form one overload group, and the compiler resolves each call against both.

A `use` with a type expression on the right defines a *type alias*. A type alias names a type; it does not import a symbol:

```ghul
use IndexedString = (index: int, value: string);
use Handler = (int) -> void;
use Names = string[];
use MaybeName = string?;
use Numbers = Collections.LIST[int];
```

`use default` imports a fixed set of names that most files want. By default the set is `IO.Std.write_line`, `Ghul.Pipes`, `Collections` and `Ghul.Numerics`. A name in the default set that the runtime doesn't define is skipped. In every other way `use default` is an ordinary `use`: it applies to the namespace block that contains it. Unless the project asks for an implicit import with `--implicit-default-use`, a file that does not write `use default` gets none of these names.

```ghul
use default

entry() is
    let totals = LIST[int]([1, 2, 3, 4])

    write_line("{totals |> filter(x => x % 2 == 0) |> reduce(0, (a, b) => a + b)}")
si
```

*More detail on this section: [language details](docs/details.md#namespaces-and-use), [sessions and submissions](docs/sessions.md#namespaces-and-use).*

## comments

`//` starts a comment that ends at the end of the line. `/*` ... `*/` encloses a comment that can span several lines. The compiler treats either kind of comment as whitespace.

A **doc comment** is a line comment that starts with exactly three slashes, `///`, with nothing before it on its line. A block of doc comments directly above a declaration documents that declaration. An editor shows the text in hover and completion wherever code uses the declaration, including code in another assembly:

```ghul
/// Joins `parts` with `separator` between each pair.
///
/// - parts: the strings to join, in order
/// - separator: placed between adjacent parts, not at either end
join(parts: string[], separator: string) -> string => string.join(separator, parts)
```

*More detail on this section: [language details](docs/details.md#comments).*

## statement terminators

Code with one statement on each line needs a `;` only to put two statements on one line.

A `;` separates two statements, or two simple declarations, on one line. A `;` at the end of a line is not needed. Where the grammar accepts a `;` and the next token starts a new line, the compiler infers the boundary. The end of the file also ends a line, so the last construct in a file needs no terminator. A construct that is incomplete at the end of a line continues on the next line. Examples are `a +`, and an argument list that has no `)` yet.

These rules decide where a line break ends a statement. The most common come first:

- A line that starts with `.`, `?`, `|>` or `ref` continues the construct on the line above. So member chains, optional chains and thread-first chains can wrap.
- A line that starts with `(`, `[`, `` `[ `` or an operator starts a new statement. Examples are a destructure assignment `(a, b) = …`, an array literal, and a prefix `!`. Such a line is never joined to the line above as a call, an index or an infix operand. To wrap an operator expression, put the operator at the end of the line: write `a +` and then the newline. Do not write the newline and then `+ a`.
- Two string literals on adjacent lines join into one literal. If one statement ends with a string literal and the next statement starts with one, write a `;` between them. This is the one boundary that needs a written `;` (see [types and literals](#types-and-literals)).
- A bare `return` at the end of a line is a void return when the next line starts with a closing keyword (`fi`, `si`, `od`, …). Otherwise the `return` takes the next line's expression as its value. A statement after a `return` in the same block is unreachable, so the two readings do not conflict.
- In a parenthesised group, a top-level `,` makes the group a tuple, and an inferred boundary makes the group a block, exactly as a written `;` does. A compound statement at the end of a line is complete. The boundary falls after it, whatever starts the next line, and an operator at the start of the next line begins a new statement. To continue the expression, put the operator on the same line: `(if c then 2 else 5 fi - 1)` is 1 when `c` is true. If `- 1` is on its own line instead, it is a second statement and is the group's value.
- A postfix marker must be on the same line as the thing it marks. A modifier at the start of a line (`pure`, `static`, …) belongs to the next definition, not to the header above it. A `rec` at the start of a line is the recursive self-reference call, not a rec-lambda marker.
- An `else` at the start of the line after a bare `assert` belongs to the assert, as its message clause, when the `else` is indented at least as far as the `assert`. Otherwise the `else` belongs to the enclosing `if` or `case` arm. Only indentation decides this. When the assert is on the same line as the `if` (`if c then assert x` / `else y fi`), an `else` at the same indentation as the `if` belongs to the assert. A `;` after the assert gives the `else` to the `if`.

*More detail on this section: [language details](docs/details.md#statement-terminators).*

## variables

See <https://ghul.dev/definitions.html#variables>.

`let` declares a local variable. The declaration has an inferred or explicit type and an initializer:

```ghul
let i = 1234;          // type inferred as int
let k: int = 5678;     // explicit type
```

A bare `let` declares an immutable local. It requires an initializer, its value is fixed, and assigning to it is an error. A local declared with a trailing `mut` can be reassigned. A `mut` local can omit its initializer. Such a deferred-init local starts with the default value of its type: zero, `false` or `null`.

```ghul
let counter mut = 0;     // initialised, will be reassigned
counter = counter + 1;

let result: int mut;     // deferred — default-initialised to 0
result = compute();
```

Definite-assignment analysis covers a deferred-init local. Reading it on a path that has not assigned it gives a `definite-assignment` warning. Do not rely on the default value.

`null` does not decide a local's type. An initializer of `null`, or an assignment of `null`, says that the local can be absent, and says nothing about the type of the value when it is present. The compiler takes the type from the other values assigned to the local, or from the fallback of a later `??`. The local's type is the optional of that type:

```ghul
let root mut = null;       // NODE?, from the assignment below
root = NODE("first");

let unknown = null;        // bool?, from the fallback
if unknown ?? false then
    ...
fi
```

When the initializer, the assignments and the uses of a local give it no type, the compiler reports `cannot infer type here` at the declaration. The local then needs a type annotation.

A `mut` local with an initializer and no written type gets the join of the types of its initializer and of every value assigned to it later. So if the initializer is one union variant or one subclass, the local can still be assigned a sibling variant or subclass:

```ghul
let tree mut = Tree.EMPTY;     // Tree, from the assignment below
tree = Tree.NODE(tree, 1, Tree.EMPTY);

let pet mut = CAT();           // Animal
pet = DOG();
```

The compiler uses the join only when it is a type that the author wrote. In these cases the local keeps the type of its initializer, and the compiler reports the assignment:

- the join is `object` or `System.ValueType`
- the join is a trait, and neither the initializer nor any assigned value has that trait as its type
- the initializer or an assigned value is a value type

So `let i mut = 0; i = 1L` is an error, and so is assigning a value of an unrelated class. A written type (`let pet: Animal mut = CAT()`) always fixes this.

In a declaration or pattern position, `_` is the discard placeholder. These positions are `let _ = expr`, a destructure leaf `(_, b)`, a `for _`, an `if let _`, a lambda discard parameter `_ => ...` or `(_, y) => ...`, and a typed discard `(_: T)`. The discard placeholder is different from the default-value expression `_` (see [language details](docs/details.md#variables)). The two appear in different syntactic positions, so they never conflict. `_[T]` is not valid as a lambda parameter, because a lambda parameter takes its type from `_: T`. Writing `_[T]` where a lambda parameter is expected is a compile error.

A single `let` can declare several variables, with inferred and explicit types mixed:

```ghul
let first = 1, second: int = 0, third = "three";
```

The discard placeholder `_` stands in for a variable name, and the value that would go into the variable is discarded. `let` declarations, tuple destructuring, lambda parameters and `for` loop variables accept `_`.

A variable is block-scoped: it is visible from its declaration to the end of the innermost enclosing block. `let` is only valid inside a function, method or property body.

A variable declared at namespace scope is a **global variable**. A global variable is a name and a type, without `let`. It cannot have an initializer:

```ghul
counter: int;            // a global variable
```

*More detail on this section: [language details](docs/details.md#variables).*

## types and literals

See <https://ghul.dev/language-basics.html>.

ghūl gives the .NET primitive types lowercase names:

- integers: `byte`, `ubyte`, `short`, `ushort`, `int`, `uint`, `long`, `ulong`, `word`, `uword`
- floating point: `single`, `double` and `decimal`
- `bigint`, an integer with no fixed width
- `bool`, `char`, `void`

`string` and `object` are reference types from the .NET base class library.

`byte` and `ubyte` are the opposite way round from .NET. `byte` is `System.SByte`, which is signed. `ubyte` is `System.Byte`, which is unsigned.

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

`_` can group digits. An integer literal can have a radix prefix (`0x`) and a type suffix. The suffix has two optional parts, and both are case-insensitive. The first part selects the sign: `s` for signed or `u` for unsigned. The second part selects the size: `b` byte, `c` char, `s` short, `i` int, `l` long, `w` word. So `123b` is a `byte`, `0ub` is a `ubyte`, `4567s` is a `short`, `7890us` is a `ushort`, `222i` is an `int`, `0ul` is a `ulong` and `123w` is a `word`. The suffix `n` makes a `bigint`: `123n`. A numeric character literal (`65c`) cannot be unsigned. A `bigint` literal (`123un`) cannot be unsigned either, because .NET has no unsigned version of `System.Numerics.BigInteger`.

The compiler reads the digits first, for as long as they are digits of the literal's radix. So a letter that is a digit in the literal's radix is read as a digit. In hexadecimal this applies to `b` and `c`, which are both size selectors and hex digits. `0x20AC` is the `int` 8364 and `0xAB` is the `int` 171; neither has a suffix. To attach a suffix that would be read as a digit, put a backtick before it. The backtick marks the boundary and is not part of the value:

```ghul
let euro = 0x20AC`c;       // char, 8364
let byte_max = 0xFF`ub;    // ubyte, 255
let wide = 0x20ACl;        // long — `l` is not a hex digit, so no backtick
```

The backtick has the same meaning here as elsewhere: read what follows as itself, not with its default meaning. A decimal literal never needs it, because no size selector is a decimal digit.

`bigint` is a built-in name for `System.Numerics.BigInteger`, in the same way that `decimal` is a name for `System.Decimal`. `bigint` is the only name for it. It is a name, not a built-in type: its arithmetic operators and its ordering come from its own static operators and its `IComparable`. The language supplies none of them. So a `bigint` has no width to overflow, and no `bigint` literal is out of range.

```ghul
let factorial mut = 1n;

for i in 1::30 do
    factorial = factorial * bigint(i);
od

write_line("{factorial}");     // 265252859812191058636308480000000
```

Mixed operands are an error, exactly as `1.0D + 1` is. If `total` is a `bigint`, `total * 2` is an error; write `total * 2n`. `==` on a `bigint` is an error, as it is on every other struct. Compare `bigint` values with `=~`.

A fractional literal is a `double` unless it has a suffix: `s` for single, `d` for double, `m` for decimal, in either case. The `m` suffix also works on a literal with only digits, to write an integral decimal (`100m`). Exponent notation is valid: `1.5e3`, `1.5E-3`.

ghūl does not convert between scalar types implicitly. An arithmetic expression with operands of different types is a compile-time error, and needs a `cast`. Upcasting is implicit: a value can be assigned to a variable of any ancestor type. So a `string` can be assigned to an `object` with no cast.

```ghul
let a = 1.0 + 1.0;               // ok, both double
let b = 1.0 + cast double(1);    // ok, explicit cast
let o: object = "hello";         // ok, string is an object
```

Each scalar type is also a constructor that takes any other scalar. The constructor converts exactly as a cast to that type does. `double(n)` is `cast double(n)`. `int(x)` truncates, as `cast int(x)` does. A value out of range wraps, as it does with a cast. `_(n)` converts to the scalar type that the context expects. The argument must be a scalar: `int("42")` does not parse a string. Convert a value held as `object` or as a type parameter with `cast`, which unboxes it.

```ghul
let n = 7;
let half = double(n) / 2.0;      // 3.5
let code = int('A');             // 65
let total: long = _(n);          // 7
```

A cast can omit the target type when the surrounding expression decides it. `cast(v)` converts `v` to the type that its position requires. These positions are a typed `let` initializer, an assignment, a `return` or `=>` body, an argument, the other parameter of an operator, an index, and the callee of a call:

```ghul
let total = cast(count) + average;   // count converts to double
let d: double = cast(i);             // to double
takes_a_double(cast(i));             // to double
values[cast(index)];                 // to whatever the indexer takes
```

A **string literal** can interpolate expressions. `{` starts an expression and `}` ends it. The expression's value is converted to a string at that point in the literal. `string` has no `+` operator, so interpolation is the way to join strings:

```ghul
let greeting = "hello {name}, you are {age} years old";
let combined = "{prefix}{suffix}";                  // concatenation
```

An interpolated expression can have an alignment and a format specifier, as in .NET: `{expr, alignment : format}`.

A format applies to a number, and to a value whose type implements `System.IFormattable`. The value is written with its `to_string(format, format_provider)`, with no provider. A format on any other value is ignored, as on .NET. To make a type of your own accept a format, implement `System.IFormattable`.

```ghul
let padded = "[{value,12:F3}]";     // [    1500.000]
```

The static type of an interpolated value decides how it is written:

- A string, a number, an enum, and any type that declares its own `to_string` are written with that `to_string`. So is any value with an alignment.
- A `bool` is written `true` or `false`, the ghūl spelling.
- An optional is written as the value it holds, by these same rules, or as `null` when it holds no value.
- Every other value is written by the runtime's `$`. This covers an array, a list, a tuple, a struct or class that declares no `to_string`, a value held as `object`, a trait and a type parameter. `$` writes a sequence as its elements in brackets, a tuple as its elements in parentheses, and a record as its type and members. Without `$`, these values would be written as their .NET type name.

```ghul
struct POINT(x: int public, y: int public);

let xs = [1, 2, 3];
let found: string? = null;

"{xs} {(1, "one")} {POINT(3, 4)} {true} {found}"
                                     // [1, 2, 3] (1, one) POINT(x = 3, y = 4) true null
```

Adjacent string literals join into one literal, so a long string can be split across lines. Plain and interpolated literals can be mixed. A comment counts as whitespace, so a literal followed by a comment still joins the next literal. Only a `;` separates two adjacent literals. This `;` is the one statement terminator that has an effect: when one statement ends with a string literal and the next statement starts with one, the `;` keeps the two literals apart. The `redundant-semicolon` warning never reports this `;`:

```ghul
let band = "top";
"{band} band"        // a new statement — without the `;` the two
                     // literals chain, and band is not defined yet
```

The text inside the braces is an *expression*. So a string literal inside the braces is written normally: `"{format("hello")}"` needs no escapes for its inner quotes. To write a literal brace, double it: `"{{"` and `"}}"`. The escapes are `\t`, `\n`, `\r`, `\\`, and `\u` followed by exactly four hex digits for any character code. So the euro sign is `"\u20AC"` and the escape character is `"\u001B"`. Four hex digits are one UTF-16 code unit, which is one `char`. Write a code point above `U+FFFF` as its surrogate pair: `"\uD83D\uDE00"` is one grinning face, and is two `char` values. The `\u` escape always takes exactly four digits, so it never takes the text after it: `"\u0041cat"` is `Acat`. Any other character after a `\` is that character, so `\"` is a quote.

An **array** type is written `E[]`. An array has a fixed size and is read-only: it has no assigning indexer. An array's length is its `count`. An array literal is a comma-separated list in square brackets. Its element type is the most specific type that every element is compatible with, or `object` if there is no closer common ancestor:

```ghul
let primes = [2, 3, 5, 7, 11];          // int[]
let mixed = ["frog", 1234, 12.5];       // object[]
let p = primes[2];                      // indexing, 0-based
```

The empty array literal `[]` is valid wherever the context gives the element type. These contexts are an explicitly typed `let`, a `return`, the parameter type of a call argument, a sibling element in an enclosing array literal, and the other arms of an `if` or `case` expression that the `[]` is an arm of. An untyped immutable local initialized with `[]` takes its element type from its later uses in the same body. Examples are passing the local where an array is expected, and putting it in an array literal that is passed where an array is expected. When no use gives the element type, the element type is `object`.

A non-empty array literal passed as an argument can be built at the type of its parameter. This happens when each element converts to the parameter's element type, but the literal built from its elements alone does not convert to the parameter type. Tuples are the common case, because tuples are value types and value types are invariant. For example, passed to a parameter of type `(name: string, operation: Operation[string]){}`, `[("+", APPEND())]` is built as a sequence of `(name: string, operation: Operation[string])` pairs, with each tuple converted as any tuple value converts. It is not built as a `(string, APPEND)[]`. For a generic parameter, the compiler matches the parameter after the call has bound its type arguments.

A sequence of `E` is anything a `for` loop can iterate. Its type is written `E{}`. `E{}` is `Collections.Iterable[E]`, the .NET `IEnumerable<E>`, in the same way that `E[]` is an array. The two spellings are the same type, so either is valid wherever the other is. Diagnostics, hover and inlays show `E{}`. The braces follow the element type in every type position, and combine with the other suffixes: `int{}?` is an optional sequence, `int[]{}` is a sequence of arrays and `int{}{}` is a sequence of sequences. Put a tuple type or function type in parentheses first, as for `[]`:

```ghul
total(values: int{}) -> int => values |> sum()

let words: string{} = ["alpha", "beta"]
let pairs: (int, string){} = [(1, "one")]
```

An index that is a **range** takes a slice of the source. `..` and `::` count both endpoints from the start, as everywhere else. `..<` and `::<` count the end endpoint back from the end of the source. `..<<` and `::<<` count both endpoints back from the end. The number of `<` characters is the number of endpoints counted back from the end, starting with the end endpoint. `<0` is the length, so `a..<0` runs from `a` to the end:

```ghul
let xs = [10, 20, 30, 40, 50];

xs[1..3];        // 20, 30
xs[1..<1];       // 20, 30, 40   — up to one back from the end
xs[1..<0];       // 20, 30, 40, 50 — to the end
xs[3..<<0];      // 30, 40, 50   — the last three
```

The slice is a `Collections.List[E]` that reads the source. Nothing is copied, so a later change to a mutable source is visible in the slice. Arrays, strings and any type that implements `Collections.List[E]` accept a range index. A range index on a string returns a string, which is a copy of the slice. A range index is read-only: a slice cannot be assigned through. A type can declare its own `[r: System.Range]` indexer, and the compiler uses that indexer first.

The from-the-end operators build a `System.Range`. A `System.Range` has endpoints that only have values relative to a length, so a `System.Range` cannot be iterated. `..` and `::` can be iterated. `for i in 1..<1 do` is an error.

A **tuple** groups two or more values, which can have different types. A tuple with one element is an error. A tuple has at most 7 elements. Tuple types and tuple literals both use parentheses. Elements can have names. An unnamed element has the name of a backtick and its index. Tuples are immutable, can nest, and can be destructured. Tuples compare element by element with `=~`. `==` on a tuple is an error, as on any other struct (see [equality](#equality)):

```ghul
let pair = (10, "hello");                  // (int, string)
let point = (x = 10, y = 20);              // (x: int, y: int)
let x = point.x;
let first = pair.`0;                       // positional access
let (name, age) = ("alice", 30);           // destructuring
```

A tuple can be assigned to a tuple type when each element of the target type accepts the corresponding element. So a `(CAT, Shape.DOT)` value is valid where an `(Animal, Shape)` is expected, and an `(int, string)` is valid where an `(int, object)` is expected. The .NET tuple type is invariant, so the compiler rebuilds the value at the wider type at the point of conversion. It converts each element as that element converts on its own, including boxing and widening to optional. This rule applies to tuple values only. It does not make function types that return tuples assignable: a `(int) -> (int, int)` value is not a `(int) -> (object, object)`.

An unnamed element of a tuple literal that is a bare identifier takes its name from the identifier. So `(a, b)` constructs the same tuple as `(a = a, b = b)`. When the identifier is a field whose name starts with one underscore (a private member), the compiler removes the leading `_` from the element name. So `(_count, _total)` made from private fields has the type `(count: ..., total: ...)`. Locals keep their names unchanged. The compiler removes only one leading underscore.

Destructuring has two forms, **positional** and **by-name**. The syntax shows which form is used.

A **positional** target list `(a, b, ...)` matches the source by the first of these that applies:

1. a value tuple with the same number of elements
2. a `deconstruct(...)` instance method whose parameters are all `T ref`
3. the positional members `` `0 ``, `` `1 ``, ...

The `deconstruct` method covers .NET types such as `Collections.KEY_VALUE_PAIR[K, V]`, ghūl classes that write each `T ref` parameter with postfix `!`, and classes with a primary constructor, which get a synthesised `deconstruct` (see [primary constructors](#primary-constructors)). A type with none of these cannot be destructured positionally. Use the by-name form for it.

```ghul
for (key, value) in dict do          // KEY_VALUE_PAIR.deconstruct
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

A **by-name** target list `(local = field, ...)` takes each element from the named member of the source. `local` is the new local variable, and `field` is the name of the member. `(x = x, y = y) = point` assigns field `x` to local `x` and field `y` to local `y`. `(new_x = x, new_y = y) = point` gives the locals new names. Each `(...)` group is either all positional or all by-name. Mixing the two forms in one group is a parse error. Nested groups each choose their own form:

```ghul
let (a, (bb = b, cc = d), d) = triple;   // outer positional, middle by-name
```

In a refutable context (`if let`, or a `case` `when` pattern), a literal on the left of `=` is a test for equality, not a new variable. `("Alice" = name, a = age)` matches when `source.name` is equal to `"Alice"`, and assigns `source.age` to `a`. The rule is the same everywhere: the left of `=` says what to do with the value (assign it to a new local, or compare it with a literal), and the right of `=` names the member to read.

Postfix `!` on a `T ref` dereferences it: `p!` reads the value, and `p! = v` writes the value. On a `T?`, postfix `!` asserts that the value is present and returns the value (see [optional types](#optional-types)). The parser produces the same node for both, and the operand type decides the meaning. Outside a `deconstruct` body, the dereference form is rarely needed: ghūl code usually takes a `ref` only to pass it to a .NET method that follows the try pattern.

*More detail on this section: [language details](docs/details.md#types-and-literals).*

## functions

See <https://ghul.dev/definitions.html#functions>.

A function definition is a name, a parenthesised argument list, an optional return type after `->`, and a body. The body is either one expression after `=>`, or a block between `is` and `si`:

```ghul
add(a: int, b: int) -> int => a + b;

multiply(a: int, b: int) -> int is
    let result = a * b;
    return result;
si
```

A named function's signature is fully explicit. Every argument has a written type. The return type is written after `->`; a function with no `->` returns `void`. The compiler infers no part of the signature of a named function or method.

A block body returns its value with an explicit `return`, or by ending with an expression. In a non-void body, the final statement is the function's return value on the fall-through path when its type is assignable to the declared return type. This holds with or without a `;` after the statement. An expression, an `if` or `case` expression, and a parenthesised block can each be this final value, the *tail*.

- A tail with a non-void type that is not assignable to the return type is an error at the tail. To discard such a value, write `let _ = expr`.
- A void tail is a statement. Examples are a call with only side effects, and an `if` or `case` whose arms all diverge or only have side effects. The body falls off the end and returns the default value of the return type, and the compiler gives a `definite-return` warning.
- An asynchronous function accepts a bare `T` value as its tail wherever it accepts `return T`.
- Loops, `let`, assignments and `assert` never provide a tail value. Labelled statements and `try` blocks do not provide one either, until `try` has an expression form.
- A void body accepts any tail and discards it. This holds at the end of a void method and in an expression body. So `f(x: int) -> void => g(x);` discards the result of `g`.
- None of these rules apply to a generator. When a generator falls off the end, its stream ends.

A function whose result depends on the values of its arguments can have a `case` over the arguments as its body, with one arm for each case. This is the same as a function defined by equations in Haskell or Elixir. With more than one argument, the scrutinee is a tuple of the arguments. The arms have the same exhaustiveness checking, narrowing and guards as any `case`:

```ghul
gcd(a: int, b: int) -> int =>
    case (a, b)
    when (_, 0) then a
    else gcd(b, a % b)
    esac
```

A function declared at namespace scope can be overloaded on its argument types. When a generic overload and a non-generic overload fit a call equally well, the compiler chooses the non-generic overload if each of its parameters is at least as specific as the generic overload's parameter, after the generic overload's type arguments are bound. For a `string[]` argument, `f(items: List[string])` is chosen over `f[T](items: Iterable[T])`, and `f[T](items: Iterable[T])` is chosen over `f(items: List[object])` or `f(items: object)`. ghūl has no default argument values.

A program starts at a function named `entry`. In a file with no namespace, the program can instead start at the top-level statements, which the compiler collects in source order into the entry point.

An `entry` function can declare any subset of two parameters. The compiler recognises each parameter by its declared type, not its name:

- a `string[]` holds the command-line arguments
- a `Ghul.Environment` gives access to the process environment. `Ghul.Environment` is a ghul-runtime trait that reads and writes the process's environment variables.

So `entry()`, `entry(args: string[])`, `entry(env: Ghul.Environment)` and `entry(args: string[], env: Ghul.Environment)` are all valid, with the parameters in either order. The compiler also recognises the environment parameter when its type is named through a `use`: `use Ghul;` then `entry(env: Environment)`, `use Ghul.Environment;` then `entry(env: Environment)`, or the alias `use X = Ghul.Environment;` then `entry(env: X)`. `entry` returns either nothing or an `int` exit status.

Only the environment parameter changes how the program starts. When `entry` declares it, the compiler synthesises a private wrapper with the real entry-point signature: no parameters, or one `string[]` when `entry` also declares the arguments. The wrapper resolves `Ghul.Environment` and calls `entry`. When `entry` does not declare the environment parameter, `entry` compiles directly to the program's real entry point.

This recognition applies only to a global function found by name: the default `entry`, or the name that `--entry` gives. It does not apply to a class's static method used as the entry point. Such a method takes a `string[]` or no parameters.

A function with the build's entry-point name and any other signature is an error at the function. The error names the part of the signature that is invalid:

- a return type that is neither `int` nor `void`. An asynchronous `entry` has this error, because it returns a task. To run asynchronous work, read `.result` on the returned task.
- more than one parameter
- a parameter of any other type

In this case the file's top-level statements do not run instead. A program that declares where it starts has made that choice.

`--entry <name>` changes the entry-point name. An `@entry` pragma marks any function as the entry point, whatever its name.

A formal parameter can be a tuple-destructure pattern instead of a plain name. It is still one parameter, of the written tuple type. On entry, the pattern is unpacked into its named elements, in the same way as a `let (a, b) = pair;` local:

```ghul
add_pair((a, b): (int, int)) -> int => a + b;

add_pair((3, 4));    // 7
```

Patterns can nest, and can be mixed with ordinary parameters: `f(x: int, (a, b): (int, int), y: int)`. A namespace-scope function's signature is always fully explicit, so the type of the whole pattern is required; there is no context to infer it from. The element types come from the type of the whole pattern, so write the elements as plain names. The type of the whole pattern can be any type that can be destructured positionally: a tuple, or a type with a matching `deconstruct(...)` method. A formal argument list does not support the by-name group form (`(x = field, ...)`).

Functions are first-class values. A function literal has the same form as a function, without a name. The compiler usually *infers* its argument types and return type from the body and from the context of the literal, so they are usually written without annotations. Either can be written explicitly. A literal with one argument needs no parentheses around it. `A -> B` is the type of a function from `A` to `B`.

A function *type* has at most 16 parameters. So a function literal, or a named function used as a value, has at most 16 parameters. A named function itself has no limit, because it is never represented as a value of a function type unless it is used as a value.

A function literal captures variables from the enclosing scope, and so forms a closure. It captures an immutable `let` by value: the closure holds a copy of the value at the time the literal is constructed. It captures a `let mut` by reference: the closure and the outer scope share one variable, and either one can read or reassign it. A function literal refers to itself with the `rec` keyword:

```ghul
let twice = x => x * 2;
let apply_twice = (f: int -> int, i) => f(f(i));
let factorial = n rec => if n == 0 then 1 else n * rec(n - 1) fi;
```

A block-bodied function literal ends with a tail, exactly as a named function does. A final statement whose type is assignable to the return type is the value that the literal returns on fall-through. When the return type is written, or comes from the slot that the literal is assigned to, the compiler checks the tail against that type. When the return type is inferred and the body has no `return`, the tail decides the return type. A void tail decides nothing, so such a body is void, and it can end with a guard `if` like any void body.

A slot whose function type returns `void` decides the literal's return type, as any slot does. So a literal assigned to such a slot discards whatever its body produces, with either body form. Use this to pass a call whose result is not wanted where a function is expected:

```ghul
names |> each(name => seen.add(name));    // `add` returns a bool, discarded here
```

When several overloads take a function with the same number of parameters, the compiler chooses as follows:

- A body that produces a value goes to a parameter whose function type returns a value. A parameter whose function type returns `void` is chosen only when no other candidate fits. So a literal that returns a `bool` chooses a `(T) -> bool` parameter over a `(T) -> void` parameter.
- A written return type chooses directly: `name -> void => seen.add(name)` chooses the void parameter.
- Among parameters that all return a value, the type that the body produces chooses the parameter it fits. A literal that returns an `int` chooses a `(T) -> int` parameter over `(T) -> double` and `(T) -> long` parameters, however many there are.

A function literal's parameter can be a destructure pattern. The pattern is written in its own parentheses inside the parameter list: the outer parentheses are the parameter list, and the inner parentheses are the pattern. It is one parameter, unpacked into the names that the body uses, as for a named function:

```ghul
let pairs = [(1, 2), (3, 4)];

pairs |> map(((a, b)) => a + b);          // element types inferred from the sequence
```

The single-parameter shorthand without parentheses (`x => …`) cannot have a pattern, and cannot have a type annotation. Both need the parentheses. Unlike in a named function, the compiler usually infers the type of the whole pattern, from the sequence or slot that the literal is passed to, or from how the parameter is used. Write the type explicitly when nothing gives it. As for a named function, the type can be any type that can be destructured positionally, and the elements are written as plain names. The type of the whole pattern accepts the full type syntax:

```ghul
let add = ((a, b): (int, int)) => a + b;

entries |> each(((key, value): Collections.KEY_VALUE_PAIR[string, int]) =>
    write_line("{key}={value}"));
```

Patterns can nest and can contain discards. So `(((a, b), c)) => …` and `((_, b)) => …` are both valid, in plain and in asynchronous function literals.

A named function can also be written among the statements of a body. Such a nested function is a function literal assigned to a local variable with the function's name. So it captures, compiles and is called exactly as the equivalent `let` would be. The two spellings are interchangeable:

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

A nested function's argument types and return type are optional, as on any function literal. On a namespace-scope function they are required, because not all of its uses are visible to the compiler. A nested function can have either body form. Its name is valid wherever a value of its function type is expected, as well as in a call:

```ghul
    halve(x) => x / 2;

    let apply_to_ten = (f: (int) -> int) => f(10);

    apply_to_ten(halve);
```

A nested function refers to itself by its own name, so it needs no `rec`. A literal inside its body refers to it by name too:

```ghul
    fact(n: int) -> int => if n <= 1 then 1 else n * fact(n - 1) fi;
```

A nested function is a local, so it is defined from its own definition onward. A reference to it above its definition is an error. Mutual recursion between two nested functions is an error. To get mutual recursion, write one of the pair as a `let mut` literal and assign it after the other is defined. A file's top-level statements are not a body, so a named function among them is a namespace-scope function, and its argument types are required.

A call with `*` written for one or more of its arguments is a *partial application*: a function value with one parameter per `*`, in order, that makes the call with its parameters in those positions. The other arguments are evaluated once, where the partial application is written, not on each call:

```ghul
scale(x: int, by: int) -> int => x * by;

xs |> map(scale(*, 2));                   // the same as map(x => scale(x, 2))
let between_1_and_9 = between(1, *, 9);   // (int) -> bool
let product = scale(*, *);                // (int, int) -> int
items |> each(log.write(*));              // the receiver is evaluated once
```

The `*` is a whole argument of the call: `f(*, 2)` is a partial application. It belongs to the innermost argument list it is written in, so `f(g(*, 1), 2)` partially applies `g` and passes the result to `f`. An operator expression is a call of its operator, `a + b` being `+(a, b)`, so `*` as an operand partially applies the operator: `* + 1` is `x => x + 1`, `10 - *` is `x => 10 - x`, `* - *` takes two parameters, `- *` negates, and `xs |> filter(* < 3)` keeps the elements below three. The other operand is evaluated once, where the expression is written, and the operator is whichever the written operands would resolve to, a built-in, a static or an instance member alike. Only the operator node the `*` is an operand of becomes the function, so `(* + 1) * 2` multiplies a function by two and is an error. `??`, `/\` and `\/` evaluate their right operand only for some values of the left and cannot be partially applied. Where an operand is expected, `*` is a placeholder when an operator, a comma, a closing bracket or the end of the statement follows; otherwise it is the prefix operator `*` applied to what follows. Operator characters run together into one operator, so `-*` is the operator `-*`: the negation is written `- *`. Each `*` takes its type from the formal it stands in, exactly as a bare `_` argument does, so the call is resolved as any call is, with the written arguments choosing the overload. Where a function type is expected of the partial application - a declared slot, or a formal of the call it is an argument to - its parameter types type the `*` arguments first, one each in order, so the expected type can choose the overload where the written arguments alone would not: `let halve: (double) -> double = scale(*, 0.5)` picks the `double` overload of `scale`. A `*` whose type nothing decides, such as a lone `*` to an overloaded function with no expected type, is an error: write a function literal with a typed parameter instead. The callee can be a function, a method, a constructor, or a value of function type. A `*` cannot be combined with `~>`.

*More detail on this section: [language details](docs/details.md#functions).*

## type definitions

See <https://ghul.dev/definitions.html#types>. ghūl has five kinds of user-defined type. All of them are declared at namespace scope. A type cannot be declared inside another type.

### classes

A class defines a reference type. The class header is the class name, then optionally a colon followed by a superclass and any traits the class implements. The body is between `is` and `si`, and contains properties, methods and constructors:

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

A class can extend at most one superclass, and can implement any number of traits. `self` is the current instance. A constructor expression creates an instance: it is the type name called like a function, and it selects the matching `init` overload (`PERSON("alice", 30)`). A class with no declared superclass extends `object`. `==` on a class always compares references. To give a class structural equality, define `=~`, or request a synthesised one with the `@equality()` pragma. See [equality](#equality).

A class without the `@equality()` pragma and without its own `=~` has no `=~`. For such a class, `==` compares references. Structs and unions need no pragma: the compiler gives each struct and union equality when it declares none. A struct is a value, so two structs with equal members are equal values. Two union values are equal when they hold the same variant and that variant's fields are equal.

A member whose type is not optional must be given a value. When a constructor leaves one or more such members unassigned on some path, the compiler gives one `field-definite-assignment` warning on the constructor's name. The warning names every member the constructor does not assign, because the object would hold null in a member that nothing else can set to null. Each unassigned member also has a related location at its declaration; for an auto-property, the location is the property, not its hidden backing field. An editor can show the related location as a link.

A constructor gets credit for the members it assigns itself. It also gets credit for the members assigned by methods it always calls on `self`. These calls give no credit, because they do not always run or do not always reach that method:

- a call on only one branch of an `if`
- a call on another object
- a call to a method that a subclass can override

Members of optional type and members of value type are not checked, because neither can hold an unexpected null. Suppress the warning with `@suppress("field-definite-assignment")` on a file or on the constructor, or with `--suppress field-definite-assignment` for the whole project.

Two postfix modifiers control the class hierarchy:

- **`open`** allows subclasses in other assemblies. A class without `open` can only be subclassed in the assembly that declares it. A class in another assembly that extends it is a compile-time error. Use `open` when a library class is meant to be extended by other code. Removing `open` later breaks those subclasses. The closed hierarchy also helps type narrowing: on the else edge of an `isa` test, the compiler can list a closed class's subclasses.
- **`abstract`** means the class itself never exists as a runtime instance. Only its subclasses do. A direct constructor call (`Animal()`) on an abstract class is a compile-time error. Subclasses still call `super.init(...)` for shared initialisation. Narrowing on closed hierarchies uses this: when the root class is `abstract`, the else edge of `isa CAT(a)` excludes the root class, and can narrow to the single remaining subclass.

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

The two modifiers are independent. `open` controls who can extend the class. `abstract` controls whether the class can be instantiated. A class can have both (`class Animal abstract open is ... si` is an abstract base that other assemblies can extend), either, or neither.

A method with no body, such as `foo();` or `foo() -> int;` with no `is … si`, is **abstract**. It is a contract that a subclass must implement. It is not a method that does nothing. A class that declares an abstract method is abstract too. So constructing that class is an error, exactly as if its header had `abstract`. A concrete subclass that does not implement the method is an error, and the error names the method and the class that declares it. This rule does not apply to property accessors, `init` or static methods. A write-only property has a synthesised getter with no body. The accessors of a property read and write its backing field, and do not declare anything.

The rule applies whether or not a trait implemented by the class supplies a default for the member. A class that declares the member again with no body removes the trait's default. The class is then abstract, its subclasses must implement the member, and `super` cannot reach the member, because no class in the chain implements it. A class that wants the trait's default does not declare the member.

`super.foo()` cannot call an abstract method. A super call names the base implementation directly, and an abstract method has none.

*More detail on this section: [language details](docs/details.md#classes).*

### structs

A struct defines a value type. Its syntax is the same as a class's, except that a struct has no superclass. A struct can implement traits. Copying a struct copies all of its fields:

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

`==` and `!=` are errors on every struct operand: a tuple, an imported `System.DateTime`, or a struct of your own. They compile to a single comparison of the value's bytes, which does not compare its fields. Use `=~` to compare structs by value.

For a struct that declares no equality of its own, the compiler synthesises `=~` and a matching `get_hash_code`. They compare the members that hold the struct's state: each auto-property and each `field`, in order, with that member type's own equality. A property with a body computes its value from the state, so it does not take part. A static member belongs to the type, so it does not take part either.

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

A bare member declaration such as `x: double;` declares an auto-**property**, not a field. A struct's property getter returns a *copy* of the struct. This matters when a heap object holds a struct: a change made through the property changes the copy, and the change is lost. So the compiler reports an error for a store through such a property. To change a struct member in place, declare a real field with the `field` modifier:

```ghul
class HOLDER is
    origin: POINT field;     // a real field, mutable in place
si
```

*More detail on this section: [language details](docs/details.md#structs).*

### primary constructors

A class or struct can declare its constructor parameters in its header. These are *primary parameters*. Each primary parameter becomes a parameter of the synthesised `init`. For a primary parameter with no matching declaration in the body, the compiler **synthesises** a field or property with the same name and the parameter's declared visibility:

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

A **modifier** after the parameter's type changes the default visibility or storage. The modifiers follow the same rules as on a field or property declared in the body:

- `x: int public`: public read and write.
- `x: int protected`: readable in the declaring class and its subclasses.
- `x: int private`: the value is stored in the member `_x`, which is non-public under the rules in [naming conventions](#naming-conventions). The parameter keeps the name `x`. So code reads the member as `_x`, and the constructor argument is named `x`. A private member is not included in the synthesised `deconstruct`.
- `x: int field`: a plain field, not an auto-property.
- `x: int static`: a static member, not an instance member.
- `x: int init`: **no member is synthesised**. The parameter is in scope only in the synthesised `init` and in any explicit `init(..)` body. Use this when the constructor uses its argument to compute something else (`init(.., other)` style).

A parameter named with a leading underscore (`_x: int`) has the same effect as `private`, by the naming convention, and follows the same rules. `_x: int private` is valid, and `private` changes nothing, because the name already makes the member non-public.

A declaration in the body with the same name as a primary parameter replaces the synthesised member, and receives the value that the synthesised `init` assigns. The names match by the same rule: `_foo` or `foo` matches the parameter `foo`. This is the *capture* form. These declarations capture the primary parameter `x`:

- the field shorthand `_x;`
- a property declaration named `_x` or `x` that has neither a read body nor an assign body

A property with an accessor body is an ordinary member, not a capture. With a capture you can also give the member a private name (`_x;` for a primary parameter `x`) without a modifier.

```ghul
class POINT(x: int, y: int) is
    _x;
    _y;

    show() => write_line("({_x}, {_y})");
si
```

is also equivalent to the expanded `POINT` above, with the fields named `_x` and `_y`.

Primary constructors also support:

- **`super(expr, expr);`** as a declaration in a class body. It passes the given expressions to the superclass `init`. Each argument can be any expression whose free identifiers are primary parameters. Literals and names at namespace or type level are also in scope. So `super(null)`, `super(other.x)`, `super(LIST([elem]))` and `super(Source.LOCATION.reflected, owner, name)` are all valid. A primary parameter used by `super(...)` gets no synthesised member, because its value goes to the base class.
- **`init(..)`**: an explicit body for the primary `init`. It runs after the synthesised field assignments.
- **`init(.., extras)`**: a secondary `init` overload. `..` expands to the primary parameters. The compiler adds a call to the primary `init` at the start of the body, so every captured member is assigned before the secondary body runs.
- **automatic `deconstruct`**: each publicly readable captured member becomes one `T ref` parameter of a synthesised `deconstruct`, in the order of the header. In .NET, the method has the name `Deconstruct`, for use from other languages. So `let (x, y) = POINT(3, 4)` works without a hand-written `deconstruct`. The compiler does not synthesise `deconstruct` when the class body declares a `deconstruct(...)` with any number of parameters, or declares any backtick-numbered property (`` `0 ``, `` `1 ``, ...). Either one means the author provides positional access.

```ghul
class DOG(name: string, breed: string): ANIMAL is
    _breed;

    super(name);

    init(.., trick: string) is
        write_line("the {_breed} can {trick}");
    si
si
```

When the body is empty, a `;` can replace `is si`:

```ghul
class POINT(x: int, y: int);

struct VECTOR(dx: int, dy: int);
```

Classes, structs and unions all support primary constructors. The [unions](#unions) section describes the union form.

### traits

A trait is ghūl's equivalent of an interface. A class or struct implements a trait by naming it in the header. It must implement every trait member that has no default. A trait member *can* have a default body. An implementing type inherits the default, and overrides the member only to change its behaviour. An override can call the default with `super`:

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

A class extends one superclass and can implement many traits. Structs and unions implement traits the same way, with the same `: Trait, Other` header syntax. Every trait member of a union must have a default, or must be implemented by a property that the union supplies, because a variant has no place in its syntax for a method body.

A trait declares properties and methods. A trait cannot declare fields: `field` in a trait body is an error. A bare trait property is read-only. To make a trait property assignable, give it an explicit assign accessor. An implementing type then implements it with a `public` property, which supplies both accessors:

```ghul
trait Counted is
    count: int, = v;      // readable and assignable
si

class TALLY: Counted is
    count: int public;
    init() is count = 0; si
si
```

*More detail on this section: [language details](docs/details.md#traits).*

### unions

A union is a reference type whose value is one of several variants. Each variant has a name and an optional list of fields:

```ghul
union Tree is
    NODE(left: Tree, right: Tree);
    LEAF(value: int);
si
```

Construct a variant through the union name: `Tree.LEAF(123)`. A variant with no fields is a *unit variant*. Code refers to a unit variant by name, without parentheses. Each unit variant has one shared instance for each generic instantiation:

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

The compiler infers the type arguments of a unit variant from the context: the declared type of the variable, the parameter type of the argument, or the return type. It infers them in the same way as for the parenthesised constructor form. The explicit `[int]` is needed only when there is no context. The parenthesised form (`Color.RED()`, `Option.NONE()`) is also valid, and returns the same shared instance.

To test which variant a union value holds, use `isa V(x)` or `if let v: V = x`. Both test the variant at run time. `if let` also declares `v` with the variant type, for use in the then-arm:

```ghul
if let node: Tree.NODE = tree then
    write_line("node: {node.left} and {node.right}");
elif let leaf: Tree.LEAF = tree then
    write_line("leaf: {leaf.value}");
fi
```

Both `isa V(x)` and `if let v: V = x` narrow `x` itself to the variant type. The narrowing applies in the then-arm, and after a guard that returns. On a union with two variants, both forms narrow `x` to the other variant in the `else` branch, so member access on `x` in the else arm resolves against that variant.

The compiler checks a `case` over a union value for exhaustiveness:

- Missing variants give a `non-exhaustive-case` warning on a `case` statement. On a `case` expression they are an error, because the expression must produce a value.
- `redundant-case-arm` reports an arm that matches nothing the earlier arms do not already match.
- `dead-case-else` reports an `else` arm that never runs, because the earlier arms cover every value.

These checks also apply to a `case` over `bool`, `bool?`, an optional union `T?`, a closed class hierarchy, and an enum. The values of a closed class hierarchy are its subclasses in the same assembly, plus the root class when the root class is concrete, because a concrete root class can be constructed.

An arm that names a unit variant as a value (`when Color.RED then`) covers that variant, exactly as `when _: Color.RED then` does, because a unit variant has one shared instance. A label in a `case` takes its type from the scrutinee. So a unit variant of a generic union needs no type arguments in a label: `when Option.NONE then` is valid over an `Option[int]`.

`case-needs-else` reports a `case` with no `else` arm whose scrutinee the arms cannot cover in this way. It is a warning on a `case` statement, which then does nothing when no arm matches. It is a warning on a `case` expression whose expected type has a default value (a value type or `T?`). It is an error on any other `case` expression. A scrutinee that can be destructured and whose arms do not cover all combinations of its elements is reported in the same way, and the report names the combinations that no arm covers.

Unions have structural equality through the `=~` operator. Two union values are `=~` when they hold the same variant and the variant's fields are equal, field by field. Each field is compared as `=~` compares two values of the field's type anywhere else:

- with the field type's own `=~`, when the type defines one
- with the field type's `<>` compared to zero, when the type defines `<>` and no `=~`
- element by element, for an array or a list
- with the runtime's default equality comparer, in all other cases. So a class that overrides `equals` is compared with `equals`. A class with no declared or synthesised `=~` is compared by reference. A struct or tuple is compared field by field.

A field whose type is a bare type parameter is compared with the runtime's comparer for that type. That comparer uses whatever equality the type argument provides.

A union with exactly one variant that has fields of *its own* works as an option type: `u?` tests whether `u` holds that variant, and `u!` returns its value. Fields from a union primary-constructor header do not count as the variant's own fields. So a variant that has only the shared fields counts as a unit variant for this rule. In a union with several variants that have fields, a trailing `default` on one variant makes `?` and `!` act on that variant:

```ghul
union Result[T, E] is
    OK(value: T) default;
    ERROR(error: E);
si
```

`r?` is then true when `r` holds `OK`. `r!` returns the `OK` value, and throws if `r` holds `ERROR`. A default variant with one field unwraps to that field, by position; the field does not need to be named `value`. A default variant with several fields unwraps to the variant. Inside `if r?`, `r` is narrowed to the default variant, so code reads its fields directly, with no `!`. The `else` branch narrows `r` to the other variant or variants. This is the same narrowing that `isa OK(r)` does.

A union can declare a **primary-constructor header** for state that every variant shares. Each variant includes the shared parameters in its field list with `..`:

```ghul
union TRIVIA(location: LOCATION) is
    LINE_COMMENT(text: string, ..);
    BLOCK_COMMENT(text: string, ..);
    BLANK_LINE;
si
```

The primary parameters become fields of the union base class. So `t.location` is readable on any `TRIVIA` value, whatever its variant. A field declared in a variant, such as `text`, belongs to that variant only. The `..` can be at any position in the variant's field list. The order of fields in the synthesised constructor and in positional destructuring (`let (a, b) = trivia`) is the source order. A variant with no fields of its own can omit the field list (`BLANK_LINE;`), and is treated as `(..)`. A variant with its own fields must include exactly one `..`. This works in the same way as `..` in a class's secondary `init` ([primary constructors](#primary-constructors)).

*More detail on this section: [language details](docs/details.md#unions).*

### enums

An enum is a set of named integer constants. The values start at 0 unless the members have explicit values. Code refers to a member through the enum type: `Suit.HEARTS`. The enum type has a `PascalCase` name, and its members have `UPPER_SNAKE_CASE` names. A trailing comma after the last member is valid:

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

Enum values support the relational operators and equality (`=~` and `==`). They are ordered by their integer values. `=~` also works on an optional enum, as on any other optional. A single member can be imported by name, as in `use Some.Namespace.Suit.HEARTS;`, as well as used through the type.

*More detail on this section: [language details](docs/details.md#enums).*

### partial and impl blocks

A separate block, which can be in a separate file, can add members to a type that is already declared. The type must be declared in the same assembly. The added members are real members of the type. They have full private access and normal virtual dispatch, and they behave exactly like members declared in the type's own body.

*More detail on this section: [language details](docs/details.md#partial-and-impl-blocks).*

### properties, methods, and visibility

A property is a name and a type, with optional getter and setter bodies. A property with no bodies is stored in a hidden field. Any code can read a property. Only code in the type that defines the property can assign it. A property name that starts with `_` is non-public for reading too. How far non-public reaches depends on the `--underscore-access` policy (see [language details](docs/details.md#naming-conventions)).

The storage and visibility modifiers of a primary-constructor parameter also apply to a declaration in the body: `x: int public` for public read and write, `x: int field` for a plain field instead of an auto-property, and `x: int static` for a static member. The `field` modifier matters most on value types (see [structs](#structs)). `private` is the exception. On a primary-constructor parameter, `private` gives the member a different name from the parameter. A declaration in the body has no second name, so `private` on a body declaration with no accessor body is an error. Name the member `_x` instead.

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

A method is a function declared in a class, struct or trait. A method has an implicit `self`. A constructor is a method named `init`. A method is public unless its name starts with `_`. A method whose name starts with `_` is non-public under the `--underscore-access` policy. By default, only the declaring class can see it. The compiler enforces this.

## operators

See <https://ghul.dev/definitions.html#functions>.

An operator is a sequence of operator characters, which the scanner reads as one token. The ASCII operator characters are `! $ % ^ & * - + = | : @ ~ # \ < > . ? /`. Every non-ASCII character that Unicode classifies as a symbol is also an operator character. So `×`, `÷`, `∪`, `⊕` and `≠` are operator characters in exactly the same way as `*` and `+`, and an operator can use the standard notation for what it does.

A function whose name is an operator is used as an operator. An operator declared as a member takes its left operand as `self` and its right operand as its argument. An operator declared at namespace scope takes both operands as arguments. Use a namespace-scope operator to give an operator to a type you did not write:

```ghul
struct N(v: int) is
    ⊕(other: N) -> N => N(v + other.v);
si

⊗(a: N, b: N) -> N => N(a.v * b.v);
```

The compiler resolves an operator among the declarations that take the same number of operands as the use. A prefix `-` has one operand. So a member `-` with two operands (`self` and one argument) never matches a prefix `-`. Inside the type that declares such a member, a prefix `-` still finds the unary operator declared as a static member or at namespace scope.

An operator's precedence comes from its first character. A declaration cannot set it. So an operator that looks like arithmetic has arithmetic precedence. From highest to lowest precedence:

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

The unary `\` is the bitwise complement of an integer. Its result has the operand's type: `\5` is `-6` for an `int`, `\0` is `-1`, and `\x` is `250` for a `ubyte` `x` of 5. `\` is the unary partner of the binary `&`, `|` and `^`. `!` is the logical not of a `bool`. The boolean operators `/\` and `\/` are each one token.

An operator is a function value wherever a function of its type is expected, whether it is declared as a function or built in (see [language details](docs/details.md#operators)). A built-in operator is an instruction rather than a method, so the compiler synthesises a function that applies it, once for each type it is used at in a function body. The name is written with the backtick escape: ``int.`+`` names the `+` of `int`, and a bare `` `+ `` names whichever `+` the expression `a + b` would resolve to for operands of the expected function type's parameter types: the same candidates, by the same overload resolution, so a `+` declared on the right operand's type or at namespace scope is found exactly as it would be in the expression. So `xs |> reduce(0, `+)` sums an `int` sequence, and `pairs |> map(`+)` adds the elements of each pair. A bare spelling with no expected function type is an error, as is one for which no operator resolves. A bare spelling can also head a call, where the written arguments resolve it as the operands of `a - b` would and a `*` takes the formal of the operator chosen: `` `-(10, *) `` is `x => 10 - x`, and `xs |> map(`+(*, 1))` adds one to each element. A call whose every argument is `*` has nothing to resolve from and is an error. `<`, `<=`, `>`, `>=`, `!=` and `!~` are derived from `<>`, `==` and `=~` and are not functions. An instance member is not a value, whether or not it is an operator, because it needs a receiver: ``string.`<>`` is an error, and a function literal takes its place.

*More detail on this section: [language details](docs/details.md#operators).*

## equality

ghūl has two equality operators, and they test different things.

`==` and `!=` test whether two values are *identical*. For a scalar, identical means the same bits. For a reference, it means the same object. They compile to one machine comparison, and the following properties come from that:

- No type can overload or override `==`, so its behaviour does not depend on the operand types.
- `==` does not look inside a value, so its result does not depend on how deeply the value nests.
- `==` calls nothing, so it never throws. Comparing two absent optionals compares two nulls, and dereferences nothing.
- `==` does not walk a structure, so it costs the same on a very long string as on an `int`.

So `a == b` means one instruction, and a reader can understand it without knowing the operand types.

Because of this, `==` and `!=` accept only these operands:

- primitive scalars: the integer types, `single`, `double`, `decimal`, `bool`, `char`
- enum members
- references: `string`, `object`, any class, any trait, and `null` compared with one of these
- a bare type parameter. The type argument decides which of the above it is.

Any other operand is a compile error, and the error suggests `=~`. On a struct (a tuple, an imported `System.DateTime`, or a struct of your own), the single comparison would compare the value's bytes, not its fields. That would give wrong results without any error: a reference field would be compared by identity, and padding bytes would be compared.

**`==` on a `string` compares references, and this will not change.** Two strings with the same characters are `==` only when they are the same object. Two literals are usually the same object. Two computed strings usually are not. This definition is the only one that keeps the four properties above. Compare the characters of strings with `=~`.

The order of two strings follows .NET globalization. On .NET, `<>` and the relational operators compare strings by the current culture, as `String.CompareTo` does. `sort()`, `min` and `max` also compare by the current culture. The wasm and llvm targets behave like a .NET program configured for invariant globalization, which compares strings by UTF-16 code unit. So upper case sorts before lower case, and punctuation sorts by its code. A .NET program gets the same order by setting `<InvariantGlobalization>true</InvariantGlobalization>` in its project. `string.compare_ordinal(a, b)` compares by code unit in any program. The sign of its result is the same on every target. The size of its result depends on the target.

`=~` and `!~` test whether two values are *equal in meaning*. Each type defines what that means for its values:

```ghul
"hello" =~ "{"hel"}{"lo"}"      // true - same characters
"hello" == "{"hel"}{"lo"}"      // false - different objects
```

`=~` resolves on:

- primitive scalars, `char`, `bool`, `decimal` and enum members, which it compares by value
- `string`, which it compares by characters
- any type that declares `=~` as a member. This includes a class, struct or trait of your own, and any imported .NET type that implements `IEquatable[T]`. `System.DateTime` and `System.Version` get `=~` this way.
- any type that has a global `=~`. `=~(a: T, b: T) -> bool` at namespace scope gives `T` the operator without changing the type. Use this for a type you did not write, or for a tuple.
- a union, through its synthesised operator (see [unions](#unions))
- a struct whose state is all public and that declares no equality of its own, through its synthesised operator. The operator compares member by member, with each member type's own equality (see [structs](#structs)).
- a class with an `@equality()` pragma, through its synthesised operator. The operator compares member by member and then compares the base class, with each member type's own equality (see [classes](#classes)).
- a tuple, element by element, with each element type's own equality, at any depth of nesting
- an array, a `List[T]` or a `LIST[T]`. It compares the counts, then element by element, with each element type's own equality. So `[[1, 2], [3]] =~ [[1, 2], [3]]` is true, and two lists of a type that declares `=~` compare with that `=~`. Here, elements of a class that declares neither `=~` nor `<>` compare by reference. The same comparison written directly on two such values is an error. A list of such values has a useful equality, and two such values alone have none.
- a type that declares `<>` and no `=~`. An ordering defines equality, so `a =~ b` is `a <> b == 0`.
- a bare type parameter, through the runtime's comparer for the type argument

When more than one of these applies, the nearest declaration is used: a member operator first, then a global operator. The element-wise comparison and the comparer are used only when no operator is declared.

Some types have no `=~`:

- a class that neither declares equality nor requests it with `@equality()`. Its `=~` does not resolve; `=~` does not fall back to identity.
- `object`
- a struct with any non-public state
- a struct that declares `get_hash_code`, or an `equals` that takes an `object`, without also declaring `=~`. Such a struct has no `=~` until one is declared.

Using `=~` on a type that has none is a compile error, and the error names the operand types. A `SET` is not compared element by element, because set equality ignores order. Use `set_equals` to compare sets. A pipe has no `=~`.

A type that defines `=~` must also define `get_hash_code`. The two belong together, and .NET collections check the hash first. [.NET interop](#net-interop) covers the `Ghul.Equatable[T]` contract, the `Equals` bridge, and why the compiler cannot synthesise the hash.

`=~` handles null; `==` has no need to. Two absent values are equal. An absent value and a present value are not equal. In neither case does an operator body run. See [optional types](#optional-types).

This applies wherever `=~` is defined: `a =~ b` resolves on `T?` exactly when it resolves on `T`, and gives the same result for two present values. So an optional enum, an optional tuple and an optional `T` compare like any other optional, with no narrowing first. Declaring `=~(a: T, b: T) -> bool`, as a member or as a global, is enough to make `T? =~ T?` work.

On scalars and enums, `==` and `=~` give the same result. On every other type, the two give different results, or only one of them is defined. `=~` is the operator that means "equal" in the usual sense. Use `==` when the question is identity, or when the cost of the comparison matters.

## optional types

See <https://ghul.dev/language-basics.html#optional-types>.

A type followed by `?` is an *optional* type. A value of type `T?` is either present or absent. The type without the `?` is non-optional. The postfix `?` operator tests whether an optional holds a value. The postfix `!` operator returns the value. `!` is rarely needed: `if x?` narrows `x` to its non-optional type, and `if let` tests an optional and assigns its value to a new variable in one step.

```ghul
let name: string? = lookup();

if name? then
    write_line("hello, {name}");   // name is non-optional string here
fi
```

Optional types work for reference types and value types. The compiler represents `T?` in one of three ways:

- a nullable reference, for a reference type
- `Nullable[T]`, for a value type
- `MAYBE[T]`, for an unconstrained type parameter. So `T?` can be written even where `T` can be either kind of type.

The representation is an implementation detail. All three behave the same way. A value of one representation is accepted wherever another representation is expected, when it is assigned, passed or returned, and the compiler converts it at that point. The compiler owns this `MAYBE[T]`. A program that writes `Ghul.MAYBE[T]` itself gets the plain struct of that name. That struct is not an optional type, and is not assignable to a `T?`.

The three representations are distinct in one place: as a type argument of another type. Over an unconstrained `T`, `LIST[T?]` is `LIST[MAYBE[T]]`, and is not `LIST[string?]` for any `T`. A function type is a generic type too. So a value of type `(int) -> string?` is not a `(T) -> U?` for any `U`. A type argument has no point where the compiler can convert. So a call that must infer `U` from a *stored* function value of a fixed type such as `(int) -> string?` does not resolve. A function whose own return type is `U?` over a type parameter has the same representation, and is accepted.

A function referred to *by name* is accepted whatever representation its signature uses. A function name is not yet a value. When the function's signature and the parameter's function type describe the same call and differ only in the representation of an optional position, the compiler wraps the function in a literal with the parameter's exact type, and converts at that literal's boundary. So `bind(unit(8), halve)` resolves when `halve` returns `int?`. It also resolves in the other direction, when the parameter uses the reference representation. A function type that differs in anything other than the representation is still an error.

A function literal with an inferred return type has no fixed representation. When the literal is passed to a `(T) -> U?` parameter, its return type takes the parameter's representation, whatever the body produces. So `bind(4, n => n + 1)` and `xs |> find_map(x => lookup(x))` both resolve. A `string?` or a bare `int` from the body is converted at the literal's return.

A non-optional `T` can be assigned to a `T?` with no conversion written. Assigning a `T?` to a `T` is an error. To use a `T?` where a `T` is expected, narrow it first:

- `if x?` and `if let` narrow `x` inside the guarded region.
- `x!` asserts that `x` is present, and throws if it is absent.
- `x ?? _` gives a non-optional fallback value when `x` is absent.

Reading a member, iterating (`for x in xs`) or indexing (`xs[i]`) through an optional value that flow analysis has not proved present is an error. Such a value can be a local or member path that is not narrowed, or a call result. This error has the same status as passing a `T?` where a `T` is required, because it is the same fact about the same static type. So it has no slug to suppress and no severity to change. To read through the value, narrow it first (`if xs?` or `if let`), or use `x?.y`, `x.has_value` or `x!`.

`!` on a value that is not optional is an error (`cannot unwrap this`), because there is nothing to unwrap.

When flow analysis has proved a value present, for example inside an `if x?` or `if let` region, a further `!`, `?` or `?.` on that value gives a warning: `redundant-unwrap`, `redundant-presence-test` or `redundant-coalesce`. To fix the warning, remove the operator. To suppress it, use `@suppress("<code>")` on a declaration or a file, or `--suppress <code>` for the whole project. `--warn-as-error`, `--warn-as-info` and `--warn-as-hint` change a slug's severity.

`?` or `?.` on a non-optional *value type* is an error, because a struct is never null and there is nothing to test.

On a non-optional *reference*, a `?` presence test is redundant because the type guarantees presence. It gives a `presence-test-non-optional` warning. Inside an `assert` condition there is no warning, because the compiler treats the test as deliberate. `?.` on a non-optional reference is valid. It is a defensive null test, for a null that can arrive despite the static type, for example from a reflected .NET API. Comparing such a value with `null` is not the same test. `null` is a value of optional types only, so `x == null` and `x != null` on a non-optional operand are errors. Write the defensive test as `x?` or `x?.y`.

A type with `has_value` and `value` properties is treated as optional. `?` uses those properties on any such type. `!` uses them only on a struct.

An operator declared on a type takes its left operand as `self`, and `self` always holds a value. So no such operator accepts a left operand that may be absent. `a - b` with an `a: T?` that is not narrowed does not resolve, in the same way that passing that `a` to a non-optional parameter does not. Narrow the operand first, or call the operator through `a!`. `=~` and `!~` are the exception, whatever the operator declares: the compiler writes null checks around the call, so an absent left operand gets a result and is not dereferenced. To declare any other operator that accepts an absent left operand, declare it at namespace scope with an optional first parameter. The left operand is then an argument, not a receiver.

The `?.` operator is *coalescing* member access. `a?.b` reads `b` from `a` when `a` is present, and gives the absent value when `a` is absent. The result is always optional: a non-optional member type `U` becomes `U?`, and an optional member type `U?` stays `U?`. The receiver can be an optional reference type or an optional value type (`T?` represented as `Nullable[T]`). When flow analysis has narrowed the receiver to non-optional, `?.` always reads the member, and gives a `redundant-coalesce` warning, because a plain `.` does the same. On a receiver that is never optional, `?.` is an error for a value type (`receiver is not optional`), and is valid for a reference type, as a defensive null test.

```ghul
let p: PERSON? = find(id);
let name = p?.name;              // string?
let length = p?.name?.length;     // int? — chained coalesce
let title = p?.describe();       // string? — method call short-circuits too
```

Method calls work with `?.` in the same way. `a?.foo(args)` calls `foo` when `a` is present, and gives the absent value otherwise. When `a` is absent, the argument expressions are not evaluated. A call to a void method does nothing when the receiver is absent. A function-typed field or property called through `?.` (`a?.callback()`) is not called when the receiver is absent.

The `??` operator is *null-coalescing*. `a ?? b` returns `a` when `a` is present. Otherwise it evaluates and returns `b`. The right operand is evaluated only when needed. `??` is right-associative, so `a ?? b ?? c ?? d` parses as `a ?? (b ?? (c ?? d))`. Each intermediate result is optional until a non-optional fallback ends the chain. The result type is the least upper bound of the left operand's non-optional type and the right operand's type. The result type is optional if and only if the right operand is optional. So a chain that ends with a plain `T` returns `T`, and a chain of optionals returns `T?`. `??` works with all three representations: an optional reference `T?`, an optional value type `T?` (`Nullable[T]`), and `MAYBE[T]` for an unconstrained `T?`. The operands can use different representations. The compiler chooses the result's representation from the least upper bound of the non-optional types, and converts each operand to it. In a condition, `x ?? false` on a `bool?` treats an absent value as false.

`=~` can compare values that may be null, with no narrowing first. The compiler writes the null checks around the call. Two absent values are equal. An absent value and a present value are not equal. `!~` is the negation of the whole result, so `!~` on two absent values is false:

```ghul
let present: THING? = THING(3);
let absent: THING? = null;
let also_absent: THING? = null;

present =~ absent;          // false
absent =~ also_absent;      // true
absent !~ also_absent;      // false
```

*More detail on this section: [narrowing](docs/narrowing.md#optional-types).*

## control flow

See <https://ghul.dev/control-flow.html>. Most control-flow statements contain one or more blocks. Each block is a scope.

An `if` statement is `if` ... `then` ... `fi`, with optional `elif` and `else` clauses. `else` is the last clause, so an `elif` or a second `else` after an `else` is an error. `if` is also an expression. As an expression, every branch must produce a compatible type. An `if` expression with no `else` produces an optional of the branches' type. Its value is present when a branch runs, and absent when no branch runs. A loop expression gives the same absent value when it ends without a value. An `if` expression needs an `else` when the context expects the non-optional type, and when every branch diverges:

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

When an `if` or `while` condition proves a more specific type for a local variable, the compiler gives the variable the more specific type in the branch or loop body. The common cases are an `isa` test for a class or variant, and a `?` presence test on an optional:

```ghul
if isa CAT(a) then
    // a is narrowed to CAT
    write_line(a.purr());
fi
```

For a union with two variants, the `else` branch narrows to the other variant. The same applies to a class hierarchy declared in this assembly without `open`: when the test excludes one direct subclass, the else edge narrows to the other subclasses. If the root class is `abstract`, only its subclasses exist at run time. Then the narrowing can reach one single subclass, and code can use members that only that subclass declares. A concrete root class remains one of the possible types. The narrowing is still sound, but code can use only the members that the root class declares.

Narrowing follows control flow. If a guard rejects a type and then leaves the block with `return`, `throw`, `break` or `continue`, the code after the guard is narrowed too.

Assignment also narrows. When the assigned value's static type is strictly more specific than the variable's declared type, the variable has the more specific type from the assignment onward. This applies to a local variable, a global variable and a top-level `let`. A write to a field or property of a type does not narrow it:

```ghul
let pet: Animal mut = CAT();

pet = DOG();
write_line(pet.bark());   // pet is DOG here
```

*More detail on this section: [narrowing](docs/narrowing.md#type-narrowing).*

### if let

`cast T?(x)` converts `x` to a `T`. When `x` is not a `T`, it gives the absent value and does not throw. A presence test can then check the result. `cast T(x)`, without the `?`, is a checked cast. When `x` is not a `T`, it throws `Ghul.InvalidCastException` at the cast, so a null never reaches a variable whose type says it is never absent. The `cast-may-throw` warning marks such a cast. Two kinds of target type do not throw and still give a value:

- A value type gives that type's default value.
- A type parameter can be either a reference type or a value type, so the cast cannot check it. Inside a generic, `cast T(x)` can still put an absent value in a non-optional variable.

`if let` combines a cast and a presence test in the `if` condition. The condition is a `let`. The then-branch runs only when the value is present. The new variable is narrowed, and in scope, only in the then-branch. A type on the variable makes the condition a type test. `elif let` adds further tests:

```ghul
if let c: CAT = a then
    write_line(c.purr());
elif let d: DOG = a then
    write_line(d.bark());
else
    write_line("some other animal");
fi
```

The tested type can be a value type. On an `object`, `if let i: int = o` matches a boxed `int`. On an `int?`, it matches a present value. On a plain `int` or `long` there is nothing to test, and the type is an error.

With no type, `if let` tests only that the value is present. This is the usual way to use an optional, because the variable has the non-optional type in the branch. The `let` can also destructure:

```ghul
if let line = reader.read_line() then
    write_line("read: {line}");
fi

if let (name, _) = lookup(id) then
    write_line("found {name}");
fi
```

A leaf of a destructure can be a literal: an integer, float, string, character or boolean literal, `null`, or a qualified enum member name. Such a leaf is a test for equality with the value at that position, and declares no variable. The arm runs only when every literal leaf matches, and every named leaf gets its value. The test compares as `=~` does. So a string leaf matches by content, not by identity, and a leaf never matches an absent value at an optional position. A `null` leaf is a presence test, not a comparison, and matches an absent value in all three optional representations. A `case` `when` label makes the same comparison:

```ghul
if let (1, name) = pair then
    write_line("first is one: {name}");
fi

if let (Color.RED, label) = entry then
    write_line("red: {label}");
fi
```

A bare name as a leaf declares a variable, so it always matches and never tests. A leading `~` makes the leaf a test: the value at that position must equal the value that the name already holds:

```ghul
use Colour.RED;

if let (~RED, label) = entry then
    write_line("red: {label}");
fi

if let (~expected, name) = pair then
    write_line("expected: {name}");
fi
```

The compiler reads the marked value at the pattern, so the value does not need to be a constant. A local variable, a parameter and a field all work. A dotted name cannot express these. `~` is valid on any leaf that is a valid value to match. So `~` can be written on a literal or a dotted name, where it has no effect: `(~1, s)` and `(~Colour.RED, s)` match exactly as `(1, s)` and `(Colour.RED, s)` do. A marked leaf counts towards exhaustiveness exactly as the same leaf without `~` does. Marked enum members and booleans can cover their whole set of values. A value from a set too large to list leaves the `case` needing an `else`.

Matching leaves (literal, dotted or marked) are valid only in refutable contexts: `if let`, `while let` and `case` `when` patterns. A plain `let` with a matching leaf is an error, because the test would never run. For the same reason, `~` is an error on a formal argument and on a lambda parameter, where a leaf can only declare a variable. `~` is also an error on a whole destructure group; it is valid only on a leaf.

*Guards* add conditions, after the test, separated by `/\`. The new variable is in scope in each guard:

```ghul
if let c: CAT = animal /\ c.is_friendly then
    write_line("friendly cat: {c.name}");
fi
```

The clause's presence test runs first. If it succeeds, each guard runs in source order, with the narrowed variables. If the test or any guard fails, control goes to the next `elif` or `else` arm. The clause's initializer is everything before the first `/\`, and everything after it is a guard. So a top-level `/\` in an `if let` always separates guards. The other reading would give the initializer the type `bool`, which is never refutable.

One `if let` can have several clauses, separated by commas. The then-arm runs only when every clause's presence test and optional `/\` guard succeed. Each clause's initializer can use the variables of the earlier clauses, so values flow from left to right:

```ghul
if let outer = holder, inner = outer.value then
    write_line("inner: {inner.label}");
fi

if let c: CAT = a, d: DOG = b then
    write_line("a cat and a dog: {c.name} and {d.name}");
fi
```

When any clause's test or guard fails, control goes directly to the next `elif` or `else` arm. The earlier clauses' variables are not in scope there.

When the tested value is a member path, and the variable can have the same name as the last part of the path, `name =` can be omitted. `if let x.y.z` declares `z` and assigns it the value. It tests the path's own optionality, exactly as the full form `if let z = x.y.z` does. `if let path: T` does the same with a type test. The short form works with guards, comma-separated clauses and `while let` exactly as the full form does:

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

The short form needs a path. For a bare optional local, `if x?` narrows the local itself, so no new name is needed.

ghūl has no `match` keyword. Variant tests, narrowing, `if let` and `case` patterns do the same work.

### loops

`while` tests its condition before each iteration. `do` ... `od` is an unconditional loop, which ends at a `break`. `for` iterates over any iterable value: a range, an array, a list or a map. The loop variable has the element type, and can be destructured:

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

Some values are both a sequence and their own iterator, such as a generator. A `for` loop reads such a value through the iterator the value returns, so each loop over the value starts at its beginning. A `for` loop reads a struct iterator, such as a range, directly. Every loop supports `break`, which ends the loop, and `continue`, which goes to the next iteration. A loop disposes nothing that it iterates. For a sequence that holds a resource, see [collections and pipes](#collections-and-pipes).

The range operators work in any expression. `..` includes its start and excludes its end: `0..3` is 0, 1, 2. `::` includes both: `1::5` is 1 to 5. The from-the-end forms (`..<`, `::<`, `..<<`, `::<<`) are for indexing, not iteration (see [arrays](#types-and-literals)).

Any loop (`for`, `while`, `do`) can have a label: an identifier and a colon before the loop. `break` and `continue` can name the label of the loop they act on. So an inner loop can end or continue an outer loop:

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

A `break` or `continue` that names a label of no enclosing loop is a compile error.

### loops as expressions

Every loop form is also an expression, of optional type `T?`. `break E` ends the loop with the value `E`. When the loop ends without a `break E`, because the condition is false or the iterator has no more elements, its value is absent:

```ghul
let found: int? = for x in xs do
    if pred(x) then break x fi;
od;

if let hit: int = found then
    write_line("found {hit}");
fi
```

The loop's type is the least upper bound of the types of all `break E` values, made optional. Ending normally and `break null` give the same result. A bare `break` ends the loop with no value. All three give the absent value:

```ghul
let name: string? = while remaining do
    let line = read_line();

    if !line? then break null fi;      // same as falling off the end
    if is_interesting(line) then break line fi;
od;
```

When the context expects an optional type (a typed `let`, a call argument or a return), the loop's element type comes from the context. Each `break E` expression is then inferred against the non-optional type, like any other expression in that position.

A `break E` gives its value to the innermost enclosing loop *that is used as an expression*. The `break` ends every loop between it and that loop. So one `break` can carry a value out of several nested loops to the loop that produces the value:

```ghul
let hit: (int, int)? =
    for x in rows do
        for y in cols do
            if good(x, y) then break (x, y) fi;
        od;
    od;
```

A `break E` with no enclosing loop used as an expression is a compile error, in the same way as returning a value from a void function.

A loop with a label is a statement. A loop with a `label:` prefix cannot be used as an expression. To exit from deep inside nested control flow with a value, use a parenthesised block and `return` (see [block expressions](#block-expressions)).

A `while` condition narrows the loop body in the same way that an `if` condition narrows its then-arm. In `while xs? /\ i < xs.count do xs[i] …`, `xs` has its non-optional type inside the body. In `while isa CAT(a) do a.purr() od`, the body calls a member that only `CAT` has, with no cast.

`while let` is the loop form of `if let`. The loop runs while the refutable clause matches. The declared names are in scope, with new values, on each iteration. All the `if let` forms work:

- a presence test: `while let line = reader.read_line() do …`
- a type test: `while let c: CAT = a do …`
- a destructure
- `/\` guards: `while let c: CAT = a /\ c.has_whiskers do …`
- several clauses separated by commas: `while let x = a, y = b do …`. Every clause must succeed on each iteration.

The loop ends when any clause's test or guard fails.

### case

`case` chooses an arm by the value of its scrutinee. Each `when` has either a list of expressions to compare for equality (literals, enum members, named constants) or a pattern. `else` matches every other value. The `case` ends with `esac`. Control never falls through from one arm to the next. `then` starts the body of each arm:

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

A `when` with a list of expressions matches its labels by value. `case` compares the scrutinee with each label as `=~` does, and uses `<>` when the type has no `=~`. So a `string` scrutinee, and a scrutinee of a user type that declares `=~`, compare with labels by content, not by identity. An optional scrutinee compares in the same way. `=~` handles null, so a `T?` scrutinee matches a non-null label only when it holds an equal value, and never throws on an absent value. A `when null` label matches an absent value in all three optional representations: a null reference for a reference type `T`, and an absent `Nullable[T]` or `MAYBE[T]` for a value type or generic `T`.

`case` is also an expression. The last expression of each arm's body is the arm's value, and the `case` expression's value is the value of the arm that matched. A `case` expression needs one of these:

- an `else` arm
- arms that cover every value of the scrutinee's closed set: all of a union's variants, both `bool` values, every combination of a destructured tuple, and so on
- an expected type with a default value (a value type or `T?`), when the scrutinee cannot be covered. In this case the `case` gives `default(T)` when no arm matches, and `case-needs-else` gives a warning.

```ghul
let label = case status
when 200 then "ok"
when 500, 501, 502 then "server error"
else "other"
esac;
```

A `when` arm can have a pattern instead of a list of expressions. The patterns are the same as in `if let`:

- `when v: T then` tests the type `T`. When it matches, `v` holds the narrowed value.
- `when (a, b) then` destructures a tuple scrutinee into named variables. Each element can have a type (`when (c: CAT, d: DOG) then`). `_` discards an element. A literal leaf, as in `when (1, label) then` or `when (Color.RED, label) then`, tests that position for equality. A leaf marked with `~`, as in `when (~expected, label) then`, tests the position against the value the name holds, and declares no variable.
- `when _: T then` tests the type only, and declares no variable.

Pattern arms follow the same refutability rules as `if let`. An optional scrutinee gives the pattern its unwrapped value. A value-type pattern on a plain value-type scrutinee has nothing to test. It is an error, reported once, and the pattern's variables get the error type:

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

A bare identifier with no `:` and no `(...)` is an expression. `when v then` tests equality with the value of the variable `v` that is in scope. It does not declare a new local. A pattern that declares a variable must have a `:` or parentheses.

A pattern arm can have a trailing `/\` guard. The guard runs after the pattern matches. The pattern's variables are in scope in the guard and in the arm body:

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

When a guard fails, control goes to the next arm, exactly as when the pattern does not match. An arm with a guard never counts towards exhaustiveness, because it can fail even when its pattern matches. So `non-exhaustive-case` still reports a variant that only guarded arms match.

An arm narrows in the same way as `if let`. `when v: T` narrows the scrutinee to `T` inside the arm body. A test in a guard, such as a `?` presence test or an `isa`, also narrows inside the body. Narrowing in an arm is local to that arm. Nothing that an arm proves applies in another arm, or after the `case`.

### sequence patterns

A pattern in square brackets matches a `List[T]`, an array, or a lazy sequence (see below) by its length and binds its elements by position. It is accepted anywhere a destructure pattern is: `let`, `if let` and `while let`, a `case` arm's `when`, a `for` loop variable, a formal argument, and the left side of an assignment.

```ghul
let [a, b] = pair;                  // exactly two elements
let [first, ..rest] = items;        // one or more: `rest` is the remainder
[x, y] = [y, x];                    // assignment, here swapping two variables

if let [head, ..tail] = items then
    write_line("{head} then {tail.count} more");
fi

describe(xs: List[int]) -> string =>
    case xs
    when [] then "empty"
    when [x] then "one: {x}"
    when [x, ..more] then "{x} and {more.count} more"
    esac
```

`..name` as the last element binds everything after the leading ones. The rest is a `List[T]` view onto the source, not a copy, so a later change to a mutable source shows through it. A bare `..` or `.._` matches the remainder without binding it. Leading elements may be any pattern, nested patterns and `_` discards included. Only a final rest element is supported, and at most one.

Without a rest element the pattern needs exactly that many elements; with one, at least that many. Where the pattern is refutable (`if let`, `while let`, a `case` arm) a mismatch fails the match. Everywhere else it throws `Ghul.AssertFailedException`.

A sequence pattern also matches over a lazy sequence - anything that is an `Iterable[T]` but not a list or an array, such as a pipe or a generator's result. The match pulls elements from the sequence's iterator into locals, and every arm of the matching statement tests against the one pull, so a single-pass source is read once however many arms test it. An exact-length pattern sees one element past its head, to tell "exactly this many" from "at least this many".

A rest element over a lazy sequence is a lazy sequence of its own: the elements the pull took past the ones the pattern matched, followed by what remained of the iterator. The first read continues the pull's iterator, so a source with side effects runs its matched head once per match; every later read takes a fresh iterator from the source and skips the matched elements, so it replays what the first read saw without holding any of it.

A string is a lazy sequence of its chars to a sequence pattern, so `case word when [first, ..rest]` matches its first char and binds the rest as a sequence of chars rather than a string.

A source that is its own iterator is driven through a copy, so a range matches without being consumed. In a `case`, the arms share one pull only for a pattern at the scrutinee itself; a lazy sequence pattern nested deeper in an arm, such as `when (1, [x, ..rest])` or `when [a, ..r]: MY_SEQ`, pulls on its own in each arm that reaches it. A `while let` over a lazy sequence re-reads its scrutinee on every test, as any `while let` does, so `while let [x, ..rest] = cur do cur = rest od` walks a sequence one element at a time.

A `case` over a list is checked for exhaustiveness: `[]` and `[x, ..rest]` together cover every list, and a missing length is reported, as in `missing [_, _, ..]`. A `case` over a lazy sequence is checked the same way.

`..` means a rest element only inside a sequence pattern; a rest element in a tuple pattern is an error. A sequence pattern cannot be a lambda parameter: destructure the argument at the start of the body instead, as in `xs => (let [x, ..r] = xs in x)`.

### block expressions

A parenthesised block `(statement; ...; value)` runs a sequence of statements, and its value is the value of the last one. Use it in any position that accepts an expression: a `let` initializer, a function argument, a `=>` body, and so on.

```ghul
let x = (let y = 5; y * 2);                 // x = 10
let z = (let a = 3; let b = 4; a + b);      // z = 7
let n = (write_line("setup"); 42);          // n = 42

let box = BOX();
let m = (box.v = 7; box.v * 2);             // assignment statement, then the value
```

The compiler decides whether a parenthesised group is a block, a tuple, a parenthesised expression or a lambda's parameter list:

- The group is a block from its first top-level `;`.
- The group is a block from its first token if that token can only start a statement (`let`, `try`, `return`, ...).
- A group that starts with a compound statement (`if`, `case`, `for`, `while`, `do`) is a block when the token after the compound statement cannot continue an expression. So `(for x in xs do f(x) od 0)` is a block whose tail is `0`, with no `;` needed.
- An operator after the compound statement, on the same line, is the exception. An operator can continue an expression, so the group stays an expression, and the compound statement is the operator's left operand. `(if c then 2 else 5 fi - 1)` is 1 when `c` is true.
- This exception applies only on the same line. A compound statement ends its line, so an operator at the start of the next line starts a new statement. `(if c then 2 else 5 fi` / `-1)` is a block whose tail is `-1`, with no `;` needed.
- Otherwise the group is a tuple, a parenthesised expression or a lambda's parameter list.

So `(a = f(x), b = g(y))` constructs a named tuple, and `(a = f(x); b = g(y); a + b)` runs two assignments and gives their sum. The `,` or `;` is the only difference, and the elements can be any expressions in both. A statement that already has an expression form keeps that form. `(let x = 5 in x * 2)` is the `let ... in` expression. `(let x = 5; x * 2)` is a block with a `let` statement and a tail.

A block is also a block for disposal. A `use` or `let use` in a block disposes its value when the block ends, before the block's value is used (see [language details](docs/details.md#variables)).

A common use of a block is to turn a loop into an expression. The loop body updates a `mut` accumulator, and the tail returns the result:

```ghul
let sum_1_to_5 = (
    let acc mut = 0;
    for i in 1..6 do
        acc = acc + i;
    od;
    acc
);
```

If the last statement has no value (a `let`, `for`, `while`, `assert`, ...), the block is void. A void block is valid wherever a void value is valid: as an expression statement, or as the `=>` body of a void function. A position that requires a value (a typed `let` initializer, a function argument, the `=>` body of a function that returns a value) requires a last statement that produces a value. The exception is a body where every reachable path diverges, through `return`, `throw`, or an inner `if`, `case` or `try` that diverges. The last statement is then unreachable, and the block's value comes from the points where it diverges.

`return E` inside a block used as an expression exits the **block**, not the enclosing function. The block's value is the least upper bound of the values of every `return E` in the block and of the tail, if there is one. So an early `return` can exit the block with a value, while another path reaches the tail. A `null` among these values makes the result optional, and does not count as a type:

- The least upper bound of the other values becomes optional. `(let s = f(); return s; null)` with a `string` return is `string?`.
- When every value is `null`, the block has the type that the context expects.
- When every value is `null` and the context expects no type, the block is an error: `all val-block contributions are null`.

Nested blocks follow the innermost rule. A `return` in an inner block exits only the inner block, and the outer block continues.

A block can be the *whole* body of an expression-bodied function, method or lambda (the `=> body`). The innermost rule still applies, so a `return` inside the body exits the block. The block's value is then the function's value, so the behaviour is the same as an `is ... si` body. `try`, `catch` and `finally` work as in any function body, including a `return` inside a `try`: the `finally` runs before the value is returned. A body in which every reachable path returns needs no separate tail:

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
    catch e: Ghul.DivideByZeroException
        return 0;
    finally
        log("done");
    yrt
);
```

A bare `return;`, with no value, is valid in a void block, as in a void function. It exits the block early. In a block that requires a value, it is an error.

`val ... lav` is the old spelling of the same construct. `val statement; ...; value lav` and `(statement; ...; value)` are interchangeable everywhere. `val ... lav` will be removed, so write the parenthesised form.

### exceptions

`throw` raises an exception. An exception must derive from `Ghul.Exception`. Code handles exceptions with `try` ... `yrt`, which has `catch` clauses and an optional `finally` clause. A `catch` names an exception variable and a type. It handles that type and any subtype. `finally` always runs, including before a `return` leaves the `try`:

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

`throw` can also be the whole body of an expression-bodied function, property or indexer. Use this for a placeholder for code that is not written yet:

```ghul
not_done() -> int => throw Ghul.Exception("not implemented");
```

Such a body always diverges, so it is valid for any declared return type: explicit, generic or void. An inferred return type becomes void.

### assert and return

`assert` checks a condition, and throws if the condition is false. The `else` clause is optional. Without it, the exception message contains the source location and the text of the condition.

```ghul
assert index >= 0;
assert index < array.count else "index out of range";
```

A string after `else` gets the source location as a prefix, and is thrown in a `Ghul.AssertFailedException`. A `Ghul.Exception` value after `else` is thrown unchanged. Anything else after `else` is a compile error.

In an expression, `assert cond else "msg" in expr` checks a condition before an expression. It works like `let X in expr`: if the assert fails it throws, and if it passes the value is the inner expression. The condition's narrowing applies in the inner expression, so the inner expression can use the checked value directly:

```ghul
lookup(key: string?) -> int =>
    assert key? else "key is null" in
    table[key];
```

`return value;` returns a value from a function with a block body. `return;` returns from a void function.

### asynchronous code

A function is asynchronous when its declared return type is `Tasks.TASK[T]` (the .NET `Task<T>`) or `Tasks.TASK` (the non-generic `Task`). Inside an asynchronous function, `await e` is an expression. It waits for the task `e` to complete, and its value is the task's result. So `let x = await e;` initializes `x` to the result, and the function then continues:

```ghul
compute() -> Tasks.TASK[int] is
    let a = await double_async(10);
    let b = await add_async(a, 1);
    return b;
si
```

The code reads from top to bottom, although execution suspends at each `await`. `await e;` as a statement waits for the task to complete, and discards any result.

A function declared `-> Tasks.TASK[T]` can `return` a bare `T`. The compiler gives the value to the completed task. When the body has no suspension, the compiler wraps the value as `Tasks.TASK.from_result(...)`. The function can also `return` a task, or any other awaitable value, whose result is a `T`:

- When the body does not `await`, the caller receives that task.
- When the body does `await`, the caller already has the function's own task, and the returned task can only complete it. So the compiler awaits the returned task and uses its result. `return t` and `return await t` then do the same thing.

A void body accepts a returned task whose `await` gives no value, in the same way.

*More detail on this section: [asynchronous code](docs/async.md#asynchronous-code).*

### generators

A function that returns `T{}` (an `Iterable[T]`) and contains `yield` is a *generator*. Each `yield` gives the next element to the consumer and suspends the function. The function resumes at the same point when the consumer asks for another element. The generator produces its elements lazily, so it can produce an unbounded sequence.

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

The pipe combinators chain onto a generator's result with `|>`. Each read of the result runs the body from the beginning, with the arguments of the original call. Two reads in progress at the same time are independent. The first read from the thread that called the generator runs the body in place. Every other read runs a new copy of the body.

`yield in E` yields each element of `E` in turn. `E` is anything a `for` loop can iterate: a pipe, an array, a list or an iterator. The generator takes the elements of `E` one at a time, as the consumer asks for them, exactly as a hand-written loop would. This makes `yield in` the usual form for a recursive generator:

```ghul
preorder[T](tree: Tree[T]) -> T{} is
    if let (value, left, right): Tree.NODE = tree then
        yield value;
        yield in preorder(left);
        yield in preorder(right);
    fi
si
```

The element type of `E` must be assignable to the generator's element type. A value that cannot be iterated is an error, in the same way as a `for` over it.

A bare `return` ends the sequence early, exactly as reaching the end of the body does. It has no value: the declared `Pipe[T]` describes the sequence that the generator produces, and a `return` in the body returns nothing.

A function literal whose body contains `yield` is also a generator. It captures variables as any function literal does: it reads a `let` as the value was when the literal was constructed, and shares a `let mut`. Each read of its result runs the body again, and reads the captured variables again. Its element type comes from the first of these that applies:

1. its declared return type
2. the slot it is assigned to, when that slot expects a `Pipe[T]`, `Iterable[T]` or `Iterator[T]`
3. its first `yield`

A generator literal whose element type none of these decides is an error. A nested named function that yields is also a generator literal. It refers to itself by name for `yield in`:

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

A generator's return type must be `T{}`, `Iterator[T]` or `Ghul.Pipes.Pipe[T]`. `yield` in a function with any other return type is an error. A generator that returns an `Iterator[T]` can be read once: the read uses the iterator that the generator returns. A function cannot be both a generator and asynchronous. As with `await`, `yield` is not yet supported inside a `catch` or `finally` handler.

## collections and pipes

See <https://ghul.dev/functional-programming.html>.

The collection types are:

- `Collections.Iterable[T]`, written `T{}`: any sequence (the .NET `IEnumerable<T>`)
- `Collections.List[T]`: the read-only list trait (the .NET `IReadOnlyList<T>`)
- `Collections.LIST[T]`: the mutable list
- `MAP` and `Map`: the mutable dictionary and its read-only trait, named in the same way as `LIST` and `List`
- `SET`: the mutable hash set. `Set` (the .NET `IReadOnlySet<T>`) is its read-only trait, and `MutableSet` (`ISet<T>`) is its mutable trait.
- `MutableList`, `MutableMap`, `Bag`, `MutableBag` and `STACK`

ghūl has no map literal syntax. To write a map with fixed contents, write a list literal of key and value pairs, and collect it with `collect_map()`. `collect_map()` throws if a key appears twice:

```ghul
let scores = [("alice", 1), ("bob", 2)] |> collect_map();
let total = scores["alice"];
```

To compute a map from a sequence, give `collect_map` a key function and a value function: `words |> collect_map(w => w, w => w.length)`. To create a map that starts empty and is filled later, construct it with no arguments: `MAP()`. The compiler takes its types from how the map is used.

To turn a sequence into a collection, construct the collection from the sequence. `ARRAY(p)`, `LIST(p)` and `SET(p)` take any sequence. `MAP(p)` takes a sequence of key and value pairs, and throws on a repeated key, as `collect_map` does. The element types come from the sequence, so a constructor can end a `|>` chain. `_(p)` constructs the collection type that the context expects:

```ghul
let names = people |> map(p => p.name) |> ARRAY();
let by_name = MAP(people |> map(p => (p.name, p)));
let seen: SET[string] = _(names);
```

To turn a sequence into text, construct a `string` from it. `string(p)` converts each element as `join` does, with nothing between the elements. `string(p, separator)` puts `separator` between each pair of elements. So `word |> reverse() |> string()` is the word reversed, `[1, 2, 3] |> string()` is `123`, and `names |> string(", ")` is the names separated by commas. `$` and interpolation still write a sequence as its elements in brackets.

The sequence combinators are global functions in `Ghul.Pipes`. Each one takes the sequence as its first argument, so the thread-first operator `|>` chains them. ghūl has the usual set of combinators, similar to LINQ. No combinator changes its source. The combinators are of two kinds:

- lazy stages, which return a new sequence: `map`, `filter`, `flat_map`, `skip`, `take`, `cat`, `index`, `zip`, `sort`
- terminals, which read the sequence and produce a value: `reduce`, `sum`, `product`, `collect`, `collect_mutable`, `collect_set`, `collect_map`, `collect_mutable_map`, `count`, `find`, `find_map`, `first`, `only`, `any`, `all`, `each`, `join`, `append_to`

`collect` produces an array, and `collect_mutable` produces a mutable `LIST`. The collecting terminals are function forms of the constructors above, and produce the same result: `collect` and `ARRAY(p)`, `collect_mutable` and `LIST(p)`, `collect_set` and `SET(p)`, `collect_mutable_map` and `MAP(p)`, `join` and `string(p, separator)`. `collect_map` is the exception: it returns the read-only `Map`.

`++` joins two sequences, as `cat` does: `[1, 2] ++ [3] ++ [4, 5]` is the elements 1 to 5 in order. It reads each operand lazily and has the same precedence as `+`. Both operands are sequences, so a single element goes in an array literal: `[x] ++ xs`.

```ghul
let numbers = [1, 2, 3, 4, 5];
let evens = numbers |> filter(x => x % 2 == 0);
let doubled = numbers |> map(x => x * 2);
let total = numbers |> sum();                       // 15
let folded = numbers |> reduce(1, (acc, x) => acc * x);
let odd = numbers |> count(x => x % 2 == 1);        // 3, the elements the predicate accepts
```

`sum` and `product` add or multiply a sequence of any numeric type. They take the element type from the sequence, so neither needs a seed. The sum of an empty sequence is `0`, and the product of an empty sequence is `1`, because addition and multiplication each have an identity value. `min` and `max` are different: they return a `MAYBE[T]`, because an empty sequence has no least or greatest element.

Every read of a pipe starts from the beginning. Two reads in progress at the same time are independent. This is true for every kind of read: `for`, a combinator, a terminal or interpolation. So:

- Two `for x in p` loops each see every element.
- A read that stops part of the way through has no effect on the next read.
- `p |> count()` followed by `p |> only()` reads the whole sequence both times.
- `p |> take(2)` gives the first two elements every time it is read. Use `skip` to read later elements.

The combinators return `T{}`. Each read of a combinator's result reads its source again from the beginning. A terminal does not dispose the iterator it reads, and neither does a `for` loop, whether or not it reads to the end (see below). A generator's `dispose()` releases nothing: it does not run the body's `finally` clauses, and does not dispose an iterator that the body reads with `yield in`. `memo` reads its source once. Every read of a `memo` result replays the cached elements, and asks the source for more elements only after the end of the cache.

A `for` loop does not dispose the sequence it iterates. To dispose a sequence that holds a resource, take its iterator with `use`. Few sequences hold a resource: file and directory enumeration, a database reader, a PLINQ query, and a .NET iterator written with a `using`. Disposal matters when the loop can exit early, because the iterator is then still open.

```ghul
for line in use IO.File.read_lines(path).iterator do
    if line.starts_with(wanted) then
        return line
    fi
od
```

`next` reads one element from an iterator. It advances the iterator and returns the element it reaches, or the absent value at the end. So `next` works as the condition of a `while let` loop: `while let cat: CAT = animals |> next() do ... od` runs until the iterator ends, or until it gives an element that is not a `CAT`.

A pipe can also start from a value instead of a collection:

- `repeat(value)` yields `value` without end.
- `repeat(value, count)` yields `value` `count` times.
- `from(start)` counts up from `start` without end.
- `from(start, step)` counts up from `start` in steps of `step`.

To make a list of a given size, collect a bounded `repeat`:

```ghul
let seen = repeat(false, 100) |> collect_mutable();      // LIST[bool], a hundred of them
let squares = from(1) |> map(n => n * n) |> take(5);  // 1, 4, 9, 16, 25
```

`Ghul.Pipes.stream(initial, advance)` builds a lazy sequence, which can be infinite. `advance` takes the current state and gives the next element and the next state. `advance` can have side effects. It is called lazily, only when an element is needed, so it is much easier to reason about when it has no side effects. The `||` infix operator writes the step: `value || next_state`. A `stream(...)` is an ordinary `Pipe[T]`, so the pipe combinators chain onto it with `|>`. See <https://ghul.dev/functional-programming.html#lazy-sequences>.

The thread-first operator `|>` calls a function with the left value as its first argument. `x |> f(a)` is `f(x, a)`, and `x |> f()` is `f(x)`. The compiler resolves the right-hand side exactly as an ordinary call. So it can be a free function, a method on an explicit receiver (`x |> box.combine(a)` is `box.combine(x, a)`), or a generic function whose type argument is inferred from the left value. Chains associate to the left, so `x |> f(a) |> g(b)` is `g(f(x, a), b)`. `|>` is a plain call. Its right-hand side must be a function call, or the name of a function whose name is an operator:

```ghul
double(x: int) -> int => x * 2;
add(x: int, y: int) -> int => x + y;

let a = 5 |> double();           // double(5) is 10
let b = 5 |> add(3);             // add(5, 3) is 8
let c = 5 |> double() |> add(1); // add(double(5), 1) is 11
```

`|>` and `~>` have their own precedence level, below range and above relational (see [operators](#operators)). So the left operand is everything on the left with higher precedence: `1 + 2 |> double()` is `double(1 + 2)`, and `0..n |> map(f)` maps the whole range. A comparison or a boolean operator is outside the chain. So `xs |> count() > 3` compares the count with 3, and `ready /\ xs |> any(p)` tests `ready` first.

A prefix operator applies to its operand before the chain. So `!xs |> any(p)` negates `xs`, not the result of `any`, and `await t |> f()` is `f(await t)`. `use` works in the same way. `use open(p) |> first()` disposes the value that `open(p)` returns. `use open(p).iterator` disposes the iterator, because member access has higher precedence than any prefix operator. To negate the result of the chain, put the chain in parentheses: `!(xs |> any(p))`.

The left value goes into the last call on the right-hand side. So `x |> box.combine(a)` is `box.combine(x, a)`, and `x |> BOX(1).combine(a)` is `BOX(1).combine(x, a)`. Member access, indexing, `!` and `?` after that call apply to the call's result, as after any call. So `xs |> collect_mutable()[0]` is the first element, and `xs |> collect_mutable().count` is the count. An operator after the call applies to the result of the whole chain, so `xs |> count() % 2` is `count(xs) % 2`.

The right-hand side can omit the argument list only when it is a function whose name is an operator, because the bare name has no other meaning. The left value is then the only argument. An argument list is also valid:

```ghul
$(o: object?) -> string => "<{o}>";

let d = 5 |> $;                  // $(5)
let e = 5 |> $();                // the same call, written out
```

Separate the operator name from `|>` with a space. The scanner reads a sequence of operator characters as one token, so `5 |>$` is one operator named `|>$`, not two operators.

The propagating thread-first operator `~>` is `|>` with absence propagation, in the same way that `?.` is member access with absence propagation. The left value must be optional. When the left value is absent, `~>` does not make the call, does not evaluate the argument expressions (as `?.` does not), and gives the absent value. When the left value is present, `~>` passes its unwrapped value, exactly as `|>` passes a value. The result is always optional. A callee that returns a non-optional `U` gives `U?`, as `?.` does with a member's type. A void callee is not called when the value is absent:

```ghul
parse_port(s: string) -> int?;
clamp_port(n: int) -> int?;
label(n: int) -> string;

let port = text |> trim() |> parse_port() ~> clamp_port() ~> label() ?? "closed";
```

`|>` and `~>` can be mixed in one chain. A `|>` stage always runs. A `~>` stage propagates absence. `~>` works with every kind of optional, including an unconstrained `T?` in a generic. `~>` has the same diagnostics as `?.`:

- A `~>` whose left value is never optional is an error on a value type (`receiver is not optional`). On a reference type it is valid, as a defensive null test.
- When flow analysis has proved the left value present, `~>` gives a `redundant-coalesce` warning.

Inside a generic, the callee receives the unwrapped `T`, and its result is the optional of whatever the callee returns.

A `|>` or `~>` at the end of a line continues the chain on the next line. Use this to wrap a long chain. Only a name can continue the chain this way. If the next line starts with anything else, the operator has no right-hand side, and the compiler reports that error. The compiler never reads the next statement as the call.

*More detail on this section: [language details](docs/details.md#collections-and-pipes).*

### list comprehensions

A list comprehension builds an array from one or more sources. It is written in square brackets: the element expression first, then one or more `for` clauses. Each `for` clause can be followed by `if` clauses:

```ghul
let squares = [x * x for x in 1::5]                  // [1, 4, 9, 16, 25]
let pairs = [(a, b) for a in 1::3 for b in a::3 if a != b]
let lengths = [name.length for name in names if name?]
```

A `for` clause reads its source as a `for` loop does. So any value a loop can iterate is a valid source, and the clause's variable can be destructured (`for (key, value) in map`). Each clause can use the variables of the clauses before it. The element expression can use all the variables. An `if` clause keeps only the elements for which its condition is true, and narrows what it tests. So `name.length` above has `name` as a `string`. Clauses need no separator, so a long comprehension can span several lines.

The result is an array of the element's type, or of the type that the context expects: `let objects: object[] = [x for x in ints]`. The `: T[]` annotation of a list literal also works on a comprehension. The closing bracket ends the comprehension, so pipes work on either side of it: `[x for x in xs |> filter(odd)] |> sum()`. A comprehension builds its whole array before anything reads it, so its source must end. `[n * n for n in from(1)]` never finishes, and gives an `unbounded-comprehension-source` warning. For an unbounded sequence, or one to read lazily, use the lazy form below.

The same clauses in braces make a lazy comprehension. Its result is a `Pipe[T]` of the element's type, not an array:

```ghul
let primes = {n for n in from(2) if is_prime(n)}

primes |> take(10)                                   // the first ten primes
```

A lazy comprehension produces its elements one at a time, as the pipe is read. So its source can be infinite, and elements that are never read are never computed. A lazy comprehension is a generator literal (see [generators](#generators)). So it captures the variables it reads as any function literal does, and each read runs its clauses again. `|>` works with it as with the array form. Inside an interpolated string, `{{` is an escaped brace. So an interpolation that starts with a lazy comprehension needs a space: `"{ {x * 2 for x in xs} }"`.

The loops of a comprehension belong to the comprehension. A `break` or `continue` inside a comprehension cannot leave it. A comprehension cannot contain a `yield`, an `await` or a `try`. A function literal inside a comprehension is a separate body, and these restrictions do not apply to it.

## displaying values

The runtime converts any value to text in two ways:

- `$(value)` gives the text a program shows to its user. String interpolation uses `$` for a value whose type has no text of its own (see [types and literals](#types-and-literals)).
- `inspect(value)` gives the detailed form for a REPL or a debugging session. It has the same structure as `$`, and quotes strings and characters wherever they appear inside a value.

Both accept any value. An absent value is written `null`. `$` needs no `use`. `inspect` is in `Ghul`.

```ghul
use Ghul.inspect

struct POINT(x: int public, y: int public)

$(["one", "two"])                 // [one, two]
inspect(["one", "two"])           // ["one", "two"]
inspect("top")                    // top
$(POINT(3, 4))                    // POINT(x = 3, y = 4)
inspect((1, "one", 'c', true))    // (1, "one", 'c', true)
```

Only `inspect` quotes a string or character, and only inside another value. A string or character passed directly to `inspect` is the whole result, and is written unquoted. `$` and `inspect` write a value by the first of these rules that applies:

1. An absent value is `null`. A `bool` is `true` or `false`.
2. A type that implements `Ghul.Displayable` writes itself (see [language details](docs/details.md#displaying-values)).
3. A tuple is written as its elements in parentheses. A map entry is written as `(key, value)`.
4. A type that declares its own `to_string` is written with that `to_string`, even when it is also a sequence. The runtime's own pipes, and generators, are the exception: their `to_string` writes their elements, and they are written as sequences.
5. A sequence, such as an array, a list or a pipe, is written as its elements in brackets.
6. A class, struct or union variant compiled by ghūl, with no `to_string` of its own, is written as its type and members: `POINT(x = 3, y = 4)`, `Shape.DOT(size = 2)`.
7. A value of a type from another language, with no `to_string` of its own, is written as its .NET type name. Its members are not read, because a property getter can do anything. For example, reading a task's result waits for the task.

A sequence is written up to 100 elements, followed by `, ...]`. So an unbounded pipe can be written. Stopping at 100 elements has no effect on the next read of the value. A value that contains itself is written `<cycle>` where it recurs. The same value in two places is written in full both times.

*More detail on this section: [language details](docs/details.md#displaying-values).*

## generics

See <https://ghul.dev/generics.html>.

Classes, structs, traits, unions, methods and global functions can take type parameters. The type parameters are written in brackets after the name:

```ghul
print_something[T](value: T) => write_line("something is {value}");

struct BOX[T] is
    item: T;
    init(item: T) is self.item = item; si
si
```

Code can do little with a value whose type is an unbounded type parameter. It can store, pass and return the value, compare it with `=~`, and call the methods of `object` on it. A **bound** on the type parameter, `[T: Bound]`, makes the value behave as the bound type, so code can use the bound's members:

```ghul
trait Named is name: string; si

greet[T: Named](x: T) => write_line("hello {x.name}");
```

A type parameter can have several bounds, joined with `/\`: `[T: Named /\ Sized]`. The value then behaves as each bound, so code can use a member of any bound. The type argument must satisfy every bound. A comma declares a separate type parameter; it does not add a second bound.

A bound can also be a **kind**:

- `class`: a reference type
- `struct`: a value type
- `optional`: a type that can be absent
- `init`: a type with an accessible parameterless constructor

Kinds can be combined with each other and with a type bound. They are separated by spaces, and have no parentheses:

```ghul
make[T: init]() -> T;
find[T: class init](key: string) -> T;
build[T: Named class init](name: string) -> T;
build[T: Named /\ Sized class init](name: string) -> T;   // two bounds plus kinds
```

The compiler also enforces the CLR kind constraints of an imported generic (`where T : class`, `struct`, `new()`), when it resolves a type argument.

Type arguments can be written explicitly (`print_something[int](1234)`). Usually the compiler infers them, from these sources:

- the call arguments of a function or method
- the constructor arguments of a generic class, struct or variant
- the context, when the arguments do not decide every type argument: the return type, the type of a `let`, the left side of an assignment, or the parameter that the call is passed to
- how an untyped immutable local initialized with the call is used later in the body
- for a generic function used as a value, the function type of the slot it is assigned to

```ghul
print_something(1234);                       // T inferred as int
let b = BOX("hello");                        // BOX[string]
let r: RESULT[int, string] = RESULT.OK(42);  // OK's arg pins T = int;
                                             // the LHS pins S = string
takes_int(zero_of(1));                       // zero_of[T](n: int) -> T:
                                             // the slot pins T = int
```

When neither the arguments nor any later use decides a type argument, the construction or call is an error: `cannot infer type here`, or `cannot infer the type of` the local that it initializes. Write the type argument explicitly: `BOX[int]()`.

*More detail on this section: [generics](docs/generics.md#generics).*

## type inference

See <https://ghul.dev/type-inference.html>.

ghūl infers types widely, but inference is **function-local**. A namespace-scope function's signature (its parameter types and return type) is always written out, and the compiler infers types only inside bodies. Inside a body, the compiler infers the types of local variables, loop variables, destructured variables, the parameters and return types of function literals and nested named functions, and the type arguments of generic calls.

Inference also uses later code. A variable with no type information at its declaration takes its type from how the same body uses it later. This includes the operations the body performs on the variable and, for a function, its own recursive calls. The compiler narrows local variables, fields and store-free properties (see [narrowing](docs/narrowing.md#type-narrowing) for how long each kind of fact lasts). The inferred type of a `let` variable is never visible outside the function that declares it.

## .NET interop

See <https://ghul.dev/dotnet-integration.html>.

ghūl compiles to .NET IL, and can use most types in any .NET assembly. The compiler converts .NET names to ghūl conventions:

- Method, property and field names become `snake_case`.
- Enum names and enum members become `MACRO_CASE`.
- Class, struct and trait names keep their .NET names, without .NET's generic arity suffix. So `Queue<T>` is `Collections.Queue[T]`.
- The namespace `System.Collections.Generic` is `Collections`, and `System.IO` is `IO`.

Some common types have different names:

- `System.Console` is `IO.Std`.
- `IReadOnlyList<T>` is `Collections.List[T]`.
- `IReadOnlySet<T>` is `Collections.Set[T]`.
- `IEnumerable<T>` is `Collections.Iterable[T]`.
- `IComparable<T>` and `IEquatable<T>` are `Ghul.Comparable[T]` and `Ghul.Equatable[T]`.
- `IComparer<T>` and `IEqualityComparer<T>` are `Collections.Comparer[T]` and `Collections.EqualityComparer[T]`. So the .NET classes `Comparer<T>` and `EqualityComparer<T>` are `Collections.ComparerBase[T]` and `Collections.EqualityComparerBase[T]`.

The dotnet-integration page has the full table of names.

The core types have ghūl names in ghūl namespaces:

- `System.Exception` is `Ghul.Exception`. The common exceptions in `System` are also in `Ghul`: `Ghul.InvalidOperationException`, `Ghul.NotImplementedException`, `Ghul.ArgumentException` and the others.
- `System.Text.StringBuilder` is `Text.STRING_BUILDER`.
- `System.Math` is `Ghul.Math`.
- `System.Random` is `Ghul.RANDOM`.
- `System.StringSplitOptions` and `System.StringComparison` are `Ghul.StringSplitOptions` and `Ghul.StringComparison`.
- `System.Lazy<T>` is `Ghul.LAZY[T]`.
- `System.FlagsAttribute` is `Ghul.FlagsAttribute`.
- `KeyValuePair<K, V>` is `Collections.KEY_VALUE_PAIR[K, V]`.
- `IComparer<T>` and `IEqualityComparer<T>` are `Collections.Comparer[T]` and `Collections.EqualityComparer[T]`, as above.

The old name of each of these types still refers to the same type wherever a type can be named. A `use` of an old name imports the type under that old name. Diagnostics, hover and completion show only the new name.

`Ghul.Equatable[T]` and `Ghul.Comparable[T]` are declared with operators, not named methods. `Ghul.Equatable[T]` requires `=~`, and `Ghul.Comparable[T]` requires `<>`. So a type implements them by defining the operator. Every .NET type that implements these interfaces gets the operator too. This is how `=~` compares a `System.DateTime`, and how the relational operators order a `System.Version`.

```ghul
class BOX: Ghul.Comparable[BOX], Ghul.Equatable[BOX] is
    _v: int;

    init(v: int) is _v = v; si

    <>(other: BOX) -> int => _v - other._v;
    =~(other: BOX) -> bool => _v == other._v;
si
```

The parameter is declared non-optional. The compiler handles presence where the operator is used, so the body receives only present values. On a reference type, an optional parameter is also valid. Use it for a body that checks for a null from a caller in another language, without the compiler reporting the check as redundant. A value type does not have this option, because its `T?` is a different type.

`<>` gives the order of its operands: negative when the left operand is less, zero when neither is less, and positive otherwise. The relational operators use `<>`: `a < b` is `a <> b` compared with zero. So defining `<>` gives a type all four relational operators.

Defining `=~` also decides how .NET compares the type, when `get_hash_code` is also defined. For a type that declares both, the compiler synthesises a matching `Equals(object)`. So the operator runs when the runtime compares values: when the value is a dictionary key, or when a collection searches for it. Without `Equals(object)`, .NET compares a class by reference and a struct field by field, and does not use the operator. An explicit `equals(other: object?)` member replaces the synthesised one.

A type needs both `=~` and `get_hash_code`, because .NET requires equal values to have equal hashes, and a hash-based collection checks the hash first. A type that defines neither is consistent, because it compares and hashes by identity. So a type that defines only `=~` gets an `equality-without-hash` warning, and the compiler does not synthesise `Equals(object)` for it. The compiler does not synthesise the hash, because an operator can ignore some of the fields it reads, and a hash of all the members would then disagree with the operator.

A member `=~` or `<>` must be `pure`: declared `pure`, or provably store-free. Otherwise it is a compile error. The compiler trusts both operators on an operand whose type is known only later, such as a lambda parameter. It also trusts `=~` when a comparison goes through `EqualityComparerBase[T].default` (see [.NET interop in depth](docs/dotnet.md#net-interop)). Nothing at these call sites can check what the implementation does, so an implementation that could store would make this trust unsound. Most bodies are provably store-free with no annotation: comparisons of fields and properties, and calls to another type's `=~` or `<>`. Add `pure` when the body does more than the analysis can follow, such as a loop or a call that the analysis cannot bound. An override of a pure `=~` or `<>` must also be pure, as for any other [pure function](#type-narrowing).

A backtick escapes an identifier that is a ghūl keyword: `` `class `` is the identifier `class`.

A static property or field is `snake_case`, even when it looks like a constant, because only enum members become `MACRO_CASE`. So `CancellationToken.None` is `System.Threading.CancellationToken.none`.

An **indexer** is the one member that code reaches only through its own syntax. .NET does not fix an indexer's name: the property has the name its declaring language chose, and the type names the real one. `System.String` and `Text.STRING_BUILDER` both call theirs `Chars`. Code never writes the name: `[` and `]` find the indexer whatever its name is.

```ghul
let initial = name[0];
```

The accessors of an indexer are not members of their own, so naming one directly is an error.

Code does not reach a **nested** .NET type through its enclosing type. The nested type is in the enclosing type's namespace, with a name that joins the type names with `_`. So `System.Environment.SpecialFolder` is written:

```ghul
let home = System.Environment.get_folder_path(System.Environment_SpecialFolder.USER_PROFILE);
```

A function literal can be passed directly where a .NET **delegate** type is expected. The compiler compiles the literal as that delegate:

```ghul
let xs = Collections.LIST[int]();

xs.sort((a: int, b: int) -> int => b - a);          // System.Comparison[int]

let is_even: System.Predicate[int] = n => n % 2 == 0;
```

The literal's parameter types come from the expected delegate, so they need no annotation. `Func` and `Action` are different: ghūl represents its own function types with them. So a `(int) -> bool` value is a `System.Func<int, bool>` in IL, and passes to a `Func` parameter with no conversion in either direction. Write the ghūl form, `(int) -> bool`, and do not name `Func` directly.

Every other delegate type is a distinct .NET type, not another way to write `(int) -> bool`. So a function **value** stored in a variable is not accepted where such a delegate is expected:

```ghul
let compare = (a: int, b: int) -> int => b - a;     // a function value
xs.sort(compare);                                   // error: not assignable to System.Comparison[int]
```

Declare the variable with the delegate type instead. The variable then holds that delegate from the start:

```ghul
let compare: System.Comparison[int] = (a: int, b: int) -> int => b - a;
xs.sort(compare);
```

Or construct the delegate explicitly from the function value, by calling the delegate type like a constructor:

```ghul
let compare = (a: int, b: int) -> int => b - a;     // a function value
xs.sort(System.Comparison[int](compare));
```

A global function, or a static or instance method, used **by name** is different from a stored function value. The name converts directly wherever a function type *or* a named delegate type is expected, because the compiler uses the method itself, and does not need an existing value to wrap.

```ghul
compare_descending(a: int, b: int) -> int => b - a;

apply(f: (int, int) -> int) -> int => f(3, 5);

apply(compare_descending);                          // ok - no lambda wrapper needed

xs.sort(compare_descending);                        // ok - System.Comparison[int]

let f = compare_descending;                         // f: (int, int) -> int
```

A type used by name where a function type or a named delegate type is expected is its **constructor** as a function value. The expected type's parameter types choose the constructor, as a call's arguments would, and a generic type takes its type arguments from them, or from the expected return type. A constructor has no method a delegate can point at, so the compiler synthesises a function that constructs the type, once for each type it is used at in a function body. The scalar types' converting constructors are values in the same way.

```ghul
class PERSON(name: string public, age: int public) is si

let people = pairs |> map(PERSON);                  // (string, int) -> PERSON
let widened = xs |> map(double);                    // (int) -> double
let boxed = words |> map(BOX);                      // BOX[string], from the element type
let make: (string) -> PERSON = PERSON;              // the one-parameter constructor
```

The compiler resolves an overloaded name against the function or delegate type that the reference must match, in the same way that a call's argument types choose an overload. When there is no such type, an ambiguous name is an error; the compiler does not guess.

A pragma whose name is not a compiler built-in names a .NET **attribute**. The compiler emits the attribute on the declaration that the pragma is written on. That declaration can be a class, trait, struct, union, variant or enum; a function or method; a field or property; or one parameter in the parameter list of a function, method or lambda literal. The short form `Foo` resolves to `FooAttribute` when there is no plain `Foo`. This applies in a `use` as well as in a pragma. So `use System.Obsolete` imports `System.ObsoleteAttribute`, and `use Marker = System.Obsolete` imports it as `Marker`. Attribute arguments can be positional, named (`name = value`), arrays, or `typeof`:

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

*More detail on this section: [.NET interop in depth](docs/dotnet.md#net-interop).*

## compilation targets

See <https://ghul.dev/webassembly.html>.

`--target` chooses the target. `dotnet` is the default, and writes a .NET assembly. `wasm` writes a WebAssembly module that uses the GC proposal, and a JavaScript loader next to it. The module file has the extension `.wasm` (a name with no extension gets it), and the loader has the same name with the extension `.mjs` and finds the module beside it. The loader runs the module under Node.js 22.19 or later on the 22 line, 24.15 or later on the 24 line, or 25 or later. Node 23 cannot run it. `llvm` writes a native executable (see [compilation targets](docs/targets.md#compilation-targets)). The same source builds for each target, and has the same meaning on each. Where the `wasm` target cannot compile something yet, it reports an error; it never compiles the code with a different meaning.

The wasm and llvm targets both behave like a .NET program configured for invariant globalization (`System.Globalization.Invariant`). Strings compare and sort by code unit, and numbers and dates have the same format on every machine. A .NET program gets the same behaviour by setting `<InvariantGlobalization>true</InvariantGlobalization>` in its project.

*More detail on this section: [compilation targets](docs/targets.md#compilation-targets), [conditional compilation](docs/targets.md#conditional-compilation), [foreign functions](docs/targets.md#foreign-functions), [what differs on the wasm target](docs/targets.md#what-differs-on-the-wasm-target).*
