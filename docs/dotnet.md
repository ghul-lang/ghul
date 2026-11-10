# ghūl: .NET interop in depth

Read this file when you are calling .NET libraries beyond the common cases. It continues sections of [GHUL.md](../GHUL.md), the language reference, under the same headings. GHUL.md is loaded with every session. This file is not.

## .NET interop

`a =~ b` on a bare, unconstrained type parameter compiles to a call of `EqualityComparerBase[T].default.equals`. .NET collections use the same comparer for a generic instantiation. The comparer calls the `Equals(object)` bridge that GHUL.md's [.NET interop](../GHUL.md#net-interop) section describes. So the comparison does what the actual type argument does:

- A type that declares `=~` and `get_hash_code` compares with its own operator.
- A class with no declared or synthesised `=~` compares by reference.
- A struct, enum or scalar gets the runtime's ordinary value equality for its type.

When a bound declares `=~` (`[T: Named]`, where `Named` declares the operator), the compiler uses the bound's operator directly, and never calls the comparer.

A tuple uses the same comparer. `EqualityComparerBase[T].default` for a `ValueTuple` is the tuple's own element-wise equality. So each element is compared with the default comparer for *its* type, and so, by the same chain, with a user-written `=~` when the element type declares one.

A type that implements `Collections.Iterator[T]` and declares no `reset` gets a synthesised `reset` that throws `Ghul.NotSupportedException`. This is what `IEnumerator.Reset` is documented to do, and what .NET's own generated iterators do. A `reset` that the type declares is unchanged. The compiler does not supply `dispose`, because only the type's author knows what the type holds and must release.

An operator is an ordinary member, and can be called as a member. This is sometimes clearer than the operator syntax, and it is how a completion list offers the operator. Separate the dot from the operator's name. The scanner reads a sequence of operator characters as one token, and `.` is an operator character. So `a.=~(b)` is read as an operator named `.=~`, not as a member access. A space separates them, and so does the backtick escape:

```ghul
a. =~(b)
a.`=~(b)
```

Both are the same call. Both are a plain method call, not another way to write the operator. The two forms differ from the operator in ways that give no error:

- The compiler writes its null handling for `a =~ b` around the *operator*. So the member call receives an absent operand, and the null handling does not answer it first.
- An operator that compiles to an IL instruction has no .NET method behind it. On the scalar types, the arithmetic operators are instructions, declared as static members of the type. So `a. +(b)` on an `int` finds no overload that takes one operand, and ``int.`+(a, b)`` is the correct call.
- `=~` and `<>` on the scalar types and on `string` do call the .NET method that the name maps to. That method does not do the same thing as the operator.

Member syntax is fine on a type whose operators you wrote. It is not a general replacement for the operator. Using an instruction-backed operator as a *value*, for example passing ``int.`+`` where a function is expected, is an error, because there is no method to take the address of. An operator you declare yourself is an ordinary static or global function, and can be used as a value like any other function. An instance member named through its type, such as `BOX.plus` or ``int.`<>``, is also an error, because a member reached through a receiver needs a receiver.

Code uses a type's own **operators** by writing the operator. A public static operator method that a .NET type declares (`op_Addition` and the others, on `bigint`, `System.DateTime`, `System.TimeSpan` and any other type that has them) is a candidate wherever either operand has that type. Both operand types supply candidates. So `step * 2.0` and `2.0 * step` find the same operator on `TimeSpan`.

