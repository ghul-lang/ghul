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

const node_fs = is_node ? await import("node:fs") : null;
const node_path = is_node ? await import("node:path") : null;

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
// - options.stdin: the program's standard input, as a string, or as a
//   function answering the next piece of it each time it is called, and
//   null once there is no more; by default the program reads no input
// - options.stdout, options.stderr: called with each piece of text the
//   program writes to that stream
// - options.onfile: called with the path and the whole content, as a
//   Uint8Array, each time the program writes a file; without it a program
//   run by Node has the file written relative to the working directory,
//   and one run anywhere else has its files discarded
//
// Answers the program's exit status.
export async function run(options = {}) {
    const args = options.args ?? [];
    const env = options.env ?? {};
    const stdout = options.stdout ?? (() => {});
    const stderr = options.stderr ?? (() => {});

    const sinks = [null, stdout, stderr];
    const onfile = options.onfile ?? (is_node ? node_file_writer(stderr) : () => {});
    const input = input_reader(options.stdin);

    const started = performance.now();

    let instance = null;
    const callbacks = (id) => instance.exports._run_callback(id);

    const host = {
        write(text, stream) {
            (sinks[stream] ?? stdout)(String(text));
        },
        flush(_stream) {},

        file_written(path, content) {
            onfile(String(path), base64_bytes(String(content)));
        },

        stdin_read_line: () => input.read_line(),
        stdin_read: () => input.read(),
        stdin_peek: () => input.peek(),
        stdin_read_to_end: () => input.read_to_end(),

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
        bigint_from_ulong: (value) => BigInt.asUintN(64, value),
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
        // Two's complement in as few hex digits as hold the value and its
        // sign, as .NET writes a BigInteger under `X`.
        bigint_to_hex(value, upper) {
            let digits = (value < 0n ? ~value : value).toString(16).length;
            let text = value < 0n ? ((1n << (4n * BigInt(digits))) + value).toString(16).padStart(digits, "0") : value.toString(16);

            if (value === 0n) {
                text = "0";
            } else if (parseInt(text[0], 16) >= 8 && value > 0n) {
                text = "0" + text;
            } else if (parseInt(text[0], 16) < 8 && value < 0n) {
                text = "f" + text;
            }

            return upper ? text.toUpperCase() : text;
        },
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

// Standard input, read as the program asks for it: a line, a character,
// or everything left. Text is pulled from `source` a piece at a time, so a
// program reading a line at a time from a terminal gets each line as it is
// typed rather than waiting for the end of the input. Lines end at \n,
// \r\n or \r, as .NET's ReadLine ends them, and a character is a UTF-16
// code unit, as .NET's Read answers one.
function input_reader(source) {
    let pull;

    if (typeof source === "function") {
        pull = source;
    } else {
        let rest = source ?? null;

        pull = () => {
            const piece = rest;
            rest = null;
            return piece;
        };
    }

    let text = "";
    let at = 0;
    let ended = false;

    // Adds the next piece of input to what is buffered, answering whether
    // there was one.
    const more = () => {
        while (!ended) {
            const piece = pull();

            if (piece === null || piece === undefined) {
                ended = true;
                break;
            }

            if (piece.length > 0) {
                text = text.slice(at) + piece;
                at = 0;
                return true;
            }
        }

        return false;
    };

    return {
        read_line() {
            let from = at;

            for (;;) {
                let end = -1;

                for (let i = from; i < text.length; i++) {
                    const c = text.charCodeAt(i);

                    if (c === 10 || c === 13) {
                        end = i;
                        break;
                    }
                }

                if (end >= 0) {
                    // A \r at the end of what is buffered may be the first
                    // half of a \r\n, so the next piece decides.
                    if (text.charCodeAt(end) === 13 && end + 1 === text.length && !ended) {
                        const offset = end - at;

                        more();
                        end = at + offset;
                    }

                    const line = text.slice(at, end);
                    const crlf = text.charCodeAt(end) === 13 && text.charCodeAt(end + 1) === 10;

                    at = end + (crlf ? 2 : 1);

                    return line;
                }

                const scanned = text.length - at;

                if (!more()) {
                    if (at < text.length) {
                        const line = text.slice(at);
                        at = text.length;
                        return line;
                    }

                    return null;
                }

                from = at + scanned;
            }
        },

        read() {
            if (at >= text.length && !more()) {
                return -1;
            }

            return text.charCodeAt(at++);
        },

        peek() {
            if (at >= text.length && !more()) {
                return -1;
            }

            return text.charCodeAt(at);
        },

        read_to_end() {
            while (more()) {}

            const rest = text.slice(at);
            at = text.length;

            return rest;
        },
    };
}

// The bytes standard, padded base64 text stands for.
function base64_bytes(text) {
    if (is_node) {
        return new Uint8Array(Buffer.from(text, "base64"));
    }

    if (typeof Uint8Array.fromBase64 === "function") {
        return Uint8Array.fromBase64(text);
    }

    const binary = atob(text);
    const bytes = new Uint8Array(binary.length);

    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
    }

    return bytes;
}

// Writes each file the program writes under the working directory,
// creating the directories it names. A path that is absolute or climbs
// with `..` would reach outside it, so it is reported on standard error
// and not written, and the program carries on.
function node_file_writer(stderr) {
    return (path, bytes) => {
        const segments = path.split(/[\\/]/);

        if (node_path.isAbsolute(path) || /^[A-Za-z]:/.test(path) || segments.includes("..")) {
            stderr(`file ${path} not written: only a path within the working directory can be written\n`);

            return;
        }

        node_fs.mkdirSync(node_path.dirname(path), { recursive: true });
        node_fs.writeFileSync(path, bytes);
    };
}

// Node's standard input as pieces of text, read synchronously so the
// program can block on it. Input arriving on a non-blocking descriptor is
// waited for rather than taken as the end.
function node_stdin(readSync) {
    const buffer = Buffer.alloc(65536);
    const decoder = new TextDecoder();
    const pause = new Int32Array(new SharedArrayBuffer(4));
    let done = false;

    return () => {
        while (!done) {
            let count;

            try {
                count = readSync(0, buffer, 0, buffer.length, null);
            } catch (error) {
                if (error.code === "EAGAIN") {
                    Atomics.wait(pause, 0, 0, 5);
                    continue;
                }

                if (error.code === "EOF") {
                    count = 0;
                } else {
                    throw error;
                }
            }

            if (count === 0) {
                done = true;
                const rest = decoder.decode();
                return rest.length > 0 ? rest : null;
            }

            const piece = decoder.decode(buffer.subarray(0, count), { stream: true });

            if (piece.length > 0) {
                return piece;
            }
        }

        return null;
    };
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
    const { readSync } = await import("node:fs");

    process.exitCode = await run({
        args: process.argv.slice(2),
        env: { ...process.env },
        stdin: node_stdin(readSync),
        stdout: (text) => process.stdout.write(text),
        stderr: (text) => process.stderr.write(text),
    });
}
