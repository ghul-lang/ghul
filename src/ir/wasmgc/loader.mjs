// Runs a ghūl program compiled for the wasm target.
//
// The compiler writes this file beside the module it builds, naming the
// module below. Run directly by Node (`node program.mjs args...`) it runs
// the program with the process's arguments, environment and console, and
// leaves the program's exit status as the process's. A web page imports
// it and calls `run` with the same things as options.

const MODULE_FILE = "__GHUL_MODULE_FILE__";

// .NET's exit status when a program ends on an unhandled exception: the
// runtime aborts, which a shell sees as 128 + SIGABRT.
const UNHANDLED_EXCEPTION_EXIT_CODE = 134;

const is_node = typeof process !== "undefined" && process.versions?.node !== undefined;

class Exit extends Error {
    constructor(code) {
        super(`exit ${code}`);
        this.code = code;
    }
}

// Runs the program.
//
// - options.module: the module's bytes, a Response, or a URL to fetch;
//   by default the module beside this file
// - options.args: the program's command-line arguments
// - options.env: the program's environment, as an object of strings
// - options.stdout, options.stderr: called with each piece of text the
//   program writes to that stream
//
// Answers the program's exit status.
export async function run(options = {}) {
    const args = options.args ?? [];
    const env = options.env ?? {};
    const stdout = options.stdout ?? (() => {});
    const stderr = options.stderr ?? (() => {});

    const sinks = [null, stdout, stderr];

    const started = performance.now();

    let instance = null;
    const callbacks = (id) => instance.exports._run_callback(id);

    const host = {
        write(text, stream) {
            (sinks[stream] ?? stdout)(String(text));
        },
        flush(_stream) {},

        argument_count: () => args.length,
        argument: (index) => args[index],

        environment_lookup: (name) => env[name] ?? null,
        environment_count: () => Object.keys(env).length,
        environment_name: (index) => Object.keys(env)[index],

        exit(code) {
            throw new Exit(code);
        },

        wall_clock_milliseconds: () => Date.now(),
        monotonic_milliseconds: () => performance.now() - started,

        random_u32: () => crypto.getRandomValues(new Uint32Array(1))[0] | 0,

        schedule_timer(delay_milliseconds, id) {
            setTimeout(() => callbacks(id), delay_milliseconds);
        },
        queue_microtask(id) {
            queueMicrotask(() => callbacks(id));
        },
    };

    const imports = { "ghul:host": host };
    const compile_options = { builtins: ["js-string"] };

    const source = await load(options.module ?? new URL(MODULE_FILE, import.meta.url));
    ({ instance } = await WebAssembly.instantiate(source, imports, compile_options));

    try {
        instance.exports._start();

        return instance.exports._exit_code();
    } catch (error) {
        if (error instanceof Exit) {
            return error.code;
        }

        stderr(`Unhandled exception. ${describe(error, instance)}\n`);

        return UNHANDLED_EXCEPTION_EXIT_CODE;
    }
}

async function load(module) {
    if (module instanceof ArrayBuffer || ArrayBuffer.isView(module)) {
        return module;
    }

    if (is_node && module instanceof URL && module.protocol === "file:") {
        const { readFile } = await import("node:fs/promises");

        return readFile(module);
    }

    const response = module instanceof Response ? module : await fetch(module);

    return response.arrayBuffer();
}

// The first line .NET prints for an unhandled exception, after its
// "Unhandled exception. " prefix: the exception's type and message. An
// exception the program threw carries the module's exception tag, and
// its one argument is the exception itself, which `_describe_exception`
// describes where the module exports it.
function describe(error, instance) {
    const tag = instance?.exports._exception;

    if (tag && error instanceof WebAssembly.Exception && error.is(tag)) {
        const describe_exception = instance.exports._describe_exception;

        return describe_exception ? describe_exception(error.getArg(tag, 0)) : "an exception the program threw";
    }

    return `${error?.name ?? "Error"}: ${error?.message ?? String(error)}`;
}

if (is_node && process.argv[1] && import.meta.url === (await import("node:url")).pathToFileURL(process.argv[1]).href) {
    process.exitCode = await run({
        args: process.argv.slice(2),
        env: { ...process.env },
        stdout: (text) => process.stdout.write(text),
        stderr: (text) => process.stderr.write(text),
    });
}
