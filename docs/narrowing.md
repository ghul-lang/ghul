# ghūl: narrowing

Read this file when you need to know why a value is or is not narrowed, or when you are changing the compiler's flow analysis. It continues sections of [GHUL.md](../GHUL.md), the language reference, under the same headings. GHUL.md is loaded with every session. This file is not.

## optional types

A generic function that returns `T?` can be called with a `T` that is itself optional. Its result then has two layers: whether a value came back, and the value, which can itself be absent. `next[T](iter: Iterator[T]) -> T?` called on the iterator of a `string?[]` returns a `string??`. `if let`, `while let` and `!` remove only the outer layer. So the value they give is the `string?`, which still needs a test. `??` and a `case` over the result test the outer layer. `?.` also tests only the outer layer, so reading a member through the inner value is an error. Write `(x!)?.length` to test both layers.

When the left operand of `??` holds the runtime's `Result[T, E]` union, `??` unwraps the result instead of coalescing. A present value (an OK) gives its payload. An absent value (an ERROR) is replaced by the right operand. The result has exactly the right operand's type:

- `Result[T, E] ?? Result[T, F]` gives a `Result[T, F]`. The OK payload is rebuilt with the right operand's type arguments, and the left operand's error type is discarded.
- `Result[T, E] ?? T` gives a `T`.

The left operand's error is never part of the result. It is discarded, with its payload, when the right operand replaces it. An error in the result is always the right operand's error, which means the fallback failed too: `failed_a() ?? failed_b()` is the error value of `failed_b()`. A chain of `??` is evaluated right-associatively, and has the type of the rightmost fallback. The right operand must be a Result, or must be assignable to the OK payload. The operator treats a value as a Result only when the build's runtime declares the union.

```ghul
let port: int = parse(text) ?? 80
let later: Result[int, string] = first() ?? second()
```

`??` over plain optionals:

```ghul
let name: string? = lookup();
let greeting = "hello, {name ?? "stranger"}";   // string

let primary: string?   = first();
let secondary: string? = second();
let chosen = primary ?? secondary ?? "fallback"; // string
```

GHUL.md describes how `=~` handles optional operands: the compiler writes null checks around the call. An absent left operand always gets its result from these null checks, whatever the operator declares, because there is no receiver to call a method on. The operator's declaration decides what happens to the *right* operand:

- When the parameter is declared non-optional, the null checks also handle an absent right operand, and the body receives only present values.
- When the parameter is declared optional, as in the `Ghul.Equatable[T]` example in GHUL.md's [.NET interop](../GHUL.md#net-interop) section, the body receives the absent value and handles it.

A `T?` over a value type, or over an unconstrained type parameter, compares in the same way, with one difference. The null checks always handle an absent value of these types, and never pass it to the operator, because a value operand has no absent form to pass.

A global `=~` works in the same way. When it declares non-optional parameters, the compiler writes the null checks around it, and its body receives only present values. When it declares optional parameters, it handles absence itself, and the compiler calls it as written.

