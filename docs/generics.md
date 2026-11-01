# ghūl: generics

Read this file when you are writing generic library code. It continues sections of [GHUL.md](../GHUL.md), the language reference, under the same headings. GHUL.md is loaded with every session. This file is not.

## generics

Code can reach a bound's *static* members through the type parameter, written `T.member(...)`. .NET's generic-math interfaces (`IParsable[T]`, `INumber[T]`, `IBinaryInteger[T]`, ...) are built on this mechanism:

```ghul
use System.IParsable;

parse[T: IParsable[T]](s: string) -> T => T.parse(s, null);
```

ghūl supports only using such a member. A type cannot *implement* a static interface member. Nothing connects a type's static member to the interface's static slot, and the runtime refuses to load a type that leaves such a slot empty. So declaring a concrete type that implements an interface with a static member is an error at the declaration. This applies to the generic-math interfaces above. So the built-in numeric types satisfy a bound on one of these interfaces, and a type of your own cannot.

Some of these interfaces declare an **operator** as a static member. `IAdditionOperators[TSelf, TOther, TResult]` declares addition, and `INumber[T]` extends it. Code uses such an operator as an operator, not through the type parameter, but only after importing the operator by name:

```ghul
use System.Numerics.INumber;
use System.Numerics.IAdditionOperators.`+;

total[T: INumber[T]](a: T, b: T) -> T => a + b;
```

Without the `use`, the operator is not in scope and `a + b` does not resolve. So code that does not import the operator is unaffected. Importing an operator does not replace the built-in operators: `3 + 4` still adds two `int` values with the built-in operator.

A concrete type needs no import for its own operators. A public static operator that a .NET type declares for itself is a candidate wherever either operand has that type (see [.NET interop](../GHUL.md#net-interop)). So `Int128.one + Int128.one` resolves with no import. The import is for a bounded type parameter, whose operators come from the interface, not from one type.

A static member imported by name works on a concrete type as well as on a bounded one. So `use System.Numerics.INumber.max;` makes `max(a, b)` available on a bounded `T` and on `Int128`.

These operators can be imported in this way:

- the arithmetic operators `+`, `-`, `*`, `/` and `%`
- the bitwise and shift operators `&`, `|`, `^`, `\`, `<<`, `>>` and `>>>`

The comparison and equality operators cannot be imported. A type defines its order and equality with `<>` and `=~`, and the comparison and equality operators are defined in terms of those. Import each operator from the interface that *declares* it. For the shift operators this is `IShiftOperators`, whatever the bound is:

```ghul
use System.Numerics.IBinaryInteger;
use System.Numerics.IShiftOperators.`>>>;

halve[T: IBinaryInteger[T]](a: T) -> T => a >>> 1;
```

A trait's type parameter can declare its **variance**, after any other constraints. `out` makes the parameter covariant, and `in` makes it contravariant. A covariant trait of a subtype can be assigned to the same trait of its supertype: a `Source[CAT]` is a `Source[Animal]`. A contravariant trait works in the other direction: a `Sink[Animal]` is a `Sink[CAT]`.

```ghul
trait Source[T: out] is
    next() -> T
si

trait Sink[T: in] is
    take(value: T)
si
```

The compiler checks how the type parameter is used. A covariant parameter in an input position, such as a method parameter, is an error. A contravariant parameter in an output position, such as a return type, is an error. Only a trait can declare variance, because .NET allows variance only on interfaces. `out` or `in` on a type parameter of a class or struct is an error. The variance of an imported type, a function type or an array comes from .NET.

A type parameter with a trailing `..` is an **argument pack**. The pack stands for the arguments of a call, held as a positional tuple.

Two markers work together:

- `[T..]` in the type parameter list allows the compiler to wrap the arguments into a tuple, and to unwrap a tuple into arguments, where `T` appears in the signature. This marker alone spreads nothing.
- `T..` on a formal parameter's type requests the wrapping or unwrapping for that parameter, when the call needs it.

A formal parameter of the pack type without the `..` marker takes the pack as a tuple. A caller can always write the tuple explicitly. One argument is the value itself, not a one-element tuple.

The `..` on the type parameter is that parameter's bound: it says what `T` can be. So a type parameter with `..` cannot also have a type bound.

A formal parameter writes `..` on its own type to choose how it receives the pack:

- `f: T.. -> U` takes a function whose parameters are the pack's elements, spread out. The function has as many parameters as the call supplies elements.
- `v: T..` takes the pack's elements as the call's remaining arguments.
- `v: T`, with no marker, takes the tuple.

