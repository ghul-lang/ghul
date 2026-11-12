// Runs a ghūl program compiled for the wasm target.
//
// The compiler writes this file, the same every time, beside the module it
// builds: the module's name with the extension `.mjs`, loading the module
// beside it with the extension `.wasm`. Run directly by Node
// (`node program.mjs args...`) it runs the program with the process's
// arguments, environment and console, and leaves the program's exit status
// as the process's. A web page imports it and calls `run` with the same
// things as options.

// The module this loader runs when it is not handed one: the file beside it
// with the same name and the extension `.wasm`.
function sibling_module() {
    const url = new URL(import.meta.url);

    url.pathname = url.pathname.replace(/\.mjs$/, ".wasm");

    return url;
}


// .NET's exit status when a program ends on an unhandled exception: the
// runtime aborts, which a shell sees as 128 + SIGABRT.
const UNHANDLED_EXCEPTION_EXIT_CODE = 134;

const is_node = typeof process !== "undefined" && process.versions?.node !== undefined;

const node_fs = is_node ? await import("node:fs") : null;
const node_path = is_node ? await import("node:path") : null;
const node_child_process = is_node ? await import("node:child_process") : null;
const node_worker_threads = is_node ? await import("node:worker_threads") : null;
const node_os = is_node ? await import("node:os") : null;
const node_tty = is_node ? await import("node:tty") : null;
const node_v8 = is_node ? await import("node:v8") : null;
const node_vm = is_node ? await import("node:vm") : null;

class Exit extends Error {
    constructor(code) {
        super(`exit ${code}`);
        this.code = code;
    }
}

