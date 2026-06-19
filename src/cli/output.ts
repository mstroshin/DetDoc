import type { Readable, Writable } from "node:stream";

export interface CliIO {
  stdout: Writable;
  stderr: Writable;
  stdin: Readable;
  isInteractive: boolean;
}

export function defaultIO(): CliIO {
  return {
    stdout: process.stdout,
    stderr: process.stderr,
    stdin: process.stdin,
    isInteractive: Boolean(process.stdin.isTTY && process.stdout.isTTY),
  };
}

export function writeLine(stream: Writable, text = ""): void {
  stream.write(`${text}\n`);
}