The same applies to a static operator declared on a ghūl class or struct. `+(a: VECTOR, b: VECTOR) -> VECTOR static` applies to `v + w` anywhere that `VECTOR` is visible, not only inside its body. To use an operator whose operands do not include the declaring type, import it by name: ``use Lib.VECTOR_OPS.`*;``. The generic-math interface operators are imported in the same way.

The arithmetic, bitwise, shift and unary operators are found in this way. Comparison and equality come from `<>` and `=~`, as everywhere else, so a reflected `op_LessThan` or `op_Equality` is not used. The scalar types are the exception. Their operators are the language's own, so `decimal`'s reflected `op_Addition` is not a second candidate next to the built-in `+`.

`cast` can call a .NET **user-defined conversion operator** (`op_Implicit` or `op_Explicit`) declared on the source type or on the target type. `cast` also does subtype conversions and scalar conversions:

```ghul
let h = cast System.Half(1.5);      // System.Half declares `explicit operator Half(double)`
let f = cast single(h);             // and `implicit operator float(Half)`
```

`cast T(v)` calls the operator, and the operator can throw on failure, as when C# calls it. `cast T?(v)` never throws because of the conversion: an `InvalidCastException` or `OverflowException` from the operator becomes an absent value. Any other exception still propagates.

An auto-property's **backing field** has the name `$` followed by the property name. Reflection sees the backing field as well as the property. So a reflection-based serializer that is set to include fields writes every property twice. With `System.Text.Json`, leave `include_fields` unset unless the type really has fields to serialize.

ghūl has no default argument values. So code must pass every .NET **optional parameter** explicitly. There is no overload with the parameter omitted. `File.ReadAllTextAsync(path)` is written:

```ghul
let text = await IO.File.read_all_text_async(path, System.Threading.CancellationToken.none);
```

`@IL.name("Name")` sets the name of a function, method or property in the compiled assembly. Use it for a .NET library that finds members by name. For example, Entity Framework Core looks for an `Id` property, and for a `DbSet` property named after the table. On a property, `@IL.name` also names the accessors `get_Name` and `set_Name`. `@IL.name.read("...")` and `@IL.name.assign("...")` each name one accessor. The argument is a single string literal, and cannot contain a quote. A type keeps its ghūl name in the compiled assembly, so `@IL.name` on a class, struct, trait, union or enum is an error. The ghūl name does not change, so ghūl code still calls the member by its declared name:

```ghul
class PRODUCT is
    @IL.name("Id")
    id: int public

    init() is si
si
```

The compiler acts on five `@IL` pragmas: `IL.name`, `IL.name.read`, `IL.name.assign`, `IL.output` and `IL.entrypoint`. Any other `IL.` pragma gives an `unknown-pragma` warning. Without the warning, a misspelled or removed pragma would be treated as a built-in and do nothing.

`@intrinsic("operation")` marks a declaration as a compiler intrinsic. A call to it compiles to an operation of the compiler, not to a call of the emitted method. It exists for the runtime and core libraries, which provide the intrinsics that every compilation reflects. The pragma alone names the operation. So a library for a target that has no assemblies to carry attributes can still mark its declarations. When the compilation's references include the runtime's `Ghul.Internal.INTRINSIC_ATTRIBUTE`, the compiler emits the pragma as that attribute. This happens on .NET, where other compilations read the marker by reflecting the emitted assembly. When no reference includes the attribute, the compiler emits nothing. Source code cannot name the attribute type, because nothing in `Ghul.Internal` can be named from source.

`@trusted_store_free()` marks a function, method or property of a library as store-free for narrowing. The compiler then trusts it as it trusts the .NET members that it knows store nothing: a call to it leaves a narrowed value narrowed. The trust covers only the declaration's own body. Overrides have no obligation. An override in the program being compiled is judged by its own body, so an override that can store still ends a narrowing at a call that could reach it. This is the difference from `pure`, which every override must keep. `@trusted_store_free()` exists for the core library and the runtime. A build that declares library sources accepts it only in a library source, and reports it anywhere else. A build that declares no library sources is its own core. Where the runtime declares `Ghul.Internal.TRUSTED_STORE_FREE_ATTRIBUTE`, the compiler carries the marker across assemblies as that attribute.

`@finalizer()` marks the method that the collector calls after an instance of its class becomes unreachable. So an object that holds a host resource, such as an open file, releases it when the program does not dispose it, as the base class library's own finalizers do on .NET. Only the libraries can use it. It is accepted only in a core or runtime source, as `@trusted_store_free()` is. It is accepted only on an instance method with no arguments, of a non-generic class, and at most once in each class. A finalizer releases only its own object's resource, and must not throw. Everything that its object refers to still exists when it runs. The finalizers of finalizable objects that it refers to run after it. Finalizable objects that refer to one another in a cycle are never finalized. An object that is still reachable when the process ends is not finalized, as on .NET. Only the llvm target runs finalizers. On the other targets, the pragma has no effect.

A parameter attribute is recognised only where a formal parameter can appear: the parameter list of a named function or method, or of a lambda literal. It is not valid on a `let` or on a primary-constructor parameter. A parameter attribute on an element of a parenthesised expression that turns out not to be a lambda (an ordinary value tuple) is an error. The compiler does not ignore it.

`System.Obsolete` marks a declaration as deprecated. This works when the attribute is written as a pragma in ghūl, and when a .NET assembly carries it. Every use of the declaration from elsewhere is then reported as `<name> is deprecated: <message>`, or as `<name> is deprecated` when the attribute has no message. The report is a `deprecated` warning, which can be suppressed like any other warning. It is an error when the attribute's second argument is `true`. Using a class's constructor counts as using the class. A use inside a declaration that is itself deprecated is not reported, so one deprecated member can use another. Hover shows the message under the signature, and completion marks the item as deprecated.

```ghul
@System.Obsolete("use scaled instead")
doubled(x: int) -> int => x * 2;