const TERMINAL_STREAMS = ["stdin", "stdout", "stderr"];

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
// - options.files: the files the program starts with, as an object from
//   path to content, each content text, which is read as UTF-8, or bytes;
//   by default it starts with none. A path is relative to the program's
//   root directory, which is also its current directory
// - options.onfile: called with the path and the whole content, as a
//   Uint8Array, each time the program writes a file; without it a program
//   run by Node has the file written relative to the working directory,
//   and one run anywhere else has its files discarded
// - options.file_system: whether the program reads and writes the real
//   file system rather than files in memory; by default it does when run
//   by Node with neither options.files nor options.onfile given, and never
//   anywhere else, which has no file system to reach
// - options.externs: the functions the program declares extern, as an object
//   from the name each is declared with to the function that answers it; by
//   default there are none, and a program that declares one cannot start.
//   Numbers cross as numbers, a long as a BigInt, and a string as a string
// - options.terminal: whether each of the program's standard streams is a
//   terminal, as an object with a boolean for each of `stdin`, `stdout` and
//   `stderr` it wants to say; this is what the program reads as
//   `IO.Std.is_input_redirected` and the like. A stream left out is a
//   terminal when run by Node and the process's own stream is one, and is not
//   a terminal anywhere else: a page has no terminal, so an embedder whose
//   input box and output pane stand in for one says so here
// - options.stdout_buffer: how many characters of standard output to hold
//   before passing them to options.stdout in one piece; what is held is
//   passed on before a read from standard input, a write to standard error,
//   a process start or a flush, and when the program ends. By default, 0,
//   each piece is passed on as it is written
//
// Answers the program's exit status.
export async function run(options = {}) {
    const args = options.args ?? [];
    const env = options.env ?? {};
    const stdout = options.stdout ?? (() => {});
    const stderr = options.stderr ?? (() => {});

    // Standard output is held and written in pieces of at least
    // stdout_buffer characters where the embedder asks for that, as the
    // command line does when standard output is not a terminal. What is
    // held is written before a read from standard input, so a prompt is
    // seen first; before a write to standard error, so the two keep their
    // order; before a process starts; when the program flushes; and as the
    // program ends, however it ends. Standard error is never held.
    const stdout_buffer = options.stdout_buffer ?? 0;
    let held = [];
    let held_length = 0;

    const write_stdout = (text) => {
        if (stdout_buffer <= 0) {
            stdout(text);
            return;
        }

        held.push(text);
        held_length += text.length;

        if (held_length >= stdout_buffer) {
            flush_stdout();
        }
    };

    const flush_stdout = () => {
        if (held_length === 0) return;

        const text = held.join("");

        held = [];
        held_length = 0;

        stdout(text);
    };

    const write_stderr = (text) => {
        flush_stdout();
        stderr(text);
    };

    const sinks = [null, write_stdout, write_stderr];
    const onfile = options.onfile ?? (is_node ? node_file_writer(write_stderr) : () => {});
    const input = input_reader(options.stdin);
    const pump = stdin_pump(input, options.stdin, write_stderr);
    const input_files = Object.entries(options.files ?? {}).map(([path, content]) => [path, file_bytes(content)]);
    const files = (options.file_system ?? (options.files === undefined && options.onfile === undefined)) && is_node ? node_files() : no_files;
    const processes = is_node ? node_processes() : no_processes;

    const started = performance.now();

    let instance = null;
    const callbacks = (id) => instance.exports._run_callback(id);

    // A WasmGC reference has no address to hash, so each object is given a
    // number the first time its identity is hashed, held for as long as the
    // object lives.
    const identities = new WeakMap();
    let next_identity = 0;

    const host = {
        // A null string writes nothing, as it does on .NET.
        write(text, stream) {
            (sinks[stream] ?? write_stdout)(text === null ? "" : String(text));
        },
        flush: () => flush_stdout(),

        // Whether standard stream 0, 1 or 2 is a terminal: what the embedder
        // said, else the process's own stream under Node, else no.
        is_terminal(stream) {
            const said = options.terminal?.[TERMINAL_STREAMS[stream]];

            if (said !== undefined) return said === true;

            return is_node && stream >= 0 && stream <= 2 && node_tty.isatty(stream);
        },

        // Constructed here rather than thrown by the module, so the
        // exception records the stack it was thrown from.
        throw(exception) {
            const limit = Error.stackTraceLimit;
            Error.stackTraceLimit = FRAME_LIMIT;

            try {
                throw new WebAssembly.Exception(instance.exports._exception, [exception], { traceStack: true });
            } finally {
                Error.stackTraceLimit = limit;
            }
        },

        identity_hash(value) {
            let hash = identities.get(value);

            if (hash === undefined) {
                hash = Math.imul(++next_identity, 0x9E3779B1);
                identities.set(value, hash);
            }

            return hash;
        },

        file_written(path, content) {
            onfile(String(path), base64_bytes(String(content)));
        },

        ...files,
        ...processes,

        // A process shares the terminal, so what the program wrote comes first.
        process_run: () => (flush_stdout(), processes.process_run()),

        input_file_count: () => input_files.length,
        input_file_path: (index) => input_files[index][0],
        input_file_content: (index) => byte_text(input_files[index][1]),

        stdin_read_line: () => (flush_stdout(), pump.reader().read_line()),
        stdin_read: () => (flush_stdout(), pump.reader().read()),
        stdin_peek: () => (flush_stdout(), pump.reader().peek()),
        stdin_read_to_end: () => (flush_stdout(), pump.reader().read_to_end()),

        stdin_pending: () => (flush_stdout(), pump.pending()),
        stdin_wait: (ms) => (flush_stdout(), pump.wait(ms)),

        heap_bytes: (force) => heap_bytes(force),

        // The engine collects on its own schedule: there is nothing to tune.
        gc_collect_when_idle: () => true,
        gc_set_free_space_divisor: (divisor) => {},
        working_set_bytes: () => working_set_bytes(),

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
        bigint_fits_long: (value) => BigInt.asIntN(64, value) === value,
        bigint_to_double,
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

    const imports = { "ghul:host": host, "ghul:extern": options.externs ?? {} };
    const compile_options = { builtins: ["js-string"] };

    const source = await load(options.module ?? sibling_module());
    ({ instance } = await WebAssembly.instantiate(source, imports, compile_options));

    const unhandled = (error) => {
        stderr(`Unhandled exception. ${describe(error, instance)}\n${frames(error)}`);

        return UNHANDLED_EXCEPTION_EXIT_CODE;
    };

    let code;

    try {
        instance.exports._start();

        code = instance.exports._exit_code();
    } catch (error) {
        if (!(error instanceof Exit)) {
            // What the program wrote before it failed comes before the
            // report, if it can still be written.
            try {
                flush_stdout();
            } catch {
            }

            return unhandled(error);
        }

        code = error.code;
    }

    // A return and an exit both end here, and what is still held is
    // written; a write that fails now fails the program, as it would have
    // had it been written straight away.
    try {
        flush_stdout();
    } catch (error) {
        return unhandled(error);
    }

    return code;
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

        // Whether a complete line is buffered, or the input has ended with
        // text left to read. A carriage return that ends what is buffered
        // does not count: whether a line feed follows is not known yet.
        has_line() {
            for (let i = at; i < text.length; i++) {
                const c = text.charCodeAt(i);

                if (c === 10) {
                    return true;
                }

                if (c === 13) {
                    return i + 1 < text.length || ended;
                }
            }

            return ended && at < text.length;
        },

        // Pulls one more piece of input into the buffer, answering whether
        // there was one.
        fill() {
            return more();
        },

        // Takes what is buffered and leaves the reader empty, for a reader
        // that is taking over the stream.
        rest() {
            const buffered = text.slice(at);
            text = "";
            at = 0;

            return buffered;
        },
    };
}