Some types do not compare through an operator at all. An enum compares with an opcode. A tuple and a bare type parameter have no operator (see [equality](../GHUL.md#equality)). The compiler writes the same null checks around whatever compares these types. So an optional of one of these types behaves exactly like an optional of a type that declares an operator. The rule is: `a =~ b` resolves on `T?` whenever it resolves on `T`.

## type narrowing

These rules add to GHUL.md's description of narrowing by assignment. An assigned `null` gives only the presence fact. An assigned value of a value type does not narrow, because a wider variable holds the boxed value, not the plain struct. An assigned value of a tuple type keeps the declared type's spelling, so the named elements stay reachable. When different branches assign different types, the variable has their common ancestor type after the `fi`.

Narrowing applies to:

- local variables, including a function's own parameters
- `self`. An `isa`, `if let` or destructure on `self` narrows `self` in place. So a method, typically in an [`impl` block](../GHUL.md#partial-and-impl-blocks), can match its own concrete type or a union's variants without first copying `self` into a local. `self` is never reassigned, so reassignment never removes its narrowing.
- fields
- properties
- member-access paths made of these

Both presence facts and type facts apply to paths. After `if x.y? then`, a later `x.y` has its non-optional type. After `if isa CAT(x.y) then`, a later `x.y` has the type `CAT`, so `x.y.purr()` type-checks. `if let p: CAT = x.y` narrows in the same way. When the value is a closed hierarchy, the else edge narrows to the other types. A union with two variants narrows to the other variant. A closed class hierarchy removes the tested subclass from the possible types. So `if isa CAT(x.y) then x.y.purr() else x.y.bark() fi` type-checks in both arms when `x.y` is a closed `Animal`. Narrowings on the same path combine by intersection, for sibling types and for a class with a trait. After `if isa Purring(x.y)`, `x.y` has both the `Animal` members and the `Purring` members. Every step of a path must be a field or a property.

Different facts last for different times:

- A local's narrowing lasts until the local is reassigned. The assignment then narrows the local to the new value's static type when that type is strictly more specific. Otherwise the local has its declared type.
- A global variable is narrowed again by assignment in the same way. But its narrowing is a heap fact, not a local fact. A callee can name the global and write it. So the narrowing ends at any call that the compiler cannot prove leaves the global unchanged.
- The compiler tracks direct stores precisely. A field's fact ends at an assignment to the same field through any receiver, because the receiver written may be the same object as the receiver the fact was proved on. A property's fact ends at any assignment to a field, property or element, because the property's getter may read anything the assignment changed. A path's fact ends at a store to anything the path reads through, and when the path's root is reassigned.

The compiler treats one kind of local as heap state: a local that a function literal assigns. Such a local is not on the stack. The closure body and the enclosing scope share one storage cell. So a call can change the local without the enclosing scope seeing it. Facts about such a local form in the same way as facts about any local. They last across calls in the same way as facts about a field:

- A call that provably leaves the local unchanged keeps the facts. Such a call is a store-free callee, or a callee whose solved write set does not include the local.
- A call that runs the assigning closure, directly or through anything that can reach it, ends the facts.

To use the value after such a call, test it again, or copy it into a local variable before the call.

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

A new local declared by `if let` is out of reach of every closure, so its facts last across any call:

```ghul
if let present = s then
    clear();

    write_line("{present.length}");
fi
```

A heap fact lasts from the test that establishes it until the first call that the compiler cannot prove leaves it unchanged, or the first store that could change it. From that point the value has its declared type again. The compiler decides this after the whole program has compiled. So the narrowed type after a call is the type that the effect relations justify, and the compiler checks every later use against that type. Passing the value where only the non-optional or narrower type is valid is the ordinary type error. Reading a member through it is the ordinary error for a dereference through an optional. To fix the error, test the value again, or copy it into a local variable before the call. A local that no closure assigns cannot be reached by any callee, so its facts last across every call.

Testing the value again re-establishes the fact, whatever calls came before. A presence test, an unwrap `!`, a coalescing `?.`, an `isa` test and an `if let` all check the value at run time. So in `if _f? /\ mutate() then`, when the compiler cannot prove that `mutate` leaves `_f` unchanged, `_f` has its declared type `string?` in the branch. Passing `_f` where a `string` is required is an error there, `_f.length` is an error, and `_f!.length` is valid. The editor marks the call that ended the fact with a `◄` hint, which names what the call can change.

The compiler decides whether a call leaves a fact unchanged member by member, after the whole program has compiled:

- A call leaves a fact unchanged when nothing it can reach writes the member that the fact describes. What a call can reach includes overrides and called function values. For a presence fact, the question is whether anything reachable writes a possibly absent value to the member.
- A call leaves a fact read through a getter unchanged when nothing it can reach writes anything that the getter reads.
- A store-free callee leaves every fact unchanged.

A small fixed set of imported .NET members is trusted further than an unproven call and less than a store-free call. These are the collection mutators `LIST.add`, `LIST.insert`, `LIST.remove_at`, `LIST.clear`, `STACK.push`, `STACK.pop` and `STACK.clear`, and the `STRING_BUILDER` writers. They store only their own receiver's internal state, and call nothing while they do it. So they leave unchanged any fact that does not read through a getter of that state. So `if _name? then _items.add(x); _name.length` type-checks. The same `_items.add(x)` before a use that relies on a property whose getter reads `_items` is reported.

The compiler also trusts some members by their shape:

- An imported .NET static method whose parameters are all scalars, strings or enums has no receiver, and nothing overridable to name. It counts as store-free.
- An imported instance member that the CLR binds statically (non-virtual, final, on a struct, or on a sealed type), with such parameters, can only write its own receiver's internal state. So field facts last across a call to it, and property facts end.
- Generic methods, static virtual interface members and members of a generic type do not get this trust, because their bodies can dispatch through a type parameter. `LIST[T].sort()` is a member of a generic type in this sense, although it takes no arguments that name a type parameter.
- A global function imported from another ghūl assembly is also a CLR static method, but it does not get this trust. Its body is arbitrary ghūl code, not a .NET API. So it is trusted only when it is declared `pure`, like code of your own.

A static method can still use mutable ambient state that its parameters do not name. For example, `Console.write_line(s)` writes through whatever writer `Console.set_out` last installed. The compiler accepts this risk and does not guard against it. Redirecting such a widely used stream to code that changes narrowed state is not a realistic hazard, and declining to trust every static method that takes a string would make this trust useless.

The fixed set is part of the compiler, and source code cannot extend it. For code of your own, declare `pure`. `pure` makes a stronger claim: the function stores nothing at all.

The getter that a fact reads through is held to the same standard. The compiler presents the fact as a narrowing only when the getter's own call, treated as a crossing like any other call, is discharged. Being store-free is sufficient for this, but not necessary. A write-only getter, whose writes are disjoint from everything it reads, is self-stable and supports the fact. When the getter cannot support the fact, the test presents no narrowing at all. There is no narrowing inlay at the test, hover shows the declared type, and the editor shows a hint at the test that names the getter, because such a getter can return a different value on every read. To fix this, use `if let` or a local variable. When adjacent reads really do agree, declare the property `stable` (see below).

The compiler proves one getter shape instead of refusing it: the **monotone memoiser**. A monotone memoiser's body:

- writes only one field of the receiver
- writes only values that are always present to that field
- returns an absent value only under a guard that proved that field absent
- returns that field on every other path

Such a getter cannot change its result from present to absent. So a presence fact through it lasts even across the getter's own call, and relying on the presence is sound. The compiler still refuses a type fact through the same getter, because writing the field while it is absent can change the runtime type that a member of a wider type holds.

When the compiler cannot prove what it needs, declare it. A postfix `pure` modifier on a function or method (`describe() -> int pure is … si`) makes the compiler treat it as store-free, so a fact lasts across a call to it, without proving the body. The declaration is a contract. Every override and every trait implementation must also be pure, declared or proved. Breaking this rule is a compile error, even when the pure base member is imported from another assembly.

A postfix `pure` on a function type (`filter(p: (T) -> bool pure)`) extends the contract to a slot that holds a function. Such a slot accepts only a store-free value:

- a literal whose body has no call that may store, no heap store and no local reassignment
- a store-free named function
- a value that already has a pure function type

The slot can be a parameter, a variable, a field or a return type. Putting any other value in it is reported, whether by passing, assigning, initializing or returning. The two kinds of position have different slugs, because the warnings have different weight:

- Passing an impure value as an argument gives `impure-function-argument`. This warning is advice. The compiler judges the enclosing call by its own callee in any case, so narrowing at that call does not depend on the warning.
- Storing an impure value in any other kind of slot gives `impure-function-value`. This warning matters. The value stays in the slot, and the compiler trusts a call through a pure function type to leave every fact unchanged. So code can rely on a stale fact across a call that does invalidate it. Fix this warning, or do not declare the slot pure.

A property can make a similar declaration about its getter with a postfix `stable` modifier (`value: string? stable => …`). `stable` means that two adjacent reads, with nothing between them, agree on presence and runtime type. Use it for a getter that the crossing question cannot prove, such as a general memoiser or a cache: the case where `pure` would be false, because the getter stores. The compiler presents facts narrowed through a property declared `stable`, although it cannot prove the body. The getter's own re-read is discharged, for presence and for type. Other calls cross the fact as usual, judged by what they can write and what the getter reads.

On a member-access path, `stable` covers only the property that declares it. A stable property deeper in the path returns the same object on each read, but its getter may write through that object. So a fact about a further member still depends on that property's call. Copy the path prefix into a local instead.

`stable` is independent of `pure`. A memoiser is impure and stable. `stable` is a contract in the same way as `pure`. Every override must also be stable, either declared or proved self-stable by the same crossing question. Breaking this rule is a compile error, even when the stable base member is imported from another assembly.

Being store-free is a property of the function, not of the slot it goes into. So a function value's own type shows it. A literal whose body is proved store-free has a pure function type. So does a reference to a function that is declared `pure` or proved store-free. The pure function type shows wherever the type is shown.

```ghul
double(x: int) -> int pure => x * 2;

let f = double;                      // (int) -> int pure
let g = (n: int) -> int => n * 2;    // (int) -> int pure — proved store-free
```

A literal written `pure` has a pure function type whatever its body does: `(n: int) -> int pure => …`. The compiler trusts it, as it trusts a function declared `pure`. The marker goes with the literal's `rec` and `memo` markers, in any order.

The compiler trusts a variable of a pure function type to hold a store-free value wherever it is read. So the warning is on the store into such a variable, and the trust is only as good as the values stored. A pure function type is a declaration in the same sense as `pure` on a function. The compiler verifies neither, and both mislead the compiler when they are false. Reassigning such a variable is fine, as long as the new value is also store-free. Purity declarations and pure function types are kept in a compiled assembly, and the compiler honours them when it imports the assembly.

A postfix `pure` on a class, struct or trait header (`class PARSER pure is ... si`) makes the same declaration for a whole type. Every instance member must then be pure, either proved store-free or declared `pure`. A member that stores is an error, and the error names it. Declaring the member `pure` is the way out: the compiler trusts the declaration and does not verify it, as everywhere else. These writes are exempt, because they are necessary:

- Constructors assign fields by definition.
- Static members keep their own state, and can be marked one by one.
- Assign accessors, and the `ref` parameter writes of the synthesised `deconstruct`, are allowed write paths. A getter that stores through an assign accessor is still an error, because from outside it looks like a read. A hand-written `deconstruct` is an ordinary member, and gets no exemption.

A pure type cannot make a write public. Declaring a property `public` makes its assign accessor public, and this is an error on a pure class, on a pure struct and on a primary-constructor parameter of either. `pure` on a union is an error, because union members are already required to be pure through `partial` and `impl` blocks.

A member with no body in a pure type is implicitly declared `pure`. It is a contract, not an implementation, so implementations inherit the requirement through the ordinary override rules. A class that implements a pure trait cannot supply a method that stores, in the same way that it cannot override a member declared `pure` with one.

The type-level `pure` marker is a rule for the declaring assembly and its readers. It is not a separate contract across assemblies. Members that are declared or proved pure cross assemblies one by one and keep their guarantees there. The override contract binds implementations in exactly the same way.
