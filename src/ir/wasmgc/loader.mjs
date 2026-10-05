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

        // The floating-point functions the core library's Math does not
        // compute in ghūl, each taking and answering doubles.
        math_sqrt: Math.sqrt,
        math_cbrt: Math.cbrt,
        math_floor: Math.floor,
        math_ceiling: Math.ceil,
        math_truncate: Math.trunc,
        math_sin: Math.sin,
        math_cos: Math.cos,
        math_tan: Math.tan,
        math_asin: Math.asin,
        math_acos: Math.acos,
        math_atan: Math.atan,
        math_atan2: Math.atan2,
        math_sinh: Math.sinh,
        math_cosh: Math.cosh,
        math_tanh: Math.tanh,
        math_exp: Math.exp,
        math_log: Math.log,
        math_log10: Math.log10,
        math_log2: Math.log2,
        math_pow: Math.pow,

        // The arbitrary-precision integer bigint is a box around, with the
        // semantics of .NET's BigInteger: division truncates, a remainder
        // takes the dividend's sign, and shifts are arithmetic.
        bigint_is_integer_text: (text) => /^\s*[+-]?[0-9]+\s*$/.test(text),
        bigint_parse: (text) => BigInt(text.trim()),
        bigint_from_int: (value) => BigInt(value),
        bigint_from_long: (value) => value,
        bigint_from_double: (value) => BigInt(Math.trunc(value)),
        bigint_to_long: (value) => BigInt.asIntN(64, value),
        bigint_to_double: (value) => Number(value),
        bigint_to_string: (value) => value.toString(),
        bigint_add: (a, b) => a + b,
        bigint_subtract: (a, b) => a - b,
        bigint_multiply: (a, b) => a * b,
        bigint_divide: (a, b) => a / b,
        bigint_remainder: (a, b) => a % b,
        bigint_negate: (a) => -a,
        bigint_compare: (a, b) => (a < b ? -1 : a > b ? 1 : 0),
        bigint_equals: (a, b) => a === b,
        bigint_hash: (a) => Number(BigInt.asIntN(32, a ^ (a >> 32n))),
        bigint_pow: (a, exponent) => a ** BigInt(exponent),
        bigint_mod_pow(value, exponent, modulus) {
            let result = 1n % modulus;
            let base = value % modulus;
            let rest = exponent;

            while (rest > 0n) {
                if (rest & 1n) {
                    result = (result * base) % modulus;
                }

                base = (base * base) % modulus;
                rest >>= 1n;
            }

            return result;
        },
        bigint_gcd(a, b) {
            let x = a < 0n ? -a : a;
            let y = b < 0n ? -b : b;

            while (y !== 0n) {
                [x, y] = [y, x % y];
            }

            return x;
        },
        bigint_shift_left: (a, places) => a << BigInt(places),
        bigint_shift_right: (a, places) => a >> BigInt(places),
        bigint_and: (a, b) => a & b,
        bigint_or: (a, b) => a | b,
        bigint_xor: (a, b) => a ^ b,
        bigint_not: (a) => ~a,
        bigint_bit_length: (a) => (a < 0n ? ~a : a) === 0n ? 0 : (a < 0n ? ~a : a).toString(2).length,

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