So a function that takes a function and the values to call it with declares one of each. Callers then write the call out, and do not build the tuple by hand:

```ghul
apply[T.., U](f: T.. -> U, v: T..) -> U => f(v);

concat(a: string, b: string) -> string => "{a}{b}";

apply((a, b) => "{a}{b}", "x", "y");     // T is (string, string)
apply(concat, "x", "y");                 // the same, by name
apply(concat, ("x", "y"));               // the tuple, written out
apply(double, 123);                      // T is int, as for any parameter
```

A spread formal parameter must be the last formal parameter, because it takes all the remaining arguments. One argument is the value itself, not a one-element tuple. So in `apply(double, 123)`, `T` is `int`. Two or more arguments are the elements of the tuple. A tuple written out explicitly goes into the same formal parameter. So both forms work, and a caller that already has the tuple can pass it directly.

The pack is the last parameter of the function that the formal parameter takes. That function can have other parameters before it. `f: (A, T..) -> A` is the shape of a fold's callback: the accumulated value comes first and is passed unchanged, and the remaining parameters are the pack's elements.

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

Only the last parameter of a function type can be the pack, and a parameter list can contain only one pack. `(A.., B) -> C` and `(T.., T..) -> int` are both errors.

The pack takes its type from whatever the call supplies. A function passed to the pack's formal parameter is one source: its parameter types form the tuple. So a call that passes only the function still infers the pack, as long as the function's parameter types are known:

```ghul
n_ary[A.., B](f: A.. -> B) -> (A -> B) => f;

add(a: int, b: int) -> int => a + b;

n_ary(add);                        // A is (int, int)
n_ary((a: int, b: int) => a + b);  // the same, written out
n_ary((a, b) => a + b);            // error - nothing says what a and b are
```

The parameter itself does not change. `T` takes whatever the call supplies, `f(v)` passes one value, and a caller in another language sees a method that takes a tuple. The marker on `f` allows one thing: **a function with two or more parameters passed where the formal parameter expects a function with one parameter**. The compiler reads a function literal there as destructuring the tuple, and wraps a named function there so that it destructures the tuple. A function with one parameter needs no change, and is passed unchanged.

`[T..]` is valid on a type parameter of a class, struct, trait or union, as well as of a function or method. Each formal parameter chooses for itself. So a type that declares `EVENT[T..]` marks its handler parameter and its value parameter, each for the form it needs:

```ghul
class EVENT[T..] is
    subscribe(handler: T.. -> void) is ... si
    raise(v: T..) is ... si
si

let e = EVENT[(int, string)]();

e.subscribe((n, s) => write_line("{n} {s}"));
e.raise(7, "seven");
```

Inside the type, a formal parameter that holds the handler has the tuple-taking type `T -> void`. The type stores the handler with that type, because a type argument cannot have the marker:

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

The marker can be on the parameter of any function type along the formal parameter's chain of return types, not only on the outermost function type. `f: X -> T.. -> U` asks for a function that the caller's own lambda returns. This is how a higher-order function takes a function with N parameters:

```ghul
run[T.., U](make: (int) -> T.. -> U, v: T) -> U => make(10)(v);

run(n => (a, b) => a + b + n, (1, 2));   // 13
```

A literal in that position can write its types explicitly. Its return type is written as the function type with N parameters that the marker allows. The compiler presents the literal in the tuple-taking shape that the formal parameter takes, exactly as for an inferred literal, at whatever depth the marker is. The tuple-taking shape itself is never a valid return type for a literal with N parameters, in this position or anywhere else:

```ghul
run((n: int) -> (int, int) -> int => (a: int, b: int) -> int => a + b + n, (1, 2));   // 13

run((n: int) -> ((int, int)) -> int => (a: int, b: int) -> int => a + b + n, (1, 2)); // error
```

The marker is valid only in these places:

- as a formal parameter's own type
- as the last parameter of a function type on the chain of return types of a formal parameter's type
- as the last parameter of a function type in a declared return type

The marker anywhere else is an error. Examples are inside a larger type, on a function type reached through a parameter instead of a return type, and on a type parameter that no `[T..]` declares. The tuple limit is also the pack's limit. A tuple has at most seven elements, so a call with more than seven arguments for the pack is an error. A pack is not `params`. A list of values of one type with variable length is a different thing.

What each formal parameter requests is kept in the compiled assembly. So a pack declared in one assembly works in the same way from another assembly.

