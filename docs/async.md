# ghūl: asynchronous code

Read this file when you are writing a coroutine library or a custom task type. It continues sections of [GHUL.md](../GHUL.md), the language reference, under the same headings. GHUL.md is loaded with every session. This file is not.

## asynchronous code

The operand of `await` does not have to be a task. `await` accepts any value that follows .NET's awaiter pattern. Such a value's type has a parameterless `get_awaiter()`. The result of `get_awaiter()` must:

- have a `bool` property `is_completed`
- have a parameterless `get_result()`
- implement `System.Runtime.CompilerServices.INotifyCompletion` or `ICriticalNotifyCompletion`

The `await` expression has the type that `get_result` returns, which can be void. `Tasks.ValueTask[T]`, `Concurrency.Future.yield()` and `task.configure_await(false)` all follow the pattern. A type written in ghūl can follow it too. For example, a struct awaitable that gives its continuation to a scheduler implements cooperative multitasking without allocating a task for each suspension:

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

An `await` on a value that does not follow the pattern is an error, and the error names the first missing member.

The return type of an asynchronous function does not have to be `Concurrency.Future` or `Concurrency.Future[T]` either. Any type with .NET's `AsyncMethodBuilderAttribute` is a *task-like* return type. The attribute names a builder type, and the compiler uses that builder instead of the Task builder. `Tasks.ValueTask[T]` and `Tasks.ValueTask` work this way. So does a type declared in ghūl source. A library uses this to give its coroutines their own return type, instead of a Task:

```ghul
@System.Runtime.CompilerServices.AsyncMethodBuilder(typeof(COROUTINE_BUILDER))
class COROUTINE[T] is
    value: T public;

    init() is si
si
```

A builder written in ghūl declares its members with their ghūl names:

- a static `create()`
- a `start` that takes the state machine by reference and calls its `move_next`
- a readable `task` property that returns the task-like value
- a `set_result` that takes the result, or takes nothing for a task-like type with no result
- a `set_exception` that takes a `Ghul.Exception`
- `await_on_completed` and `await_unsafe_on_completed`, each taking the awaiter by reference

.NET's own builders have the same members.

An `async` function declared `-> COROUTINE[int]` awaits, suspends and returns a bare `int` exactly as a `Concurrency.Future[int]` function does. A generic task-like type has exactly one type parameter, and it is the result type, as for `Task` and `ValueTask`. A non-generic task-like type has no result. These are errors, reported at the function that returns the task-like type:

- a builder that does not declare one of the required members
- a builder member that does not take the by-reference parameter that the compiler passes
- a return type that is not a task-like type

A function literal is asynchronous under the same rules:

- A literal that declares a task-like return type uses that type's builder, as a named function does.
- A literal that declares no return type takes its task-like type from the slot it goes into: a typed local variable, a parameter or a return. When the slot leaves the result type open, as `spawn[T](body: () -> COROUTINE[T])` does, the compiler infers the result type from the body's returns.
- When several overloads take the same number of arguments, the body chooses the overload. A body that produces a value goes to a parameter whose task-like type has a result. A body that produces no value goes to a parameter whose task-like type has no result.
- A literal with no other information returns `Concurrency.Future` or `Concurrency.Future[T]`.

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

An asynchronous function whose return type has no result (`Concurrency.Future`, or a task-like type with no type argument) completes when its body reaches the end. So it needs no `return`, and gives no `definite-return` warning without one. An asynchronous function whose return type has a result still gives the warning, as any function that returns a value does. This applies whether or not the body awaits, because the declaration alone makes the function asynchronous. A bare `return;` returns the same completed result. A `Concurrency.Future` function completes through `Concurrency.Future.completed_task`. A task-like type declared in source completes through its builder, and the compiler calls the builder's members directly.

`await` can be used in the body of a `for` or `while` loop, and a `return` in such a body returns from the function through the loop. A `try`, `catch` or `finally` around code that awaits works as expected, including a `return` inside the `try`. An `await` inside a `catch` or `finally` *handler* is not yet supported. Reading `.result` on a returned task that faulted throws a `System.AggregateException`.

## asynchronous entry points

Top-level statements that `await` outside any function or function literal they contain become an entry returning `Concurrency.Future`. An `entry` function written to return `Concurrency.Future` or `Concurrency.Future[int]` is asynchronous in the same way. In either case the compiler synthesises the program's real entry point beside it, a private `_entry` taking no parameters or one `ARRAY[string]`, whose body is `Concurrency.run(() => entry(args, env))`. `run` drives the thread's event loop until the future completes, then returns the future's result, which is the exit status for a `Concurrency.Future[int]`, or throws what the future threw. That behaves the same on every target: the program's output is in the order its awaits resume, an exception that escapes is an unhandled exception, with exit status 134, and the `int` an entry returns is the exit status.

An asynchronous `entry` takes the parameters any `entry` takes, `string[]` or `ARRAY[string]` and `Ghul.Environment`, in either order. The compiler decides that an `entry` is asynchronous from its declaration, before it knows any types, so it recognises the return type by name: `Concurrency.Future` or `Concurrency.Future[int]` written in full, or `Future` named through a `use` of `Concurrency`, of `Concurrency.Future`, or an alias for it. Another task-like type, such as `Tasks.ValueTask`, is not recognised, and the entry is rejected for its return type. A `Concurrency.Future[T]` whose `T` is not `int` is rejected as `the task's result type is neither int nor void`.

Top-level statements return no value, asynchronous or not, so a `return` among them takes no value. A cell of a REPL or a session (`--submission`, `--cells`, `--session`, `--cell-link`) cannot `await` at the top level: the session runs a cell and takes the value of its final expression synchronously. The error is reported at the first `await`. Asynchronous code still runs to completion inside a cell through `Concurrency.run(() => ...)`.