// Standard input watched from another thread, for a program that asks
// whether input is waiting rather than only reading it - the analyser,
// which polls for requests while a compile runs and waits for one while
// it is idle.
//
// Nothing changes until the program first asks: reads go to the plain
// reader as they always did. The first pending() or wait() starts a
// worker thread that reads the process's real standard input, a line at a
// time, into a ring held in shared memory. What the plain reader had
// already buffered is handed over, and every later read takes its text from
// the ring, so the watcher and the program read one stream without racing
// over the descriptor. The worker blocks while the ring has no room, so
// input the program has not reached yet waits in the pipe rather than being
// dropped.
//
// The worker is only started when the program's input is the process's own
// standard input. For any other source - text handed to the loader, or a
// function a page supplies - there is no descriptor to watch: pending
// answers whether a complete line is already buffered, and wait reads
// until one is, or until the input ends.
//
// If the worker fails, the input ends: the worker writes the end of input
// into the ring itself on every failure it can see, and beats a heart in
// shared memory for the ones it cannot. A loop here that waits on the ring
// checks the heart, and treats a silent worker as the end of the input,
// since the bytes the worker had already taken from the descriptor cannot
// be put back. Events from the worker (error, exit) are not relied on:
// the program waits inside one synchronous call and never reaches its
// event loop.
function stdin_pump(reader, source, report) {
    const threaded = is_node && source?.process_stdin === true;

    // The ring: a byte stream between two offsets, each entry a four-byte
    // length and then that many bytes, copied in up to two pieces where it
    // crosses the end. USED is the bytes in the ring, which is what the
    // writer waits on; COUNT is the entries waiting, which is what the
    // reader asks; WAKE is the cell the worker sleeps on while the ring is
    // full and the reader nudges each time it takes an entry out.
    const RING_BYTES = 16 * 1024 * 1024;
    const HEADER = 64;
    const DATA = RING_BYTES - HEADER;
    const WRITE = 0;
    const READ = 1;
    const USED = 2;
    const COUNT = 3;
    const ENDED = 4;
    const WAKE = 5;
    const HEART = 6;
    const END_MARKER = 0xffffffff;

    // A line longer than this goes into the ring in pieces, each counted
    // as an entry of its own.
    const MAX_ENTRY = 1 << 20;

    let started = false;
    let ring = null;
    let view = null;
    let bytes = null;
    let decoder = null;
    let reading = null;
    let handoff = "";
    let input_ended = false;
    let heart = 0;
    let heart_at = 0;

    // Whether the worker is still beating. A worker that has died, or is
    // wedged, would otherwise leave a waiting loop here waiting for ever,
    // and the events that report a dead worker never reach a thread that
    // is inside a wasm call.
    const HEART_TIMEOUT_MS = 5000;

    const alive = () => {
        const now = Date.now();
        const beat = Atomics.load(view, HEART);

        if (beat !== heart || heart_at === 0) {
            heart = beat;
            heart_at = now;

            return true;
        }

        if (now - heart_at > HEART_TIMEOUT_MS && Atomics.load(view, ENDED) === 0) {
            end_input("it stopped responding");

            return false;
        }

        return true;
    };

    // Copies `source` into the ring at `offset`, wrapping, and answers the
    // offset after it.
    const put = (offset, source) => {
        const first = Math.min(source.length, DATA - offset);

        bytes.set(source.subarray(0, first), HEADER + offset);

        if (first < source.length) {
            bytes.set(source.subarray(first), HEADER);
        }

        return (offset + source.length) % DATA;
    };

    // Copies `length` bytes out of the ring from `offset`, wrapping.
    const get = (offset, length) => {
        const out = new Uint8Array(length);
        const first = Math.min(length, DATA - offset);

        out.set(bytes.subarray(HEADER + offset, HEADER + offset + first));

        if (first < length) {
            out.set(bytes.subarray(HEADER, HEADER + length - first), first);
        }

        return out;
    };

    const header_of = (length) => {
        const cell = new Uint8Array(4);

        new DataView(cell.buffer).setUint32(0, length, true);

        return cell;
    };

    // Takes one entry out of the ring: null when none waits, otherwise its
    // bytes, or null bytes for the end of the input.
    const take_entry = () => {
        if (Atomics.load(view, COUNT) <= 0) {
            return null;
        }

        const read = view[READ];
        const length = new DataView(get(read, 4).buffer).getUint32(0, true);
        const used = length === END_MARKER ? 4 : 4 + length;

        const entry = length === END_MARKER
            ? { bytes: null }
            : { bytes: get((read + 4) % DATA, length) };

        view[READ] = (read + used) % DATA;
        Atomics.sub(view, USED, used);
        Atomics.sub(view, COUNT, 1);
        Atomics.notify(view, WAKE);

        return entry;
    };

    // Text for the ring-backed reader: what the plain reader had buffered,
    // then each entry as it arrives, waiting for one when none has.
    const pull = () => {
        if (handoff.length > 0) {
            const text = handoff;
            handoff = "";
            return text;
        }

        // Once the end has been taken, nothing more arrives: answer the
        // end every time rather than waiting on the ring. The flushed
        // remainder of a truncated multi-byte sequence is itself text, so
        // the end has to be remembered across the call that returns it.
        if (input_ended) {
            return null;
        }

        for (;;) {
            const entry = take_entry();

            if (entry !== null) {
                if (entry.bytes === null) {
                    input_ended = true;

                    const rest = decoder.decode();
                    return rest.length > 0 ? rest : null;
                }

                const text = decoder.decode(entry.bytes, { stream: true });

                if (text.length > 0) {
                    return text;
                }

                continue;
            }

            Atomics.wait(view, WAKE, Atomics.load(view, WAKE), 50);
            alive();
        }
    };

    // The worker has gone: end the input from this side. Only the main
    // thread writes to the ring from here on.
    const end_input = (why) => {
        if (Atomics.load(view, ENDED) === 1) {
            return;
        }

        report(`ghūl: the stdin watcher stopped: ${why}`);

        view[WRITE] = put(view[WRITE], header_of(END_MARKER));
        Atomics.add(view, USED, 4);
        Atomics.add(view, COUNT, 1);
        Atomics.store(view, ENDED, 1);
        Atomics.notify(view, WAKE);
    };

    const start = () => {
        if (started) {
            return;
        }

        started = true;

        if (!threaded) {
            return;
        }

        ring = new SharedArrayBuffer(RING_BYTES);
        view = new Int32Array(ring);
        bytes = new Uint8Array(ring);
        decoder = new TextDecoder();

        const worker_source = `
            // Written as an async IIFE importing what it needs: an eval
            // worker takes its module format from the nearest
            // package.json to the loader's directory, so neither the
            // CommonJS nor the module spelling can be relied on alone.
            //
            // Standard input is read as a stream on this thread's event
            // loop rather than with a blocking read: a thread stuck in a
            // read cannot be stopped, and the process would then not exit
            // until the client closed its end of the pipe.
            (async () => {
                const fs = await import("node:fs");
                const net = await import("node:net");
                const tty = await import("node:tty");
                const { workerData } = await import("node:worker_threads");

                const ring = workerData.ring;
                const view = new Int32Array(ring);
                const bytes = new Uint8Array(ring);
                const WRITE = ${WRITE};
                const READ = ${READ};
                const USED = ${USED};
                const COUNT = ${COUNT};
                const ENDED = ${ENDED};
                const WAKE = ${WAKE};
                const HEART = ${HEART};
                const HEADER = ${HEADER};
                const DATA = ${DATA};
                const END_MARKER = ${END_MARKER};
                const MAX_ENTRY = ${MAX_ENTRY};
                const HIGH_WATER = 8 * 1024 * 1024;

                const put = (offset, source) => {
                    const first = Math.min(source.length, DATA - offset);

                    bytes.set(source.subarray(0, first), HEADER + offset);

                    if (first < source.length) {
                        bytes.set(source.subarray(first), HEADER);
                    }

                    return (offset + source.length) % DATA;
                };

                const header_of = (length) => {
                    const cell = new Uint8Array(4);

                    new DataView(cell.buffer).setUint32(0, length, true);

                    return cell;
                };

                // Writes one entry if the ring has room for it.
                function try_push(length, payload) {
                    const used = 4 + (payload === null ? 0 : payload.length);

                    if (DATA - Atomics.load(view, USED) < used) {
                        return false;
                    }

                    let write = put(view[WRITE], header_of(length));

                    if (payload !== null) {
                        write = put(write, payload);
                    }

                    view[WRITE] = write;
                    Atomics.add(view, USED, used);
                    Atomics.add(view, COUNT, 1);
                    Atomics.notify(view, WAKE);

                    return true;
                }

                // Resolves when the reader has taken something out of the
                // ring, or after a short while.
                function room() {
                    const waiting = Atomics.waitAsync(view, WAKE, Atomics.load(view, WAKE), 50);

                    return waiting.async ? waiting.value : Promise.resolve();
                }

                // Complete lines, each with the break that ended it, in the
                // order read, then null for the end of the input. Keeping
                // the break is what lets the reader on the other side tell
                // a complete line from the input's last piece, which has
                // none. A lone carriage return ends a line the way .NET's
                // ReadLine ends one, and one at the end of a read may be
                // the first half of a carriage return and line feed, so
                // the byte after it decides.
                const lines = [];
                let queued = 0;
                let parts = [];
                let held = null;

                function emit(buffer) {
                    lines.push(buffer);
                    queued += buffer.length;
                }

                function consume(chunk) {
                    const length = chunk.length;
                    let from = 0;
                    let i = 0;

                    if (held !== null && length > 0) {
                        if (chunk[0] === 10) {
                            emit(Buffer.concat([held, chunk.subarray(0, 1)]));
                            from = 1;
                            i = 1;
                        } else {
                            emit(held);
                        }

                        held = null;
                    }

                    for (; i < length; i++) {
                        const c = chunk[i];
                        let end;

                        if (c === 10) {
                            end = i + 1;
                        } else if (c === 13) {
                            if (i + 1 < length) {
                                end = chunk[i + 1] === 10 ? i + 2 : i + 1;
                            } else {
                                held = Buffer.concat([...parts, Buffer.from(chunk.subarray(from, i + 1))]);
                                parts = [];
                                from = length;
                                break;
                            }
                        } else {
                            continue;
                        }

                        emit(Buffer.concat([...parts, Buffer.from(chunk.subarray(from, end))]));
                        parts = [];
                        from = end;
                        i = end - 1;
                    }

                    if (from < length) {
                        parts.push(Buffer.from(chunk.subarray(from)));
                    }
                }

                function finish() {
                    if (held !== null) {
                        emit(held);
                        held = null;
                    }

                    if (parts.length > 0) {
                        emit(Buffer.concat(parts));
                        parts = [];
                    }

                    lines.push(null);
                }

                // Moves lines into the ring as it has room, pausing the
                // stream while a lot is waiting so a fast writer does not
                // grow this thread's memory without bound.
                let flushing = false;
                let stream = null;

                async function flush() {
                    if (flushing) {
                        return;
                    }

                    flushing = true;

                    while (lines.length > 0) {
                        const line = lines[0];

                        if (line === null) {
                            if (!try_push(END_MARKER, null)) {
                                await room();
                                continue;
                            }

                            Atomics.store(view, ENDED, 1);
                            Atomics.notify(view, WAKE);
                            lines.shift();
                            break;
                        }

                        let done = 0;

                        while (done < line.length) {
                            const piece = line.subarray(done, done + MAX_ENTRY);

                            if (!try_push(piece.length, piece)) {
                                await room();
                                continue;
                            }

                            done += piece.length;
                        }

                        queued -= line.length;
                        lines.shift();

                        if (queued < HIGH_WATER / 2) {
                            stream?.resume();
                        }
                    }

                    flushing = false;
                }

                // The program's thread cannot be told about a failure here
                // by an event while it is waiting on the ring - it runs
                // inside one synchronous call and never reaches its event
                // loop - so this thread ends the input itself on every way
                // out it can see, and beats a heart for the ones it cannot.
                let stopped = false;

                function stop(why) {
                    if (stopped) {
                        return;
                    }

                    stopped = true;

                    if (why !== null) {
                        try {
                            fs.writeSync(2, "ghūl: the stdin watcher stopped: " + why + "\\n");
                        } catch {}
                    }

                    finish();
                    flush();
                }

                const heart = setInterval(() => {
                    Atomics.add(view, HEART, 1);

                    if (Atomics.load(view, ENDED) === 1) {
                        clearInterval(heart);
                    }
                }, 500);

                process.on("uncaughtException", (error) => stop(error.message));

                try {
                    // The stream a descriptor needs: a terminal, a pipe or
                    // socket, or a file, as Node's own standard input
                    // chooses.
                    if (tty.isatty(0)) {
                        stream = new tty.ReadStream(0);
                    } else {
                        const stat = fs.fstatSync(0);

                        stream = stat.isFIFO() || stat.isSocket()
                            ? new net.Socket({ fd: 0, readable: true, writable: false })
                            : fs.createReadStream(null, { fd: 0, autoClose: false });
                    }

                    stream.on("data", (chunk) => {
                        consume(chunk);

                        if (queued > HIGH_WATER) {
                            stream.pause();
                        }

                        flush();
                    });

                    stream.on("end", () => stop(null));

                    // A pipe closed from the other end reads as the end.
                    stream.on("error", (error) => {
                        stop(error.code === "EOF" || error.code === "EPIPE" || error.code === "ECONNRESET" ? null : error.message);
                    });
                } catch (error) {
                    stop(error.message);
                }
            })();
        `;

        const worker = new node_worker_threads.Worker(worker_source, {
            eval: true,
            workerData: { ring },
        });

        worker.on("error", (error) => end_input(error.message));
        worker.on("exit", (code) => {
            if (Atomics.load(view, ENDED) === 0) {
                end_input("it exited with status " + code);
            }
        });

        worker.unref();
        heart_at = Date.now();

        handoff = reader.rest();
        reading = input_reader(pull);
    };

    return {
        pending() {
            start();

            if (reading === null) {
                return reader.has_line();
            }

            return reading.has_line() || Atomics.load(view, COUNT) > 0;
        },

        wait(ms) {
            start();

            if (reading === null) {
                while (!reader.has_line()) {
                    if (!reader.fill()) {
                        return true;
                    }
                }

                return true;
            }

            if (reading.has_line()) {
                return true;
            }

            const deadline = Date.now() + (ms > 0 ? ms : 3600000000);

            for (;;) {
                // The end of the input is something to read as well, and
                // stays so once it has been taken.
                if (Atomics.load(view, COUNT) > 0 || Atomics.load(view, ENDED) === 1) {
                    return true;
                }

                const slice = Math.min(deadline - Date.now(), 5);

                if (slice <= 0) {
                    return false;
                }

                Atomics.wait(view, WAKE, Atomics.load(view, WAKE), slice);
                alive();
            }
        },

        // The reader the program reads from: the plain one until the pump
        // has started, the ring-backed one after.
        reader() {
            return reading ?? reader;
        },
    };
}

