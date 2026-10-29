#!/bin/bash
# Checks that the compiler reproduces itself on the wasm target, as
# llvm-bootstrap.sh does on llvm: the compiler builds a wasm compiler from
# its own source, that compiler, run by Node, builds the same source again,
# and the two passes must write the same module and the same loader. The
# second pass then serves one edit and one hover in analysis mode.
#
# usage: build/wasm-bootstrap.sh [<compiler dll> [<ghul-runtime>]]
#
# The defaults are publish/ghul.dll and the runtime library checkout under
# libraries/, where CI puts it. Node 24 or later has to be on the PATH;
# NODE_OPTIONS passes it options. The passes are written to a temporary
# directory, or to WASM_BOOTSTRAP_DIR where it is set, which is then kept.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

compiler=${1:-$root/publish/ghul.dll}
runtime=${2:-$root/libraries/ghul-runtime}

if [ -n "${WASM_BOOTSTRAP_DIR:-}" ]; then
    work=$WASM_BOOTSTRAP_DIR
    mkdir -p "$work"
else
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
fi

"$root/build/llvm-self-sources.sh" "$work" "$runtime"

cd "$root"

# Builds the compiler into <directory>/ghul.wasm and ghul.mjs. Both passes
# use the same names, since the loader finds its module by its own name.
build() {
    local name=$1
    local directory=$work/$name
    shift

    mkdir -p "$directory"

    local start=$(date +%s)

    if ! "$@" --target wasm --wasm-loader "$runtime/ghul-core/host/loader.mjs" --rtti --underscore-access legacy -o "$directory/ghul" @"$work/libraries.rsp" @"$work/sources.rsp" > "$work/$name.log" 2>&1; then
        grep -v ': warn: ' "$work/$name.log" || true
        echo "$name failed"
        exit 1
    fi

    echo "$name: $(( $(date +%s) - start ))s"
}

build pass-1 dotnet "$compiler"
build pass-2 node "$work/pass-1/ghul.mjs"

status=0

for file in ghul.wasm ghul.mjs; do
    if cmp -s "$work/pass-1/$file" "$work/pass-2/$file"; then
        echo "$file is identical"
    else
        echo "$file differs"
        status=1
    fi
done

# Analysis mode reads requests by reflection, which the wasm target answers
# from the descriptions --rtti compiles in.
printf '%s\n' \
    '{"kind":"set_open_files","paths":["a.ghul"]}' \
    '{"kind":"edit","files":[{"path":"a.ghul","source":"entry() is\n    let x: int = 1\nsi\n"}]}' \
    '{"kind":"hover","path":"a.ghul","line":2,"column":9}' |
    node "$work/pass-2/ghul.mjs" --target wasm --analyse @"$work/libraries.rsp" > "$work/analysis.json" 2> "$work/analysis.log" || true

if grep -q '"signature":"x: int"' "$work/analysis.json" && ! grep -q '"kind":"error"' "$work/analysis.json"; then
    echo "analysis mode answers"
else
    cat "$work/analysis.json" "$work/analysis.log"
    echo "analysis mode failed"
    status=1
fi

# The analyser reads requests while it compiles, so it says so, and it exits
# when left idle - with the client's end of the pipe still open, which is
# the case a worker blocked in a read once made hang.
for capability in mid-compile-queries compile-abort idle-exit; do
    if ! grep -q "\"$capability\"" "$work/analysis.json"; then
        echo "analysis mode does not advertise $capability"
        status=1
    fi
done

mkfifo "$work/idle.in"

node "$work/pass-2/ghul.mjs" --target wasm --analyse --analysis-idle-timeout 2 @"$work/libraries.rsp" \
    < "$work/idle.in" > "$work/idle.json" 2> "$work/idle.log" &
analyser=$!

# Held open until the analyser has had time to exit by itself.
exec 3> "$work/idle.in"
printf '%s\n' '{"kind":"set_open_files","paths":["a.ghul"]}' >&3

for _ in $(seq 1 150); do
    kill -0 "$analyser" 2>/dev/null || break
    sleep 0.2
done

if kill -0 "$analyser" 2>/dev/null; then
    kill "$analyser" 2>/dev/null || true
    echo "analysis mode did not exit when idle"
    status=1
elif grep -q '"kind":"exit"' "$work/idle.json"; then
    echo "analysis mode exits when idle"
else
    cat "$work/idle.json" "$work/idle.log"
    echo "analysis mode exited without saying why"
    status=1
fi

exec 3>&-

# A client that closes its end of the pipe, as the editor does on shutdown,
# ends the analyser rather than leaving it waiting for input.
printf '%s\n' '{"kind":"set_open_files","paths":["a.ghul"]}' \
    | timeout 60 node "$work/pass-2/ghul.mjs" --target wasm --analyse @"$work/libraries.rsp" \
    > "$work/closed.json" 2> "$work/closed.log" && closed=0 || closed=$?

if [ "$closed" -eq 0 ]; then
    echo "analysis mode exits when its input closes"
else
    cat "$work/closed.log"
    echo "analysis mode did not exit when its input closed (status $closed)"
    status=1
fi

# A function declared extern is an import the program's caller supplies, by
# name. The program is built by the wasm-built compiler and run with them.
mkdir -p "$work/extern"

if node "$work/pass-2/ghul.mjs" --target wasm --wasm-loader "$runtime/ghul-core/host/loader.mjs" -o "$work/extern/program" @"$work/libraries.rsp" "$root/build/wasm-externs/test.ghul" > "$work/extern.log" 2>&1 &&
    node "$root/build/wasm-externs/run.mjs" "$work/extern/program.mjs" > "$work/extern.out" 2>> "$work/extern.log" &&
    cmp -s "$work/extern.out" "$root/build/wasm-externs/expected.txt"; then
    echo "extern functions are supplied by the caller"
else
    cat "$work/extern.log" "$work/extern.out" 2>/dev/null
    echo "extern functions were not supplied by the caller"
    status=1
fi

exit $status