A return type with the marker returns the pack. A combinator uses this to keep the number of parameters of a function it takes:

```ghul
retry[T.., U](f: T.. -> U, attempts: int) -> T.. -> U =>
    v => ( ... call f(v) with retries ... );
```

Inside `retry`, the declared return type still describes the tuple-taking shape of the body's `v => ...` literal. The compiler presents the result at each call that gives the pack a concrete tuple type. `retry(parse, 3)` is evaluated once, at the call, and its value is a function with as many parameters as `f`. So `let safe = retry(parse, 3); safe("2a", 10)` calls it as a function with two arguments. A call that gives the pack a single argument needs no presentation, and returns the function unchanged. The same rule applies one level up. A generic function whose own return type has the marker returns the tuple-taking value that its declaration describes, and the call of *that* function does the presentation.

A generic function or method named without an argument list is a *value*, in the same way as a non-generic name used as a value. With type arguments, it is the value for those type arguments. Without type arguments, the compiler infers them from the function type of the slot that the value goes into: from the parameter types, and from the return type for a type parameter that appears only there. The value converts wherever a function type or a named delegate type is expected. When the name is overloaded, the expected type chooses the overload:

```ghul
identity[T](x: T) -> T => x;

zero_of[T](ignored: int) -> T => _[T];

let f = identity[int];                    // (int) -> int, explicit
let g: (string) -> string = identity;     // inferred from the slot
let h: (int) -> string = zero_of;         // T pinned by the return slot
```

When no slot type is in scope, there is nothing to infer from, and the bare name is an error (`cannot infer the type arguments`). Write the type arguments explicitly.

A namespace can declare the same name with different numbers of type parameters. `class BOX` and `class BOX[T]` are two types, as `Tasks.TASK` and `Tasks.TASK[T]` are. With type arguments, the name refers to the type with that number of type parameters. Without type arguments, the name refers to the type with none.

So the generic type has no bare spelling. This matters in a `typeof`. An *open* generic is a generic type with no type arguments supplied, and only reflection can hold one. A bare `BOX` in a `typeof` refers to the type with no type parameters. `BOX[_]` refers to the open generic, with one `_` for each type parameter:

```ghul
let plain = typeof BOX;         // the sibling taking no type arguments
let open = typeof BOX[_];       // BOX[T], with no argument supplied
let closed = typeof BOX[int];   // BOX[int]

typeof PAIR[_, _];              // a two-argument open generic
```

`open` is the type that `closed.get_generic_type_definition()` returns. Only reflection can hold such a type, so `FOO[_]` is valid only as the whole operand of a `typeof`. It is not valid as a declared type, inside another type argument, or with some type arguments supplied and others written as `_`. When a name has no type with zero type parameters, a bare name in a `typeof` also gives the open generic. So `typeof List` is ``IReadOnlyList`1[T]``. `X[_]` always means the open generic, whatever other types share the name. It is the only valid spelling where another type with the same name could be meant.

The main use is an attribute that names a generic type when another type has the same name. An example is a task-like type whose builder is generic (see [asynchronous code](../GHUL.md#asynchronous-code)):

```ghul
@System.Runtime.CompilerServices.AsyncMethodBuilder(typeof(COROUTINE_BUILDER[_]))
class COROUTINE[T] is ... si
```

Everywhere else that a type is required, a generic type named without its type arguments is an error, and the error says how many type arguments the type takes. The name means the open generic, and the runtime refuses to load an assembly that names an open generic in such a position. The compiler reports this at compile time, not at load time. This applies to a declared type, a parameter type, a cast target, an `isa` test and a type argument. Two positions are exempt, because each gets its type arguments from somewhere else:

- a union variant, whose type arguments come from the union, and so from the value that the variant is tested against or assigned to (`isa Option.NONE(o)` over an `Option[int]`)
- a call whose type arguments are inferred (`LIST()`)

`size_of[T]()` returns the number of bytes that a value of `T` takes where it is stored, as one element of an `ARRAY[T]`. For a scalar, it is the scalar's width. For a class or trait, it is the size of a reference. For a struct, it is the struct's laid-out size where the struct is stored in place. The value is a constant for each type argument, so it has no run-time cost. Inside a generic, it gives the size for the type that the type parameter stands for. The value depends on the target. A reference is 8 bytes on .NET and llvm, and 4 bytes on wasm. On wasm a struct is stored by reference, so `size_of` gives the size of a reference.