// The bytes the engine reports in use on its heap, which is where
// WasmGC objects live. With `force`, a full collection runs first so the
// answer is what is live rather than what has not been reclaimed yet,
// as .NET's GC.GetTotalMemory(true) answers. Node does not expose its
// collector to a program unless asked at start-up, so the collector is
// obtained from a fresh context after switching the flag on; where that
// fails the answer is simply the unforced figure. Answers 0 where there
// is no process to ask, which a heap watchdog reads as under any limit.
let collect = undefined;

// The bytes of memory the process occupies, as Node counts the resident set,
// which is read without collecting. Answers 0 where there is no process to
// ask.
function working_set_bytes() {
    return is_node ? process.memoryUsage.rss() : 0;
}

function heap_bytes(force) {
    if (!is_node) {
        return 0;
    }

    if (force) {
        if (collect === undefined) {
            try {
                node_v8.setFlagsFromString("--expose-gc");
                collect = node_vm.runInNewContext("gc");
            } catch {
                collect = null;
            }
        }

        collect?.();
    }

    return process.memoryUsage().heapUsed;
}

// The double a bigint converts to, as .NET converts one: the magnitude
// truncated to the 53 bits a double holds, rather than rounded to the
// nearest, and infinity only from 2^1024 up. Number() rounds to the nearest,
// so where it lands above the magnitude the double below is the truncation.
function bigint_to_double(value) {
    const magnitude = value < 0n ? -value : value;
    let result = Number(magnitude);

    if (result === Infinity ? magnitude < DOUBLE_LIMIT : BigInt(result) > magnitude) {
        double_bits[0] = result;
        double_words[0] -= 1n;
        result = double_bits[0];
    }

    return value < 0n ? -result : result;
}

