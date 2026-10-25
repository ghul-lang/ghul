# ghūl: language details

Read this file when you need a specific rule. It continues sections of [GHUL.md](../GHUL.md), the language reference, under the same headings. GHUL.md is loaded with every session. This file is not.

## naming conventions

GHUL.md says that a name starting with an underscore is private to the assembly that declares it. Inside that assembly, the rule depends on the kind of declaration. A **member** (a method, field or property) is restricted further, by default to its own declaring class. A **type**, **global function** or **global variable** has no declaring class, so for these the underscore means only "private to this assembly".

A compiler flag sets how far the member restriction reaches:

- `--underscore-access private` (the default): an underscore member is visible only to its declaring class.
- `--underscore-access protected`: an underscore member is visible to its declaring class and its subclasses in the same assembly.
- `--underscore-access legacy`: the old behaviour. The compiler enforces nothing, and emits underscore methods and types as public, so they are visible outside the assembly.

A reference from elsewhere *inside* the assembly that breaks the policy is an error. The compiler still allows the access, so the error does not cause further errors.

An identifier can be written in any script:

- A letter of any script can start an identifier.
- A letter, a digit, a combining mark or a connecting punctuation mark can continue an identifier.

This is the set that C# allows, without the format characters. A zero-width joiner and a bidirectional control are format characters. They render as nothing, so a name that contains one looks like a different name. A format character inside an identifier is an error, and the error names the character. Only the basic multilingual plane is covered. A character above it is written as a surrogate pair, and the scanner reads a surrogate pair as two characters. A symbol is an operator character, and a letter is an identifier character, so no character is both. So an operator spelled `×` and an identifier spelled `naïve` are each what they look like.

The naming conventions use Unicode case. A character that has an upper-case and a lower-case form is checked in any script. So `ТИП` is a concrete class name, and `μέγεθος` is a property name. A character with neither form says nothing about case. So a name written entirely in a script without case, such as Chinese, Japanese, Arabic or Hebrew, is valid for any kind of declaration, and gives no warning.

## namespaces and `use`

The compiler puts the definitions of a source file with no namespace declarations in a namespace that it synthesises, private to that file. This suits small programs and tests. `--global-namespace` instead puts the definitions of every such file into one unnamed global namespace, shared across the project, so a global defined in one file is visible in the others. When a file declares any namespace, every definition in the file must be inside a namespace.

A whole-file namespace (`namespace N` with no `is` ... `si` body) is one instance of its namespace like a namespace block is: instances of the same name across files combine. It must be the first declaration in the file, after any `@@` pragmas, and cannot be nested inside another namespace. A file with a whole-file namespace can carry top-level statements; a file with a namespace block cannot.

The compiler collects a file's top-level statements into a synthesised entry-point function.

