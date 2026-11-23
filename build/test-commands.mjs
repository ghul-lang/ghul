// Reads the build commands `ghul-test --commands` writes, one JSON object a
// line, and writes the selected ones for a shell script to read with
// `read -r -d ''`, each field ended by a NUL:
//
//   test, target, directory, executable, output, the number of options,
//   each option, the number of sources, each source
//
// Usage: node build/test-commands.mjs <commands.jsonl> [--target <name>]
//            [--not-target <name>] [--in-place]
//
// --target keeps only commands for that target, and --not-target drops
// them. --in-place keeps only tests built in their own directory: a test
// run under a target through build_targets is built in a copy under
// .targets/.

import { readFileSync } from "node:fs";

const [file, ...options] = process.argv.slice(2);

let target = null;
let notTarget = null;
let inPlace = false;

for (let i = 0; i < options.length; i++) {
    if (options[i] === "--target") {
        target = options[++i];
    } else if (options[i] === "--not-target") {
        notTarget = options[++i];
    } else if (options[i] === "--in-place") {
        inPlace = true;
    } else {
        console.error(`test-commands: unknown option ${options[i]}`);
        process.exit(2);
    }
}

const fields = [];

for (const line of readFileSync(file, "utf8").split("\n")) {
    if (line.trim() === "") {
        continue;
    }

    const command = JSON.parse(line);

    if ((target && command.target !== target) ||
        (notTarget && command.target === notTarget) ||
        (inPlace && command.directory.includes("/.targets/"))) {
        continue;
    }

    fields.push(
        command.test,
        command.target,
        command.directory,
        command.executable,
        command.output ?? "",
        String(command.options.length),
        ...command.options,
        String(command.sources.length),
        ...command.sources);
}

process.stdout.write(fields.map(field => `${field}\0`).join(""));