const DOUBLE_LIMIT = 2n ** 1024n;
const double_bits = new Float64Array(1);
const double_words = new BigUint64Array(double_bits.buffer);

// The bytes a file's content stands for: text is UTF-8, and bytes are as
// they are.
function file_bytes(content) {
    if (typeof content === "string") {
        return new TextEncoder().encode(content);
    }

    if (content instanceof ArrayBuffer) {
        return new Uint8Array(content);
    }

    return new Uint8Array(content.buffer, content.byteOffset, content.byteLength);
}

// Text with one code unit for each of `bytes`, which is how the program is
// handed a file's content.
function byte_text(bytes) {
    let text = "";

    for (let at = 0; at < bytes.length; at += 8192) {
        text += String.fromCharCode.apply(null, bytes.subarray(at, at + 8192));
    }

    return text;
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

// The host's file operations over Node's file system, each answering 0
// or one of core's failure codes as libghul's do: 1 for a missing file, 2
// for a missing directory, 3 for access denied and 4 for any other
// failure. A file's bytes cross as a string holding one code unit for
// each byte.
function node_files() {
    let last_error = 0;
    let entries = [];

    const code_for = (error, path) => {
        switch (error?.code) {
        case "ENOENT":
            return node_fs.existsSync(node_path.dirname(path)) ? 1 : 2;
        case "ENOTDIR":
            return 2;
        case "EACCES":
        case "EPERM":
        case "EISDIR":
        case "EROFS":
            return 3;
        default:
            return 4;
        }
    };

    const attempt = (path, action) => {
        try {
            action();
            return 0;
        } catch (error) {
            return code_for(error, path);
        }
    };

    const is_directory = (path) => node_fs.statSync(path, { throwIfNoEntry: false })?.isDirectory() ?? false;

    return {
        file_system: () => 1,
        file_current_directory: () => process.cwd(),

        file_kind(path) {
            const status = node_fs.statSync(String(path), { throwIfNoEntry: false });

            return status === undefined ? 0 : status.isDirectory() ? 2 : 1;
        },

        file_read_text(path) {
            try {
                return node_fs.readFileSync(String(path)).toString("latin1");
            } catch (error) {
                last_error = code_for(error, String(path));
                return null;
            }
        },

        file_last_error: () => last_error,

        // A descriptor reading the file at `path` as it is asked for, or -1
        // with the reason in file_last_error.
        file_open_read(path) {
            try {
                return node_fs.openSync(String(path), "r");
            } catch (error) {
                last_error = code_for(error, String(path));
                return -1;
            }
        },

        // At most `count` bytes of the file `descriptor`, one code unit for
        // each byte, empty at its end, or null with the reason in
        // file_last_error.
        file_read_chunk(descriptor, count) {
            try {
                const buffer = Buffer.alloc(Math.max(0, count));
                const got = node_fs.readSync(descriptor, buffer, 0, buffer.length, null);

                return buffer.toString("latin1", 0, got);
            } catch (error) {
                last_error = code_for(error, "");
                return null;
            }
        },

        file_close: (descriptor) => attempt("", () => node_fs.closeSync(descriptor)),

        file_write_text(path, content, append) {
            const bytes = Buffer.from(String(content), "latin1");

            return attempt(String(path), () =>
                append ? node_fs.appendFileSync(String(path), bytes) : node_fs.writeFileSync(String(path), bytes));
        },

        // A file that is not there is no failure, as .NET's File.Delete
        // does nothing for one, unless its directory is not there either.
        file_delete(path) {
            const code = attempt(String(path), () => node_fs.unlinkSync(String(path)));

            return code === 1 ? 0 : code;
        },

        file_rename: (from, to) => attempt(String(from), () => node_fs.renameSync(String(from), String(to))),

        // When `path` was last written, in milliseconds since the Unix
        // epoch, or -1 where there is nothing there.
        file_modified_milliseconds: (path) => node_fs.statSync(String(path), { throwIfNoEntry: false })?.mtimeMs ?? -1,

        // The permission bits of `path`, or -1 where there is nothing there.
        file_mode: (path) => {
            const status = node_fs.statSync(String(path), { throwIfNoEntry: false });

            return status === undefined ? -1 : status.mode & 0o7777;
        },

        file_set_mode: (path, mode) => attempt(String(path), () => node_fs.chmodSync(String(path), mode & 0o7777)),
        directory_set_current: (path) => attempt(String(path), () => process.chdir(String(path))),
        directory_create: (path) => attempt(String(path), () => node_fs.mkdirSync(String(path), { recursive: true })),

        directory_delete: (path, recursive) =>
            attempt(String(path), () => recursive ? node_fs.rmSync(String(path), { recursive: true }) : node_fs.rmdirSync(String(path))),

        // The files, or the directories, directly in `path`, held for
        // directory_entry to answer one at a time; a link counts as what
        // it leads to.
        directory_entries(path, directories) {
            try {
                entries = node_fs.readdirSync(String(path), { withFileTypes: true })
                    .filter((entry) => (entry.isDirectory() || (entry.isSymbolicLink() && is_directory(node_path.join(String(path), entry.name)))) === Boolean(directories))
                    .map((entry) => entry.name);

                return entries.length;
            } catch (error) {
                return -code_for(error, String(path));
            }
        },

        directory_entry: (index) => entries[index],
    };
}

// The host's process operations, as libghul's are: a program is named, its
// arguments added one at a time, and then run to completion sharing this
// process's standard input, its output and error captured. A run answers
// the exit status, a program killed by a signal 128 plus its number, or -1
// where it could not be started, process_failure then saying why: 1 for
// no such program, 2 for anything else.
function node_processes() {
    let file = "";
    let args = [];
    let result = null;
    let failure = 0;

    return {
        process_begin(file_name) {
            file = String(file_name);
            args = [];
            result = null;
            failure = 0;
        },

        process_add_argument(argument) {
            args.push(String(argument));
        },

        process_run() {
            result = node_child_process.spawnSync(file, args, { stdio: ["inherit", "pipe", "pipe"], maxBuffer: 1 << 30 });

            if (result.error !== undefined) {
                failure = result.error.code === "ENOENT" ? 1 : 2;
                return -1;
            }

            if (result.status === null) {
                return 128 + (node_os.constants.signals[result.signal] ?? 0);
            }

            return result.status;
        },

        process_failure: () => failure,
        process_output: () => result?.stdout?.toString("utf8") ?? null,
        process_error: () => result?.stderr?.toString("utf8") ?? null,

        // The machine in Node's own words: `linux`, `darwin` or `win32`,
        // and `x64` or `arm64`.
        os_platform: () => process.platform,
        os_architecture: () => process.arch,
        process_id: () => process.pid,
        home_directory: () => node_os.homedir(),

        // Blocks the program for `milliseconds`, as Thread.Sleep does.
        sleep: (milliseconds) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, Math.max(0, milliseconds)),

    };
}

