# ghūl: compilation targets

Read this file when you are building for WebAssembly or native executables. It continues sections of [GHUL.md](../GHUL.md), the language reference, under the same headings. GHUL.md is loaded with every session. This file is not.

## compilation targets

GHUL.md describes the `dotnet` and `wasm` targets. The third target, `llvm`, builds a native executable. An `llvm` build:

1. type-checks the program against ghul-runtime, as a `wasm` build does
2. writes an LLVM module
3. links the module into an executable with the `ghul-llvm` tool: statically linked by default, or dynamically linked with `--llvm-link-mode dynamic`. The tool must be on the path, or named by `GHUL_LLVM`.

These options control an `llvm` build:

- `--llvm-output <path>` also keeps the module's text.
- `--llvm-no-link`, with `--llvm-output`, makes the module's text the only output.
- `--llvm-program-only` keeps in that text only the functions compiled from the program's own sources.
- `--debug` adds line tables and variables, so a debugger and a crash's backtrace show ghūl files, lines and variables.
- `--optimise <0-3>` sets the optimisation level. The default is 2, and 0 for a `--debug` build that sets no level.
- `--llvm-parallel-gc` links the collector that marks with several threads: as many as there are processors, up to four, or `GC_MARKERS` of them where that is set. It is for programs that keep a large heap. On the compiler's own native build, with about 500 MB live, a full mark falls from about 350 ms to about 150 ms. It is not for general programs yet: a small program starts with about 7 MB resident rather than under 1 MB, and one that allocates many short-lived objects ran about 50% slower.
- `--llvm-link-mode static|dynamic` chooses how the executable is linked. `static`, the default, links it against musl, and the program runs on any Linux of the same architecture. `dynamic` links it against the glibc of the machine it is built on, and lets `--native-library` name the system's shared libraries (see [foreign functions](#foreign-functions)). The program then needs glibc 2.34 or later and those libraries where it runs. Linking dynamically needs no C compiler and no development packages. `--llvm-parallel-gc` is not available with it yet.

A library build writes the module's text and links nothing.

The `llvm` target's code generation is at an early stage. It compiles:

- functions over the scalar types, `bigint`, strings and string interpolation
- values displayed with `$` and interpolation when their type has no text of its own
- type objects from `typeof` and `get_type`
- shallow copies with `memberwise_clone`, and identity hashing with `Collections.ReferenceEqualityComparer`
- arrays, and structs and tuples stored in place, with their methods
- optional value types
- classes with their fields, constructors, static members and static constructors
- virtual calls and trait calls, type tests and casts
- scalars and structs boxed as objects, with their own methods
- unions
- generic types and functions, compiled once for each instantiation
- generators, asynchronous functions and `await`
- function values
- exceptions thrown, caught, and cleaned up after with `finally`
- local variables, `ref` arguments to locals and to array elements, loops over ranges and other loops, conditionals, integer division checked as on .NET, and calls
- the host operations, such as writing to the console
- an `entry` that takes the command-line arguments as a `string[]` or an `ARRAY[string]`

It reports anything else as `code generation for <construct> is not supported on the llvm target`. It reports this only in code that the program reaches. An executable compiles only what its entry point calls, so an unsupported construct elsewhere in a library is not reported. A namespace named `llvm` at the root of the program is an error on this target, reported as `a namespace named 'llvm' not supported on the 'llvm' target`, because LLVM reserves the names that start with `llvm.` for its own intrinsics. A namespace with that name nested inside another namespace, such as `Outer.llvm`, is valid.

On the llvm target, an exception that nothing catches is reported with the frames it was thrown through, innermost first. The report is the `Unhandled exception.` line, followed by one `   at <name>` line for each frame. The wasm target does the same in a build with `--debug`. In such a build, a throw goes through the loader, so the exception records its stack. Without `--debug`, a throw stays inside the module, which is several times cheaper, and the report has no frames. A trap that the engine raises, such as an integer division by zero, has its frames in either case.

On the llvm target, a crash is reported in the same way. The program's output is flushed first. A stack that runs out is reported as `Stack overflow.`. Any other fault (a bus error, an arithmetic fault or an illegal instruction) is reported as `Fatal error.` and the signal. The process then ends with the signal.

A frame has the name that the linker gives the function. On the llvm target, a build with `--debug` adds the frame's file and line. At the default optimisation level, a function inlined into another function has no frame of its own. A stack that the llvm optimiser has turned into a loop does not run out, so it is never reported.

