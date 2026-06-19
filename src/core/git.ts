import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { DetDocError } from "./errors.js";

export interface DirtyFile {
  path: string;
  status: string;
}

export class GitRepository {
  constructor(readonly cwd: string) {}

  async git(args: string[], options: { input?: string } = {}): Promise<string> {
    return new Promise((resolve, reject) => {
      const child = spawn("git", ["-c", "core.quotepath=false", ...args], {
        cwd: this.cwd,
        stdio: [options.input === undefined ? "ignore" : "pipe", "pipe", "pipe"],
      });
      const stdout: Buffer[] = [];
      const stderr: Buffer[] = [];

      child.stdout?.on("data", (chunk: Buffer) => stdout.push(chunk));
      child.stderr?.on("data", (chunk: Buffer) => stderr.push(chunk));
      child.on("error", (error) => reject(new DetDocError(`git ${args.join(" ")} failed: ${error.message}`, "GIT_FAILED")));
      child.on("close", (code) => {
        const out = Buffer.concat(stdout).toString("utf8");
        const err = Buffer.concat(stderr).toString("utf8");
        if (code === 0) {
          resolve(out);
        } else {
          reject(new DetDocError(`git ${args.join(" ")} failed with exit code ${code}: ${err}`, "GIT_FAILED"));
        }
      });

      if (options.input !== undefined) {
        child.stdin?.end(options.input);
      }
    });
  }

  async root(): Promise<string> {
    return (await this.git(["rev-parse", "--show-toplevel"])).trim();
  }

  async headCommit(): Promise<string> {
    return (await this.git(["rev-parse", "HEAD"])).trim();
  }

  async statusPorcelain(): Promise<DirtyFile[]> {
    const output = await this.git(["status", "--porcelain=v1"]);
    return output
      .split("\n")
      .filter(Boolean)
      .map((line) => ({ status: line.slice(0, 2), path: line.slice(3) }));
  }

  async diff(): Promise<string> {
    return this.git(["diff", "--no-color", "--no-ext-diff", "--binary", "--", "."]);
  }

  async diffNameOnly(): Promise<string[]> {
    const output = await this.git(["diff", "--name-only", "--", "."]);
    return output.split("\n").filter(Boolean);
  }

  async applyPatch(patch: string): Promise<void> {
    await this.git(["apply", "--whitespace=nowarn"], { input: patch });
  }

  async changedFilesFromPatch(patch: string): Promise<string[]> {
    const output = await this.git(["apply", "--numstat", "-"], { input: patch });
    return output
      .split("\n")
      .filter(Boolean)
      .map((line) => line.split("\t").at(-1))
      .filter((path): path is string => Boolean(path));
  }

  async fileSha256(relativePath: string): Promise<string | null> {
    try {
      const bytes = await readFile(join(this.cwd, relativePath));
      return createHash("sha256").update(bytes).digest("hex");
    } catch {
      return null;
    }
  }
}
