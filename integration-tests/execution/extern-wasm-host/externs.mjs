// The host's side of extern-wasm-host: the functions the test declares extern.
export function add_one(value) { return value + 1; }
export function twice_long(value) { return value * 2n; }
export function shout(text) { return text.toUpperCase(); }
export function next_handle() { return 7n; }