On the llvm target, `Ghul.MethodImpl` asks for or against inlining, as it does on .NET: a function marked `NO_INLINING` is never inlined, and one marked `AGGRESSIVE_INLINING` is inlined wherever it is called. Its other options change nothing there, and on the wasm target none of them do.

A `wasm` build loads no .NET assemblies. One library, ghul-runtime, compiled into the module from source, supplies what the .NET assemblies supply on .NET. It holds two source trees:

- `ghul-core` gives the built-in types their members, and declares the collections.
- `ghul-runtime` supplies the pipes and the rest of `Ghul`.

The `ghul` command-line tool builds a project for the `wasm` or `llvm` target, and fetches the library for either target. A project lists its targets in its `ghul-project.json` manifest. A .NET project is built with the .NET SDK instead:

```sh
ghul new hello --target llvm,wasm
cd hello
ghul run --target wasm
```

On the llvm target, `T?` over an unconstrained type parameter is held, at an instantiation where `T` is a reference type that is not itself optional, as the reference itself, null where it is absent. On .NET and wasm it is held as `Ghul.MAYBE[T]`, a presence flag and the value. An instantiation over a value type or over an optional type keeps the flag on every target, so a `find` over `int?` or `string?` elements still tells an absent element it found from finding nothing. Converting such a value to `object?` gives null or the value on every target. Two things differ only where the value is boxed as itself, as when a type parameter bound to it is converted to `object`:

- an absent value is null on llvm, and a non-null boxed `Ghul.MAYBE[T]` on .NET and wasm
- a present value is the reference itself on llvm, so `isa Ghul.MAYBE[string](o)` is false and `o.get_type()` names the reference's type, where on .NET and wasm `o` is a boxed `Ghul.MAYBE[string]`

At an instantiation where `T` is a value type that is not itself optional, wasm and llvm hold `T?` as they hold a written `int?`. On wasm that is a reference to the value's box, or to the struct, null where it is absent. On llvm it is the flag and the value, in place. Either way it is boxed, compared and hashed as `int?` is. Where such a value is boxed as itself, the targets differ in two ways:

- an absent value is null on wasm and llvm, and a non-null boxed `Ghul.MAYBE[T]` on .NET
- a present value is the boxed value on wasm and llvm, so `isa Ghul.MAYBE[int](o)` is false there, where on .NET `o` is a boxed `Ghul.MAYBE[int]`

On every target, a type object's name, as `typeof` and `get_type` give it, names the scalars, `string` and `object` as .NET names them. Any other type is named on .NET by its CLR name, ``System.Collections.Generic.IReadOnlyList`1[System.String]`` for `typeof string[]`, and on wasm and llvm by the name it is emitted under, `Collections.List[System.String]`. So code that compares a type's name with text is target-specific; comparing type objects with `==` is not.

## conditional compilation

`@IF.<name>()` before a definition or a statement keeps it only when `<name>` is on. `@IF.not.<name>()` keeps it only when `<name>` is off. The name of the target being built is on, and the other targets' names are off. So `@IF.dotnet()`, `@IF.wasm()` and `@IF.llvm()` give each target its own declaration. `@IF.source_core()` is on for every target whose core library is compiled from source, which is `wasm` and `llvm`. It is off for `dotnet`. So a declaration that only needs the absence of the .NET base class library is written once:

```ghul
use IO.Std.write_line

entry() is
    write_line(target_name())

    @IF.wasm()
    write_line("a statement kept only for wasm")
si

@IF.dotnet()
target_name() -> string => "dotnet"

@IF.wasm()
target_name() -> string => "wasm"
```

`--define <name>` turns any other name on. A name that nothing turns on is off. A `--define` of a target's name, or of `source_core`, has no effect, because the target being built decides those names. Code that is left out is never compiled, so it can name things that the build does not have, such as a .NET API in a `@IF.dotnet()` declaration. To leave a whole file out of one target, write the `@IF` on the file's namespace.

## foreign functions

`@extern(module, name)` before a global function or static method with no body declares a function that the program is linked with, not one it defines. The ghūl signature is the whole declaration. The compiler reads no C prototype, and there is no separate interface description. A call is a call to the named symbol. The declaration cannot have a body, cannot be generic, and cannot be an instance member.

```ghul
@extern("libc", "abs")
absolute(value: int) -> int

@extern("libc", "strlen")
length_of(text: string) -> word
```