@System.Obsolete("removed", true)
tripled(x: int) -> int => x * 3;
```

`System.Runtime.CompilerServices.MethodImpl` tells the runtime how to treat the method it is written on. The options it names become the method's implementation flags, which is where the runtime reads them, and not an attribute on the method. So `NO_INLINING` stops the method from being inlined, and `SYNCHRONIZED` takes the lock. Reflection reads the flags with `get_method_implementation_flags`, and finds no `MethodImplAttribute` among the method's custom attributes. Options combine with `|`. Written on a property or an indexer, the attribute applies to each of its accessors, `get_` and `set_`, since a property has no implementation flags of its own:

```ghul
@System.Runtime.CompilerServices.MethodImpl(
    System.Runtime.CompilerServices.MethodImplOptions.NO_INLINING)
measured(x: int) -> int => x + 1;

@System.Runtime.CompilerServices.MethodImpl(
    System.Runtime.CompilerServices.MethodImplOptions.NO_INLINING | System.Runtime.CompilerServices.MethodImplOptions.NO_OPTIMIZATION)
traced(x: int) -> int => x + 2;
```

`System.Runtime.InteropServices.DllImport` on a static method with no body declares a call into a shared library. The compiler emits the method as the call itself, not as a method with an attribute. So the method needs no body, and cannot have one:

```ghul
class LIBC is
    @System.Runtime.InteropServices.DllImport("libc")
    abs(value: int) -> int static;

    @System.Runtime.InteropServices.DllImport("libc", entry_point = "getpid")
    process_id() -> int static;

    init() is si
si
```

The name looked up in the library is the method's own name, spelled as written, unless `entry_point` gives a different name. A native symbol must match exactly, so the case conversion of .NET names does not apply. `char_set`, `set_last_error`, `exact_spelling` and `calling_convention` are passed through as written.

Only values that the machine lays out in the same way on both sides can cross the boundary: the scalar types, a pointer, a `ref` to a scalar, and a `string` argument. A `string` argument is copied to a null-terminated buffer for the duration of the call. A returned `string` is an error, because the library must free the buffer it returned, and the runtime cannot. Any other type, such as a class, a tuple, an array or a function, is an error at the declaration.

`System.Runtime.InteropServices.StructLayout` on a class or struct sets the layout of its fields. The layout must match the native structure that the type represents. The attribute's kind, `pack`, `size` and `char_set` become the type's own layout, not an attribute on the type. Without the attribute, a struct is laid out sequentially, in the order its members are declared, and a class is laid out as the runtime chooses. `SEQUENTIAL` makes a class sequential. `EXPLICIT` places each field at the offset that a `System.Runtime.InteropServices.FieldOffset` on the field gives, so two fields can share bytes. Every instance field of an `EXPLICIT` type must have a `FieldOffset`, so such a type cannot have auto-properties:

```ghul
@System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.EXPLICIT)
struct WORD_BYTES is
    @System.Runtime.InteropServices.FieldOffset(0)
    word: ushort field

    @System.Runtime.InteropServices.FieldOffset(0)
    low: ubyte field

    init() is si
si
```