// What a program that cannot start another one is told: that it could not.
// The machine's name for itself is the engine's, since a page has no other.
const no_processes = {
    process_begin: () => {},
    process_add_argument: () => {},
    process_run: () => -1,
    process_failure: () => 2,
    process_output: () => null,
    process_error: () => null,
    os_platform: () => "browser",
    os_architecture: () => "wasm",
    process_id: () => 0,
    home_directory: () => "/",
    sleep: sleep_in_page,
};

// Blocks for `milliseconds` where the engine lets the thread wait, which a
// worker does and a page's main thread does not; there it spins instead, so
// the program still waits as long as it asked to.
function sleep_in_page(milliseconds) {
    const wanted = Math.max(0, milliseconds);

    try {
        Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, wanted);
    } catch {
        const until = performance.now() + wanted;

        while (performance.now() < until) {
        }
    }
}

// What a program that reads no real file system is told: that there is
// none to read. Core asks before using any other operation, but the module
// imports each one it can reach, so each is here, failing.
const no_files = {
    file_system: () => 0,
    file_current_directory: () => "/",
    file_kind: () => 0,
    file_read_text: () => null,
    file_last_error: () => 4,
    file_open_read: () => -1,
    file_read_chunk: () => null,
    file_close: () => 4,
    file_write_text: () => 4,
    file_delete: () => 4,
    file_rename: () => 4,
    file_modified_milliseconds: () => -1,
    file_mode: () => -1,
    file_set_mode: () => 4,
    directory_set_current: () => 4,
    directory_create: () => 4,
    directory_delete: () => 4,
    directory_entries: () => -4,
    directory_entry: () => "",
};