The meaning of the module and the name depends on the target. So write a declaration that differs between targets with `@IF.<target>()`:

| target | module | name |
|--------|--------|------|
| dotnet | the library, as `DllImport` takes it | the entry point |
| llvm | the library that supplies the symbol; empty for what the C library or libghul already holds | the C symbol, spelled exactly |
| wasm | must be empty | a function the program's caller supplies |

On .NET, an `@extern` is the `DllImport` it stands for, with the platform's default marshalling. On llvm, it is a C ABI call. By default the program links statically against musl, so a library that it names must be available as a static archive built for musl. With `--llvm-link-mode dynamic` it links against the system's glibc instead, and a library that it names is the system's shared library. These options control the link, and each can be repeated:

- `--native-input <path>` adds an object file or archive.
- `--native-library <name>` links `lib<name>.a`, or under `--llvm-link-mode dynamic` the shared library `lib<name>.so`.
- `--native-library-path <dir>` adds a directory to search for libraries.

In a dynamic link, a shared library is looked for in each `--native-library-path` directory, then where the system's dynamic loader looks: its cache, `/etc/ld.so.cache`, and the standard library directories. The file linked is the one the library's soname names, such as `libz.so.1`, so only the library's runtime package needs to be installed, not its development package. A library found in a `--native-library-path` directory is recorded in the program, so the program finds it there when it runs.

A symbol that the link cannot find is reported at the `@extern` declaration that names it. A library that is named but that no call reaches is not linked.

Only values that the machine lays out in the same way on both sides can cross:

- The scalars `bool`, `char`, `byte`, `ubyte`, `short`, `ushort`, `int`, `uint`, `long`, `ulong`, `word`, `uword`, `single` and `double` cross as the C types of the same width. A C pointer that ghūl only holds and passes back, such as a handle, is a `word`.
- A `string` argument crosses as a NUL-terminated UTF-8 copy, made for the call and released after it.
- On .NET and llvm, a reference, such as `int ref` or `word ref`, crosses as the address of the slot, so a C out-parameter such as `int *` or `sqlite3 **` writes into a local, a field or an array element. The address is valid for the call only.
- On .NET and llvm, an `ARRAY[ubyte]` crosses as the address of its first byte, so the foreign function reads or writes the array's own bytes. The length is a separate argument that the declaration has and the caller passes, as in C. A length greater than the array's count is the caller's bug, and nothing checks it. The address is valid for the call only, and the callee must not keep it.
- On .NET and llvm, a reference to a struct marked `@layout("c")`, such as `TM ref`, crosses as the address of the struct, so a C function that takes a `struct tm *` reads and writes its fields. The address is valid for the call only. On .NET, a struct that the platform's marshalling cannot pass in place, such as one with a `bool`, `char` or reference field, fails at the call with .NET's marshalling exception.
- Pointers cross on .NET only.

Any other type, such as a class, a tuple, another kind of array or a function, is an error at the parameter. A foreign function that keeps the pointer it was given after it returns has undefined behaviour, as with any marshalled call.

`@layout("c")` before a struct promises that its fields are laid out as C lays out a struct with the same fields: in the order they are declared, each aligned to its own size, with the padding that C puts between them. `size_of` gives the struct's C `sizeof`. The promise is about layout only, and nothing about the fields is checked: calling foreign code is unsafe, and the declaration has to match what the foreign code expects. A reference, such as a `string` or a class, is laid out as a pointer. A `bool` takes the size the target gives it, which is one byte on llvm, as a C `_Bool` is. A `signed char` is a `byte` and an `unsigned char` is a `ubyte`. A plain C `char` is whichever of those two the platform uses: it is signed on x86-64 and unsigned on 64-bit Arm Linux. A C pointer field that ghūl only holds is a `word`. `@layout` on anything but a struct, and a layout other than `"c"`, are errors. Bit-fields and C unions have no equivalent, and structs do not cross by value.

```ghul
@layout("c")
struct TIME_PARTS is
    second: int field public
    minute: int field public
    hour: int field public
    day: int field public
    month: int field public
    year: int field public
    weekday: int field public
    yearday: int field public
    is_dst: int field public
    gmt_offset: long field public
    zone: word field public

    init() is si
si

@extern("libc", "gmtime_r")
gmtime(time: long ref, result: TIME_PARTS ref) -> word
```