- The entry point has the two signatures that the runtime can give an entry point (see [functions](../GHUL.md#functions)). The statements can read the command-line arguments as `args` and the process environment as `env`. A private `_entry(args: string[])` wrapper passes them in.
- `args` and `env` are the entry point's own parameters. So a `let` that declares a global variable named `args` or `env` is an error. Use another name. A `let` of either name inside a nested block among the statements is an ordinary local, and hides the parameter as anywhere else.

A `let` among the top-level statements declares a global variable:

- The top-level statements after the `let` can read it, and so can the functions and types that the file defines below it.
- Its type is inferred exactly as a local variable's type is.
- A bare `let` cannot be assigned anywhere. A `let ... mut` can be reassigned by later top-level statements and by functions, so it is shared state.
- A `let` among the top-level statements is a statement, so it is in scope from where it is written and not before. Reading or assigning it above its `let` is an error. This applies to another top-level statement, to a function literal written in one, to the `let`'s own initializer, and to the body of a function or type that the file defines above it. The statements run in order, so above the `let` the value does not exist yet. A reader written below the `let` is meant to see it.
- This rule is about where the name is written. It does not guarantee when the code runs: a function written below the `let` can still be called from above it. The rule is the same for every reader, and it states what the `let` is for.
- For state that the whole file should see, in any order, use a namespace-scope declaration (`count: int;`). A declaration is a definition, not a statement, so it has no position to be read above.
- A `let` inside a nested block among the top-level statements is an ordinary local of that block.
- A top-level `let` shares the file's namespace with the file's other definitions. So a top-level `let` and a global function, global variable or type with the same name is a redefinition error.

The synthesised entry point is a file-private definition like any other. So more than one file in a project can have top-level statements, for example in a project that collects a directory of one-file examples. Only one of them can be the program's entry point. The compiler chooses the entry point by the usual rules, in this order:

1. a function with an `@entry` pragma
2. a function that the `--entry` name matches (`entry` when the flag is not given)
3. a file's top-level statements

Naming an entry point with `--entry` excludes top-level statements completely, because a build that asks for an entry point by name does not want statements from another file instead.

The run-time checks that a `--submission` build adds (see [sessions and submissions](sessions.md#namespaces-and-use)) report what went wrong. They do not make the earlier step correct. The earlier step's compiled code still assumes the hierarchy that it was compiled against. To make it correct again, run that step again against the hierarchy as it is now.

Each file whose top-level statements are not chosen gets a `top-level-statements-not-run` warning at its first statement. The statements do not run, so a `let` among them is never initialized. In a project that intends several script files in one build, suppress the warning with `--suppress top-level-statements-not-run`, or make it a hint with `--warn-as-hint`. When several files have top-level statements and nothing names an entry point, the compiler chooses none. Every one of those files gets the warning, and an executable build reports that it has no entry point.

An ordinary pragma applies to the one definition or statement after it. So it cannot reach a warning reported at a top-level statement, because no definition contains the statement. `@@pragma(...)`, with a doubled `@`, is a **file-level** pragma. File-level pragmas are written before everything else in the file, and cover the whole file, not one definition:

- `@@suppress("slug")` covers every diagnostic in the file, including those at top-level statements.
- `@@precedence(...)` sets an operator's precedence for the rest of the file's parse. Unlike the per-definition `@precedence`, it is not restored at the end.
- `@@IF.<name>()` leaves the whole file out of the build when `<name>` is off, both definitions and top-level statements. A source shared between targets uses this to keep a file to one target (`@@IF.dotnet()`, `@@IF.wasm()`, `@@IF.source_core()`).

A `@@` pragma anywhere except the very start of the file, such as after a `use`, a definition or a top-level statement, is an error:

```ghul
@@suppress("top-level-statements-not-run")

use IO.Std.write_line;

write_line("hello");
```

A file's first two bytes can be `#!`, starting a line in the style of a Linux shebang that names an interpreter. The compiler recognises this line only as the very first thing in the file, and skips it, so a file with one still compiles. Parsing ignores the line completely, including the rule that a file-level `@@` pragma must be the first thing in the file. So write a `@@` pragma directly after the shebang line.

`use X.*` imports every usable member of `X` at once. `X` is a namespace, a class, a struct, a union or an enum:

- On a namespace, it is the same import as `use X;`, because a namespace's members are visible without qualification either way.
- On a class, struct or union, it imports every static field, property, method and operator. On a union it also imports every variant. It never imports instance members or constructors, because neither means anything without a receiver.
- On an enum, it imports every member.

Each name comes into scope exactly as if it were imported by its own `use`. So a name that a wildcard import collides with gives the ordinary duplicate-use error:

```ghul
use Collections.*;               // every public symbol in the namespace - same as `use Collections;`
use MATH_CONSTANTS.*;            // every static member of a class
use Suit.*;                      // every member of an enum
use Result.*;                    // every variant (and static member) of a union
```

An alias cannot name a wildcard import. `use name = X.*;` is an error, because a wildcard stands for several imports, not one value that a name could refer to.

One namespace cannot be named at all. `Ghul.Internal` holds the attributes that carry language facts from the compiled assembly to the assembly that reads it, such as whether a class is closed, or which variant of a union a type is. These attributes record what the compiler established, not something a program chooses. So naming one from source reports that the symbol is not found, and completion offers none of them. The assembly that declares them sees its own declarations as ordinary symbols.

A type alias is another name for the type it names, not a type of its own. So the alias and the type are interchangeable in both directions. A `(index: int, value: string)` value is an `IndexedString`, and an `IndexedString` is accepted wherever the tuple type is. This holds for every kind of aliased type, so nothing that accepts the aliased type needs to know about the alias.

Constructing through an alias constructs the aliased type, so `Numbers()` builds a `Collections.LIST[int]`. A generic alias is constructed with its type arguments written, `StringMap[int]()`. The type arguments can be left off only when the alias passes its own type parameters directly to a class, as `use Box[T] = BOX[T]` does. Then `Box(42)` infers them as `BOX(42)` would. A tuple has no constructor, so an alias of a tuple has none either.

An alias can have type parameters, which its aliased type uses like any other type parameters:

```ghul
use Pair[A, B] = (first: A, second: B);
use StringMap[V] = Collections.MAP[string, V];

swap[A, B](p: Pair[A, B]) -> Pair[B, A] => (first = p.second, second = p.first);
```

`StringMap` names `MAP` with its first type argument supplied. Nothing else in the language can express this. Aliases can be defined in terms of each other (`use IntPair = Pair[int, int];`), in any order, because the compiler resolves an alias where it is first used, not where it is written.

An alias is transparent, so it cannot be defined in terms of itself, directly or through other aliases, because the type would have no end. Such a definition is an error. A type that refers to itself must be a `class` or a `union`, which are types of their own.

An alias has the same scope as any other `use`. It belongs to the namespace block that contains it, and another block that wants the same alias must declare it again. Callers are not affected, because a signature written with an alias is a signature in the aliased type.

GHUL.md describes `use default`. Importing a name that the set already includes adds nothing, and is not a duplicate. So `use default` together with `use Ghul.Pipes` is valid. A function of your own with the same name as a function in the set joins it in one overload group, and the compiler resolves each call against both:

- When your function fits the arguments as well as an imported generic function does, and each of its parameters is at least as specific, your function is chosen.
- The imported function is chosen when it fits better, or when your parameter is a catch-all type such as `object`.

To make every call use your own function, leave that name out of the imports, by replacing `use default` with the specific `use` statements that the file needs. Or give your function a different name.

`--default-use` replaces the set with a project's own set. It takes a comma-separated list, and can be given more than once. Naming any name at all leaves the default set out completely. So a project that wants only the collections asks for only the collections. A project built by MSBuild names them in one property: `<GhulDefaultUses>Collections;IO.Std.write_line</GhulDefaultUses>`.

`--implicit-default-use` gives every file that declares no namespace an implicit `use default`, after the file's pragmas and before everything else. A one-file script run directly uses this to get `write_line`, the pipes and the collections without importing them. A file that declares a namespace gets no implicit import, because its namespace blocks choose their own imports. An explicit `use default` in the file as well is harmless. A function that the file defines joins a function of the same name from the set, as with an explicit `use default`.

## comments

A doc comment block is the sequence of `///` lines that ends on the line directly above the declaration. When the declaration has pragmas, the block ends directly above the first pragma. A blank line, another comment or any code in between means the block documents nothing. Classes, structs, traits, unions and their variants, enums and their members, functions, methods, properties and global variables can have a doc comment. A member added in a `partial` or `impl` block can have one, like any other member.

The text is Markdown. The compiler removes each line's `///` and one following space, and shows the rest as written. So a `///` line with nothing else on it is a paragraph break. Describe arguments in a bullet list, with one `- name: description` line for each argument. A comment that starts with four or more slashes is an ordinary comment, so a row of slashes can be used as a divider.

## statement terminators

`--warn redundant-semicolon` reports each `;` at the end of a line. Use it in a project that is removing its terminators. It is off by default. When it is on, `--warn-as-error` and the other severity flags apply to it like any other slug. `--inlay terminator` shows the inferred boundaries as editor inlay hints: a `∘︎` wherever a statement ends without a written `;`. These are exactly the places where `redundant-semicolon` would report a `;`. It is also off by default.

## variables

A `mut` variable cannot change type after it has a type.

A bare `let` and a `let ... mut` can both take their value from `_`, the default-value expression:

- `let i = _` takes its type from the local's own annotation or from later use. `_[T]` gives the type explicitly.
- A bare `_` as a call argument takes the parameter type from the callee, when the call resolves to a single overload. If the parameter has a declared .NET default value, `_` takes that value, not the type's zero value. So passing `_` by position behaves exactly like omitting the same argument by name.
- For a `T ref` parameter, `_` discards what the callee writes. The callee receives the address of a new local that holds the default of `T`. So `System.Version.try_parse("1.2", _)` tests the text without keeping the result.
- A `_` argument is never used to infer a generic type parameter. A type parameter that only the `_` argument could decide is an error (`cannot infer type of default here`), and so is a call that stays ambiguous between overloads.
- `_[T]` always means the zero value of `T`, in every position. It never takes a callee's declared default.

`_(...)`, with an argument list, *constructs* the type that the context expects, instead of giving its zero value. So code can build a value without writing its type a second time:

```ghul
let xs: LIST[int] = _();
let b: BOX[int] = _(42);
```

The type comes from the same places as for a bare `_`: the annotation on a `let`, the left side of an assignment, or the parameter type of a call argument. An untyped immutable `let` initialized with `_()` takes its type from how the local is used later in the body, as a local initialized with `[]` does. So `let result = _()` followed by `return result` builds the declared return type. An optional context is unwrapped first: `let b: BOX? = _(1)` constructs a `BOX`, which then widens to the optional. With nothing to infer the type from, `_(...)` is an error (`cannot infer the type to construct here`). `_[T](...)` is not valid, because `T(...)` already does the same with the type written.

`use E` evaluates `E`, and disposes the value when the innermost enclosing block ends, on every path out of the block, including an exception. The value of `use E` is the value of `E`, so `use E` can be written wherever `E` can: as an initializer, an argument or an operand. The value's type must be `Ghul.Disposable`. An absent value is not disposed. Values are disposed in the reverse of the order in which their `use` ran:

```ghul
let file = use IO.File.open_read(path)
let reader = use IO.StreamReader(file)

return reader.read_line()
```

`use` disposes the value it evaluated. So reassigning a `mut` local initialized from a `use` does not change what is disposed. Inside a body, a statement can start with `use`: `use R()` alone holds a value for the rest of the block. At file or namespace level, a `use` is an import, so a top-level statement that starts with the operator is written in parentheses: `(use E)`. Disposal belongs to the block, not to the expression. So `for x in use f().iterator do ... od` disposes the iterator when the block that contains the loop ends, not when the loop ends. `return use E` returns a value that is already disposed.

`let use x = E` is the old spelling of `let x = use E`. It cannot be combined with `mut`.

`let use ... in` is the expression form. The local is disposed when the statement that contains the expression has run. In an expression-bodied function, the local is disposed when the body has been evaluated. So the form works where a block does not:

```ghul
first_line(path: string) -> string? =>
    (let use lines = IO.File.read_lines(path).iterator in cursor(lines) |> first())
```

In the expression body of an asynchronous function that awaits, there is no point at which to dispose the local, so the form is an error there.

## types and literals

For `cast(v)` with no target type (see [GHUL.md](../GHUL.md#types-and-literals)), the target type comes from the declaration that the expression resolves against, not from any other operand. So a `cast(v)` in an argument or operand position takes the type of the parameter it fills. Resolution must therefore reach exactly one candidate. `cast(v)` is an error where the position supplies no type at all, and where more than one overload or operator would accept it. So `cast(a) + cast(b)` is an error, and the compiler does not guess. So is a call whose overloads differ only in the parameter that the `cast(v)` fills. Hover over the `cast` keyword shows the type that the cast resolved to.

A cast that is called supplies its own target type. The arguments give the parameter types, and the context gives the return type. So the target is the function type that the call describes.

```ghul
let handler: object = read_handler();

let result: int = cast(handler)(4);    // handler converts to int -> int
```

A target in parentheses has two possible meanings, and what the name in it refers to decides which:

- `cast (T)(v)` converts `v` to `T` when `T` names a type.
- When `T` does not name a type, `cast (T)(v)` casts the value `T` and calls the result.

A target that can only be a type, such as a tuple type or a function type, always has the first meaning, because a value of such a type cannot be called.

```ghul
let widened = cast (double)(count);    // a type: count converts to double
let called = cast (handler)(count);    // a value: handler is cast, then called
```

A pipe declares its own `to_string`, which writes its elements in brackets, the same text that `$` gives it. A type's own `to_string` is always used first. So to change how a value is interpolated, give its type a `to_string`.

A sequence of octal digits after a `\` is the old way to write a character code (`"\33"` for an escape character). It still works, and has the same meaning, but it is deprecated. It takes as many digits as follow it, so it also takes any digits after it that were meant as text. It gives a `deprecated-octal-escape` warning. Write `\u` instead.

## functions

A bare name in call position (`foo(args)`) normally resolves to the nearest enclosing declaration of that name, as any other reference does. When that declaration cannot be called (a local variable, field or property that holds no function), and an enclosing scope has a function or a function-typed value with the same name, the call goes to that function instead. The call site gets a `shadowed-non-callable` warning:

```ghul
tally(xs: int[]) -> int => xs.count;

use_tally(xs: int[]) is
    let tally = tally(xs);   // warns, then calls the function above
    write_line("{tally}");
si
```

A bare name with type arguments (`foo[int]`, whether or not it is called) follows the same rule, because a name with type arguments can only mean a type or a function.

This fallback applies only when the nearest declaration cannot be called at all. A function whose overloads do not accept the arguments still gives the ordinary argument-mismatch error, and the compiler does not look further. A name that refers to itself from inside a function literal in its own initializer is still reported as a reference to a value that does not exist yet. This differs from the direct case above:

```ghul
let f = (x: int) -> int => f(x);   // error: variable is not defined here
```

## classes

An `@equality()` pragma before a class asks the compiler to synthesise the class's `=~` and a matching `get_hash_code`. They compare the members that hold the class's state: each auto-property and each `field`, in order, with that member type's own equality. A property with a body computes its value from the state, so it does not take part. A static member belongs to the type, so it does not take part either. Non-public members take part like any other members. The pragma is the author's request for the comparison, so a member's visibility says nothing about whether it distinguishes two values.

Two values are equal only when they have the same runtime type. So a base class value and a subclass value are never equal, in either order, and the relation is symmetric.

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

The pragma applies only to the class that it is written on. So each class in a hierarchy requests its own. An abstract class with no state of its own can request it too. This makes a comparison written against the base type resolve: `a =~ b` on two `Shape` variables dispatches to the subclass that the values actually are, and each subclass compares what it adds to its base class.

A synthesised operator serves only the class that it was synthesised for. It accepts operands of exactly that runtime type, and reads only that class's members. So a subclass of a class that has a synthesised operator must supply its own, either by requesting one with `@equality()` or by declaring `=~` and `get_hash_code`. A subclass that does neither is an error. This applies however little the subclass adds. The rule is the same for every subclass, so that every class in a hierarchy states its own equality, and the obligation never depends on whether the subclass declares a field. A subclass whose base class declares equality by hand is not affected, because the author of the base class is responsible for what they wrote.

The synthesised pair also decides how .NET compares the value, through the `Equals` bridge. So a class that requests equality becomes a dictionary key that finds an equal value, not only the same object. A class used as a key that must compare by identity in a `MAP` or a `SET` does not request equality.

Requesting equality on a class that already declares `=~`, `<>`, `get_hash_code`, or an `equals` that takes an `object`, is an error, because the request contradicts what is declared. Requesting it on an `open` class is also an error. Enforcing the subclass rule above needs every subclass to be visible, and another assembly can extend an `open` class.

A **static constructor**, `init() static`, runs once, before the type is first used, to initialise its static state. It takes no parameters and has no `self`. The runtime calls it; code never calls it directly. A class or struct can declare one as well as its instance constructors:

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

GHUL.md says that a method with no body is abstract. One case cannot be abstract: a method with no body that overrides a **class** method that has a body. A caller that holds the base type would still reach the override. So the compiler synthesises a body that throws `Ghul.NotImplementedException`, naming the method, so that the call does what the declaration says. This method is not a contract, so subclasses do not have to implement it. A trait's default is not this case. A class that declares a trait member again with no body removes the default, as GHUL.md describes, and the new declaration is a contract like any other.

## structs

The compiler synthesises a struct's `=~` and `get_hash_code` (see [structs](../GHUL.md#structs)) only when two conditions hold.

The first condition: the struct declares no part of the pair. Declaring any one of `=~`, `<>`, `get_hash_code`, or an `equals` that takes an `object`, opts the struct out of both. The compiler looks only at the struct's own members. So a global `=~` declared for the struct does not opt it out. The compiler still synthesises the operator, and where both exist, the member operator is used. To give a struct equality that differs from the member-by-member result, declare it on the struct itself, which opts out of synthesis. A hand-written `=~` is the author's own definition. A hand-written hash next to a synthesised operator could disagree with it, and the two must agree.

The second condition: every member that holds state is public. Private state is an implementation detail, and only its author knows whether it takes part in equality. Comparing only the public members would report two values as equal when a private member distinguishes them. So a struct with any non-public state has no synthesised `=~`, and has no `=~` until one is declared. `protected` counts as non-public here.

A synthesised `=~` also decides how .NET compares the value, through the same `Equals` bridge that a declared operator gets. So such a struct works as a dictionary key. The hash reads what the comparison reads:

- A member that is compared element by element adds its count to the hash, because two equal sequences are different objects.
- A member whose comparison is finer than its hash adds nothing to the hash, so that equal values never have different hashes.

See [equality](../GHUL.md#equality).

A function literal inside a struct's instance member cannot read `self` or any of the struct's instance members. Such a read is an error at the read. A literal becomes a delegate, and a delegate's target is an object. A struct's instance member holds `self` as a pointer to the value, not as a reference to an object, so the literal has nothing to capture. Copy what the literal needs into a local first. The literal then captures the local, as it captures any other local:

```ghul
struct SCALER(factor: int) is
    scale(xs: List[int]) -> Pipe[int] is
        let by = factor

        return xs |> map(x => x * by)
    si
si
```

Static members are not affected, because they have no `self`. A struct reached through anything other than `self` is not affected either. A local, a parameter, or a field of another object is an ordinary value, and the literal captures it.

## traits

Inheriting two *concrete* defaults for the same member from different traits is an error. The compiler does not choose one. So the implementing type must resolve the diamond by overriding the member.

Like a class, a trait is closed to other assemblies unless it has the postfix `open` modifier. A closed trait can be implemented, and derived from, only in the assembly that declares it. Implementing or deriving from it anywhere else is a compile error. `open` allows other assemblies to extend the trait. Use it when a trait exists to be implemented by other code:

```ghul
trait Displayable open is
    display(state: DISPLAY_STATE);
si
```

Inside the declaring assembly, nothing changes: a closed trait is implemented and derived from exactly as an open trait is. A trait imported from an assembly built before closed traits existed is treated as open.

An override or trait implementation can narrow its return type to a subtype of the overridden member's return type, as `make() -> CIRCLE` narrows `make() -> SHAPE`. It is still the override. So a caller that holds the base class or the trait calls it, and a caller that holds the narrower type gets the narrower return type. Only a reference type can narrow in this way. A value type in place of a reference type is a different representation, not a narrower type. A trait member's implementation with any other return type is an error at the member.

A class member with the same name and arguments as a member it inherits from another class, but with a return type that is neither the same nor narrower, does not override the inherited member. It hides it. The new member has its own slot. A caller that holds the subclass calls the subclass's member. A caller that holds the base class calls the base class's member, even for an instance of the subclass. This looks like an override and is not one, so it gives a `hides-inherited` warning, which can be suppressed on the member. A task with a result is the case that hiding exists for, in the same way that .NET's `Task<TResult>` hides the awaiter of `Task`:

```ghul
class TASK is
    get_awaiter() -> TASK_AWAITER => TASK_AWAITER(self)
si

class TASK[T]: TASK is
    @suppress("hides-inherited")
    get_awaiter() -> TASK_AWAITER[T] => TASK_AWAITER[T](self)
si
```

Awaiting a `TASK[int]` gives its `int`. Awaiting the same task through a `TASK` uses the base class's awaiter, which waits for the task and discards the result, as on .NET. `super.get_awaiter()` calls the hidden member.

An override or trait implementation must keep the overridden member's optionality contract. It can strengthen the contract: a non-optional return type or property where the base member is optional, or an optional parameter where the base member's parameter is non-optional. Weakening the contract in either position is a compile error:

- Returning `T?` where the base member promises `T` would give null to callers that use the base type.
- Requiring a non-optional parameter where the base member accepts `T?` would receive null from those callers.

A property with an assign accessor is both an input and an output, so its type's optionality must match the base exactly. The equality and order operators `=~` and `<>` are the one exception for parameters. The compiler handles presence where the operator is used, and the body receives only present values. So an implementation can declare its parameter non-optional even where the overridden member declares it optional.

## unions

Exhaustiveness checking also works through a destructure. A scrutinee that can be destructured, such as a tuple or any type with a `deconstruct`, is covered when the arms cover every *combination* of values of its elements. This works as long as each element has a closed set of values of its own. The same rule applies again to a nested destructure. So four arms cover a `(bool, bool)` with no `else`. Two arms cover it when each arm leaves one element unmatched. Coverage counts combinations, not each element separately. So `when (true, _)` and `when (_, true)` together do not cover `(false, false)`. An element whose values cannot be listed (`int`, `string`, an open class hierarchy) means the whole scrutinee is not covered. So does a field that the arms only test and do not assign to a variable: `when (0): WHOLE` covers part of `WHOLE`, not all of it.

A field whose type is declared in ghūl source, and could declare `=~` but does not, gives a `synthesized-equality-fallback` warning on the field's declaration. The union's structural equality then compares that field with the default equality comparer, not with an operator. Types that cannot declare an operator fall back with no warning: imported types, tuples, sets, maps and function types. An array or a list never falls back, because it compares element by element. Suppress the warning with `@suppress("synthesized-equality-fallback")` on a declaration or a file, or with `--suppress synthesized-equality-fallback` for the whole project.

A union can declare the traits it implements after its header, with a leading `:`, and after any primary-constructor parameters:

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

The property synthesised from the union's `name` primary parameter implements `NAMED.name`. Every variant inherits `NAMED.label`. A `NAMED` reference accepts any `COLOUR` value, and calls dispatch through the union's base class. A union can declare only traits after the `:`. It cannot declare a base class. Every trait member used through this header form must have a default, or must be a property that the union already supplies, usually through a primary parameter. This is because neither the union body nor its variants can contain method bodies. To give a union method implementations for a trait, use an [`impl` block](../GHUL.md#partial-and-impl-blocks).

A method or property accessor added to a union, or to one of its variants, through a [`partial` or `impl`](../GHUL.md#partial-and-impl-blocks) block must be pure: declared `pure`, or provably store-free. One that stores gives an `impure-union-method` warning.

## enums

An enum marked `@Ghul.Flags()` also has the bitwise operators `&`, `|`, `^` and the unary `\`, for combining and testing flag values. The attribute is `Ghul.FlagsAttribute`, which is .NET's `System.FlagsAttribute` under its ghūl name, so `@System.Flags()` also works. Each operator takes and returns the enum's own type. There is no conversion to or from the underlying integer. Combining values of two different enum types is a compile error, the ordinary overload-resolution failure. An enum without the attribute has none of the four operators, because the members of an ordinal enum are not meant to be combined. So `Suit.SPADES & Suit.HEARTS` is an error, like any other undefined operator.

```ghul
@Ghul.Flags()
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

This is different from C#. In C#, `[Flags]` does not change which operators an enum has, because `&`, `|`, `^` and `~` are built into the language for every enum. In ghūl, `Ghul.Flags` enables the four operators. It also has its usual effect on `to_string()`, exactly as in C#: the default text of a combined value lists its member names (`READ, WRITE`) instead of the number. ghūl cannot name a combined value as a member (`ALL = A | B | C`), because an enum member's initializer must be a plain integer literal.

## partial and impl blocks

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

A `partial` block has no interface clause. A type's interfaces are declared in its header. `partial` applies to classes, structs and unions. A union's body contains only variants, so `partial` is the only way to give a union methods.

An `impl` block also makes the target type implement an interface:

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

The interface's type parameters are the target's own, written on the target after `for` (`impl Printer for List[T]`). Inside the body, `self` has the concrete target type, so code can match a union's variants directly. The target then implements the interface exactly as if the header declared it: a `List[T]` is accepted wherever a `Printer` is expected, and calls dispatch through the type's base class. An interface that relates a type to itself takes the target as its type argument: `impl Eq[List[T]] for List[T]`. The interface must be a trait. The target must be a type in the same assembly, because an imported type cannot be reopened. When the target is a union or a single variant, every method and property accessor in the block must be pure (see [unions](../GHUL.md#unions)).

The target of an `impl` block, and of a `partial` block, can be a qualified name: a type in a namespace (`impl Printer for Some.Namespace.TYPE`) or one union variant (`impl Printer for List.NIL`). Implementing an interface on one variant attaches it to that variant only. A value whose static type is the variant implements the interface. The union as a whole does not, unless it also implements the interface.

Inside the block, the target's own members, inherited members and type parameters are in scope first, exactly as inside the target's declaration body. Every other name resolves where the block is written: in the block's enclosing namespace and that namespace's `use` imports. This includes the target name after `for`, the interface name, the types in member headers and every name in the bodies. Names that are in scope only where the target is declared (the target's namespace siblings, and the imports of the target's own file) are not visible, unless they are also visible where the block is written. Declaration order does not matter. The block can come before its target in the same file, or be in a file compiled earlier.

## operators

These rules add to GHUL.md's precedence table. The thread-first row lists two operators, not a first character (see [collections and pipes](../GHUL.md#collections-and-pipes)). An operator that starts with `?` has lower precedence than every level in the table. Every operator that the table does not list has precedence between shift and bitwise. Operators are left-associative, except an operator that starts with `?`, which is right-associative, so that a chain of such operators stays open to the next operator.

When the first character does not give the precedence you want, a `@precedence` pragma sets it explicitly. The pragma takes the operator and a level. The level is one of the eight levels `user-1` to `user-8`, which fall between the levels of the table, or one of the table's levels by name. The pragma before a definition covers that definition. The file-level `@@precedence` covers the rest of the file.

```ghul
@@precedence("∘", "user-8")

∘(f: (int) -> int, g: (int) -> int) -> (int) -> int => x => f(g(x));
```

An operator is an ordinary function, so its name is a value wherever a function of its type is expected. The name is written with the backtick escape, because an operator is not an identifier:

```ghul
struct N(v: int public);

⊕(a: N, b: N) -> N => N(a.v + b.v);

let totals = values |> reduce(N(0), `⊕);
```

A static member operator is named through its type, in the same way:

```ghul
struct V(x: int public) is
    +(a: V, b: V) -> V static pure => V(a.x + b.x)
si

let total = vectors |> reduce(V(0), V.`+);
```

A built-in operator is named the same way. It has no method behind it, so the compiler synthesises one that applies the operator to its parameters, shared by every use of the operator at that type in the function body, and the delegate over it is built once. A bare spelling found in no scope is the operator of the type the expected function type applies it to: the first parameter type, or that parameter's element type where it is a tuple, as it is for a combinator that takes an argument pack as one tuple.

```ghul
let total = xs |> reduce(0, `+);                     // int.`+
let sums = [(1, 2), (3, 4)] |> map(`+);             // 3, 7
let scaled = zip(xs, ys, `*);
let compare: System.Comparison[int] = `<>;
```

A built-in operator that mentions a type parameter of the enclosing function is a value at that type too, under the same rules as applying it in the body: `` `== `` is a `(T, T) -> bool` inside `same[T]`. A spelling that is derived from another operator - `<`, `<=`, `>` and `>=` from `<>`, `!=` from `==`, `!~` from `=~` - names no function.

## collections and pipes

GHUL.md describes how to dispose a sequence that holds a resource, by taking its iterator with `use`. `cursor` builds a pipe over the held iterator. `cursor` reads the iterator it is given, and does not ask the source for a new one. So an early-exit terminal on the pipe leaves the disposal to `use`:

```ghul
return cursor(use IO.File.read_lines(path).iterator) |> skip(wanted - 1) |> first()
```

The `undisposed-source` warning reports a read that can stop before the end of a resource-holding source when nothing holds the source. Such a read is an early-exit terminal or stage, such as `first`, `find`, `any`, `all`, `only` or `take`, or a `for` loop whose body can `break` out of the loop or `return`. The call to the source must be the read's source, or be reached from the read's source through other pipe stages. A read to the end lets the source close itself, and gives no warning. A stage that reads all of its source before it passes anything on, such as `sort` or `reverse`, gives no warning either. The warning does not follow a sequence that is first stored in a local variable, a field or anywhere else.

## displaying values

A type chooses how it is displayed by implementing `Ghul.Displayable`. Its one method writes the value through a `Ghul.DISPLAY_STATE`. Write a child value with `state.render(child)`, not with `$(child)`. The state holds the element limit and the values already being written, and a new call to `$` starts without them. `state.mode` says whether the text is for `$` (`DisplayMode.CLEAN`) or for `inspect` (`DisplayMode.DETAILED`):

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

Code can also construct a `DISPLAY_STATE` directly, with a mode and a different element limit, and write into it. `DISPLAY_STATE(DisplayMode.CLEAN, 3)` writes `[1, 2, 3, 4, 5]` as `[1, 2, 3, ...]`. Read the text with `to_string()`.

`Displayable` changes the text that `$` and `inspect` produce for a value. `Ghul.Renderable` offers the same value in other media, such as an image, which a host such as a notebook can show instead of the text. Its `representations()` gives each representation as a MIME type and its content, best first. The host chooses which MIME types it shows, and the text that `$` writes is the fallback. A host that shows output in a web page does not insert `text/html` or `image/svg+xml` from a value into its own document.