// Writes each piece of text to the descriptor `fd` before returning, as
// UTF-8. Node's own process.stdout writes what the descriptor takes at once
// and leaves the rest for the event loop, which does not run while the
// program blocks waiting for input, so a long line could sit unwritten for
// as long as the wait lasts. A descriptor that is non-blocking and full is
// waited on rather than given up on.
function node_output(writeSync, fd) {
    const pause = new Int32Array(new SharedArrayBuffer(4));

    return (text) => {
        const bytes = Buffer.from(text, "utf8");
        let offset = 0;

        while (offset < bytes.length) {
            try {
                offset += writeSync(fd, bytes, offset, bytes.length - offset);
            } catch (error) {
                if (error.code === "EAGAIN") {
                    Atomics.wait(pause, 0, 0, 1);
                    continue;
                }

                throw error;
            }
        }
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

    const pull = () => {
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

    // Says the pieces are the process's own standard input, which a worker
    // can read from the descriptor itself.
    pull.process_stdin = true;

    return pull;
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

// How many frames an exception the program throws records.
const FRAME_LIMIT = 100;

// The module's frames the error was thrown through, innermost first, one
// "   at <name>" line each, as the native target writes them. The engine's
// own and the loader's frames, and _start, which calls the entry, are
// left out.
function frames(error) {
    const stack = typeof error?.stack === "string" ? error.stack : "";
    let text = "";

    for (const line of stack.split("\n")) {
        const frame = /^\s*at (.*?) \(wasm:\/\/.*\)$/.exec(line) ?? /^\s*at (wasm:\/\/.*)$/.exec(line);

        if (frame && frame[1] !== "_start") {
            text += `   at ${frame[1]}\n`;
        }
    }

    return text;
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
    const { readSync, writeSync } = await import("node:fs");

    process.exitCode = await run({
        args: process.argv.slice(2),
        env: { ...process.env },
        stdin: node_stdin(readSync),
        stdout: node_output(writeSync, 1),
        stderr: node_output(writeSync, 2),
        stdout_buffer: node_tty.isatty(1) ? 0 : 64 * 1024,
    });
}