On llvm, `Ghul.Interop.read` and `write` read and write a value of any type at an address, and `elements` gives the address of an array's first element. An `ARRAY[T]` of a struct holds its elements in place, one after another, as a C array of the struct does, and an array of references holds one pointer after another.

A function that returns a string must say who owns the text, on llvm, with a named argument. A string return is an error on .NET. On wasm, a string return needs no named argument. The two values are:

- `result = "copy"` copies text that the callee keeps, as `getenv` returns it.
- `result = "take"` copies text that the callee allocated, and then releases it: with the C library's `free`, or with the function that `free = "name"` names, for a library that has its own deallocator.

A null return is the absent string, so the return type is `string?`.

```ghul
@extern("libc", "getenv", result = "copy")
environment_variable(name: string) -> string?

@extern("libc", "strdup", result = "take")
duplicate(text: string) -> string?

@extern("", "sqlite3_mprintf", result = "take", free = "sqlite3_free")
format(text: string) -> string?
```

On llvm, `errno = <value>` makes the function answer `Result[T, int]`, where `T` is what the C function returns. The value names the result that signals failure, and the error that the `ERROR` variant carries is the C library's `errno`, read straight after the call. So `errno = 0` means that a zero result is a failure, not that `errno` is tested for zero. `errno = "negative"` takes any negative result as failure. `errno = "set"` zeroes `errno` before the call and takes a nonzero `errno` after it as failure, whatever the result. That form is only correct for a function documented to be used that way, such as `strtol`, `readdir` or `getpriority`, because C allows a function to set `errno` when it succeeds. `errno` is an error on .NET and on wasm.

```ghul
@extern("libc", "close", errno = -1)
close(fd: int) -> Result[int, int]

@extern("libc", "opendir", errno = 0)
open_directory(path: string) -> Result[word, int]

@extern("libc", "strtol", errno = "set")
parse(text: string, end: word, base: int) -> Result[long, int]
```

On llvm, `variadic = n` calls a C variadic function, such as `printf` or `open`, with the parameters from the `n`th on passed as C passes variadic arguments: a `single` as a `double`, and anything narrower than an `int` as an `int`. The declaration is an ordinary one with a fixed list of parameters, so a call that passes different types is a different declaration of the same symbol. Two declarations of one symbol must have the same first `n` parameters and the same result. `variadic` is an error on .NET and on wasm.

```ghul
@extern("libc", "open", variadic = 2)
open(path: string, flags: int) -> int

@extern("libc", "open", variadic = 2)
open_creating(path: string, flags: int, mode: uint) -> int
```

Foreign code allocates with the C library's own `malloc` and `free`. The garbage collector does not see or scan that memory. A ghūl object can hold a pointer into it, and the program that does so must release it. The reverse is not true: memory that a foreign library allocated cannot reliably keep a ghūl object alive. So no object or array crosses, and nothing can be registered for the library to call back into.

On wasm, the module must be empty, and the name is looked up in `options.externs`, the object that the loader's `run` takes. Each declared name must be a function in that object. A program that declares a name the caller does not supply fails to start, and the error names the missing function. Numbers cross as JavaScript numbers, except `long`, `ulong`, `word` and `uword`, which cross as BigInts. A string crosses as a string, as a result and as an argument. A reference or an array cannot cross, because the host cannot write through a reference or read a WasmGC array. Every `@extern` function that the program declares is imported, whether or not it is called.

## what differs on the wasm target

On the `wasm` target, a .NET API exists only if the core library declares it. A program that calls any other .NET API gets a name-not-found error, as for any other missing name. A construct that the `wasm` target can never support is reported where it is written:

- a pointer type, as `pointer types not supported on the 'wasm' target`
- an `IL.` pragma, which states a fact about an assembly, as `pragma 'IL.name' not supported on the 'wasm' target`
- a mutable local that a closure captures, passed by `ref`, as `on wasm, 'n' cannot be passed by reference because a closure captures it`, and a method that can change a struct, called on a captured struct local, as `on wasm, a method that can change 'c' cannot be called on it because a closure captures it`. Both are reported where the call is written, with a help message that says to use a local of its own or a copy and assign the result back. On `dotnet` and `llvm` the callee's write reaches the closures, with `ghul.runtime` 42 or later

A construct that the target will support, but cannot generate code for yet, is reported at the function that contains it, as `code generation for <construct> is not supported on the wasm target`.

Not yet supported on the `wasm` target:

