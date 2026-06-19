import { Writable } from "node:stream";

export interface TestIOBuffer {
  stream: Writable;
  text(): string;
}

function createBuffer(): TestIOBuffer {
  const chunks: Buffer[] = [];
  return {
    stream: new Writable({
      write(chunk, _encoding, callback) {
        chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(String(chunk)));
        callback();
      },
    }),
    text() {
      return Buffer.concat(chunks).toString("utf8");
    },
  };
}

export function createTestIO() {
  const stdout = createBuffer();
  const stderr = createBuffer();
  return {
    stdout: stdout.stream,
    stderr: stderr.stream,
    stdin: process.stdin,
    isInteractive: false,
    stdoutText: stdout.text,
    stderrText: stderr.text,
  };
}