- `decimal`. The `llvm` target does not support `decimal` either.
- an interpolated number with a format other than the standard formats `D`, `E`, `F`, `G`, `N`, `R` and `X`, or a custom pattern of `0`, `#`, `.` and `,`
- an interpolated enum with any format

A program run by Node reads and writes the real file system through `File`, `Directory` and the readers and writers over a file, as a .NET program does. In a web page there is no file system. There, these types use a file system held in memory, which starts empty and holds what the program writes, and each file written is passed to the page. Under Node, a caller of the loader can also supply the program's files, or a sink for the files it writes, and these are then held in memory. `Path` works as it does on .NET. Standard input and output are read and written as on .NET. When standard output is not a terminal, the Node loader holds it and writes it in 64 KiB pieces. Held output is written before a read from standard input, a write to standard error, a process start or a flush, and when the program ends, however it ends.

Reflection on the `wasm` and `llvm` targets is a subset of .NET reflection, with the same names and meanings:

- a `Type`'s fields, properties, constructors, base type and generic arguments, and among its attributes the one that the compiler puts on a union. A program's own attributes are not reported: `get_custom_attributes` answers none of them
- `FieldInfo`, `PropertyInfo`, `ConstructorInfo` and `ParameterInfo`
- `Activator.create_instance`
- `Assembly.get_entry_assembly().get_types()`, which lists the program's own types other than traits and generic types, the types marked `@reflected()`, and a type for each namespace whose global functions are described, named `<namespace>.$globals` as on .NET. Under `--rtti-roots` it lists the classes holding the program's tests and the types marked `@reflected()`, with the `$globals` type of each namespace whose global functions include tests or that is marked `@reflected()`.
- a `Type`'s `get_methods`, `get_method(name)` and `get_method(name, types)`, and a `MethodInfo`'s `get_parameters`, `declaring_type`, `return_type` and `invoke`, with a null instance for a static method. Each overload is its own `MethodInfo`. `get_method(name)` throws `Ghul.Reflection.AmbiguousMatchException` where the name is overloaded, and `get_method(name, types)` matches the parameter types exactly.
- `Ghul.Reflection.get_type(name)`, `Ghul.Reflection.get_function(name)` and `Ghul.Reflection.get_function(name, types)`, which find a type, and a global function as a static `MethodInfo`, by the name the source gives it, such as `Ghul.Math.abs`. They work the same on every target, and ignore an assembly that qualifies a type's name.
- `Nullable.get_underlying_type`
- an enum's names and values, through `System.Enum`

The methods described are a type's tests, and the other methods it declares: those of the program's own types, and those of a library type marked `@reflected()`. Global functions are described in the same way, as static methods of their namespace's `$globals` type: the program's own, and those of a library namespace marked `@reflected()`. A method or global function with type parameters of its own, one taking an argument by reference, one taking more than six arguments, an operator and a property's accessor are not described. Under `--rtti-roots`, only the methods of a type marked `@reflected()` and the global functions of a namespace marked so are described.

Fields and properties are reported as declared. So an auto-property `x` is reported as the property `x` and its backing field `$x`. On both targets, the attribute that the compiler puts on a union, among the union's `get_custom_attributes`, lists the union's variants. The compiler describes the program's types only when it builds with `--rtti`, which adds code for each type. Reflecting on a type in a build without `--rtti` throws `NotSupportedException`. `--rtti-roots` describes fewer types. It describes the types marked `@reflected()` (a class, struct, trait, union or enum; a namespace can be marked too, for its global functions), and the types their descriptions reach: bases, the types of fields, properties and constructor parameters, type arguments, array elements, and the classes that extend or implement the type of a value a described type holds. A value held only as `object` is described only when its own type is reached some other way. On `.NET`, `@reflected()` does nothing.

`@test()` marks a method or a global function as a test, for a test runner to find through reflection and call. A test takes no arguments and returns nothing. An instance test is called on a new instance of its class, so the class must be a class, not abstract and not generic, with a public `init()` that takes no arguments. Tests in a struct are not supported yet. On `.NET` a test carries the attribute `Ghul.TEST_ATTRIBUTE`, and a runner finds it among the entry assembly's types, global tests as static methods of each namespace's `$globals` class. On `wasm` and `llvm`, a build with `--rtti` or `--rtti-roots` describes each test, with the attribute among the method's `get_custom_attributes`. Under `--rtti-roots`, a class described only because it declares tests is described only as far as a runner needs: its tests and its public constructor that takes no arguments. The tests of a source library compiled into the program are not the program's, and are not described.
