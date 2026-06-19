# DetDoc MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the DetDoc MVP CLI that turns Markdown diffs or explicit bugfix intent into approved, validated, replayable patches using embedded pi.

**Architecture:** DetDoc is a standalone TypeScript CLI with small core modules for config, git, worktrees, artifacts, planning, validation, approvals, and agent execution. The orchestration flow owns reproducibility and safety; pi is accessed through an `AgentRunner` boundary whose first real implementation is `PiSdkRunner`.

**Tech Stack:** TypeScript, Node.js 20+, Commander, YAML, Zod, picomatch, Vitest, pi SDK via `@earendil-works/pi-coding-agent`.

## Global Constraints

- Primary intent source: uncommitted Markdown documentation diffs.
- Secondary intent source: `detdoc fix "message"` bugfix text.
- MVP agent backend: embedded pi through the pi SDK.
- `detdoc run` rejects dirty non-documentation changes.
- `detdoc fix` rejects dirty non-documentation changes, allows dirty docs, and ignores dirty docs.
- Implementation always happens in a temporary git worktree created from `HEAD`.
- For `run`, only the Markdown diff is applied into the temporary worktree before agent execution.
- No code patch is applied to the main working tree without final user approval.
- Reproducibility guarantee is saved patch replay, not repeated LLM determinism.
- Successful runs write artifacts under `.detdoc/runs/<run-id>/`.
- Config path is `.detdoc/config.yml`.
- MVP commands: `init`, `diff`, `plan`, `run`, `fix`, `apply`, `replay`.
- No Claude Code or Codex adapter in the MVP.
- No custom Markdown DSL in the MVP.

---

## File Structure

Create these files over the tasks:

```text
package.json
tsconfig.json
vitest.config.ts
src/index.ts
src/cli/main.ts
src/cli/output.ts
src/cli/commands/init.ts
src/cli/commands/diff.ts
src/cli/commands/plan.ts
src/cli/commands/run.ts
src/cli/commands/fix.ts
src/cli/commands/apply.ts
src/cli/commands/replay.ts
src/core/agent/agent-runner.ts
src/core/agent/fake-agent-runner.ts
src/core/agent/pi-sdk-runner.ts
src/core/approval.ts
src/core/artifacts.ts
src/core/config.ts
src/core/diff.ts
src/core/errors.ts
src/core/flow.ts
src/core/git.ts
src/core/hash.ts
src/core/manifest.ts
src/core/paths.ts
src/core/plan.ts
src/core/validation.ts
src/core/worktree.ts
tests/helpers/git-fixture.ts
tests/helpers/test-io.ts
tests/config-init.test.ts
tests/git-policy.test.ts
tests/diff.test.ts
tests/worktree.test.ts
tests/plan.test.ts
tests/artifacts.test.ts
tests/validation.test.ts
tests/flow-run.test.ts
tests/apply-replay.test.ts
tests/pi-runner-smoke.test.ts
```

Responsibility map:

- `src/cli/*`: CLI parsing and user-facing command wiring only.
- `src/core/config.ts`: config defaults, parsing, validation, and init file content.
- `src/core/git.ts`: all git command execution and git-derived state.
- `src/core/paths.ts`: doc-file and deny-path matching.
- `src/core/diff.ts`: normalized Markdown diff collection.
- `src/core/worktree.ts`: temporary git worktree lifecycle.
- `src/core/manifest.ts`: deterministic task packet and run manifest creation.
- `src/core/artifacts.ts`: run directory writes and reads.
- `src/core/plan.ts`: structured plan schemas and plan validation.
- `src/core/agent/*`: agent boundary, fake runner, and pi SDK runner.
- `src/core/approval.ts`: approval abstraction and terminal implementation.
- `src/core/validation.ts`: structural patch validation and validation command execution.
- `src/core/flow.ts`: high-level `run`, `plan`, `fix`, `apply`, and `replay` orchestration.
- `tests/helpers/*`: fixture git repositories and deterministic CLI IO helpers.

---

### Task 1: Project Scaffold and CLI Skeleton

**Files:**
- Create: `package.json`
- Create: `tsconfig.json`
- Create: `vitest.config.ts`
- Create: `src/index.ts`
- Create: `src/cli/main.ts`
- Create: `src/cli/output.ts`
- Create: `src/core/errors.ts`
- Create: `tests/helpers/test-io.ts`
- Test: `tests/cli-skeleton.test.ts`

**Interfaces:**
- Consumes: none.
- Produces:
  - `runCli(argv: string[], io?: CliIO): Promise<number>`
  - `CliIO` with `stdout`, `stderr`, `stdin`, `isInteractive`
  - `DetDocError` and `toErrorMessage(error: unknown): string`

- [ ] **Step 1: Write the failing CLI skeleton test**

Create `tests/cli-skeleton.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { createTestIO } from "./helpers/test-io.js";
import { runCli } from "../src/cli/main.js";

describe("CLI skeleton", () => {
  it("prints help with the MVP commands", async () => {
    const io = createTestIO();
    const code = await runCli(["node", "detdoc", "--help"], io);

    expect(code).toBe(0);
    expect(io.stdoutText()).toContain("Usage: detdoc");
    expect(io.stdoutText()).toContain("init");
    expect(io.stdoutText()).toContain("diff");
    expect(io.stdoutText()).toContain("plan");
    expect(io.stdoutText()).toContain("run");
    expect(io.stdoutText()).toContain("fix");
    expect(io.stdoutText()).toContain("apply");
    expect(io.stdoutText()).toContain("replay");
  });

  it("returns a non-zero code for unknown commands", async () => {
    const io = createTestIO();
    const code = await runCli(["node", "detdoc", "unknown"], io);

    expect(code).toBe(1);
    expect(io.stderrText()).toContain("unknown command");
  });
});
```

Create `tests/helpers/test-io.ts`:

```ts
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
npm test -- tests/cli-skeleton.test.ts
```

Expected: the command fails because `package.json`, Vitest config, and `src/cli/main.ts` do not exist.

- [ ] **Step 3: Add package and TypeScript scaffold**

Create `package.json`:

```json
{
  "name": "detdoc",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "bin": {
    "detdoc": "./dist/index.js"
  },
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "dev": "tsx src/index.ts",
    "test": "vitest run",
    "typecheck": "tsc -p tsconfig.json --noEmit"
  },
  "dependencies": {
    "@earendil-works/pi-coding-agent": "latest",
    "commander": "^14.0.0",
    "picomatch": "^4.0.3",
    "typebox": "^1.0.58",
    "yaml": "^2.8.1",
    "zod": "^4.1.12"
  },
  "devDependencies": {
    "@types/node": "^24.0.0",
    "tsx": "^4.20.5",
    "typescript": "^5.9.3",
    "vitest": "^4.0.0"
  }
}
```

Create `tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "strict": true,
    "esModuleInterop": true,
    "forceConsistentCasingInFileNames": true,
    "skipLibCheck": true,
    "outDir": "dist",
    "rootDir": ".",
    "types": ["node"]
  },
  "include": ["src/**/*.ts", "tests/**/*.ts", "vitest.config.ts"]
}
```

Create `vitest.config.ts`:

```ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    include: ["tests/**/*.test.ts"],
    testTimeout: 30_000,
  },
});
```

Create `src/index.ts`:

```ts
#!/usr/bin/env node
import { runCli } from "./cli/main.js";

const exitCode = await runCli(process.argv);
process.exitCode = exitCode;
```

Create `src/core/errors.ts`:

```ts
export class DetDocError extends Error {
  constructor(message: string, readonly code = "DETDOC_ERROR") {
    super(message);
    this.name = "DetDocError";
  }
}

export function toErrorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}
```

Create `src/cli/output.ts`:

```ts
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
```

Create `src/cli/main.ts`:

```ts
import { Command } from "commander";
import { defaultIO, type CliIO, writeLine } from "./output.js";
import { toErrorMessage } from "../core/errors.js";

function addCommand(program: Command, name: string, description: string): void {
  program
    .command(name)
    .description(description)
    .allowUnknownOption(false)
    .action(() => {
      throw new Error(`Command '${name}' is registered but not implemented in this build`);
    });
}

export async function runCli(argv: string[], io: CliIO = defaultIO()): Promise<number> {
  const program = new Command();
  program
    .name("detdoc")
    .description("Deterministic documentation-driven agent orchestration")
    .exitOverride()
    .configureOutput({
      writeOut: (text) => io.stdout.write(text),
      writeErr: (text) => io.stderr.write(text),
    });

  addCommand(program, "init", "Create .detdoc/config.yml");
  addCommand(program, "diff", "Print normalized documentation diff");
  addCommand(program, "plan", "Create an approved implementation plan without applying code changes");
  addCommand(program, "run", "Run the documentation-diff workflow");
  addCommand(program, "fix", "Run the bugfix-intent workflow");
  addCommand(program, "apply", "Apply a saved DetDoc patch");
  addCommand(program, "replay", "Replay a saved DetDoc patch without calling an agent");

  try {
    await program.parseAsync(argv);
    return 0;
  } catch (error) {
    const message = toErrorMessage(error);
    if (message.includes("outputHelp")) return 0;
    if (message.includes("unknown command")) {
      writeLine(io.stderr, message);
      return 1;
    }
    if (message.includes("registered but not implemented")) {
      writeLine(io.stderr, message);
      return 1;
    }
    if (message.includes("(outputHelp)")) return 0;
    writeLine(io.stderr, message);
    return 1;
  }
}
```

- [ ] **Step 4: Install dependencies**

Run:

```bash
npm install
```

Expected: `package-lock.json` is created and dependencies install successfully.

- [ ] **Step 5: Run the test and typecheck**

Run:

```bash
npm test -- tests/cli-skeleton.test.ts
npm run typecheck
```

Expected: both commands pass.

- [ ] **Step 6: Commit**

```bash
git add package.json package-lock.json tsconfig.json vitest.config.ts src tests
git commit -m "chore: scaffold DetDoc TypeScript CLI"
```

---

### Task 2: Config Loader and `detdoc init`

**Files:**
- Create: `src/core/config.ts`
- Create: `src/cli/commands/init.ts`
- Modify: `src/cli/main.ts`
- Test: `tests/config-init.test.ts`

**Interfaces:**
- Consumes: `CliIO`, `DetDocError`.
- Produces:
  - `type DetDocConfig`
  - `defaultConfig(): DetDocConfig`
  - `defaultConfigYaml(): string`
  - `loadConfig(cwd: string): Promise<DetDocConfig>`
  - `initConfig(cwd: string): Promise<{ created: boolean; path: string }>`
  - `registerInitCommand(program: Command, io: CliIO): void`

- [ ] **Step 1: Write failing config/init tests**

Create `tests/config-init.test.ts`:

```ts
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createTestIO } from "./helpers/test-io.js";
import { runCli } from "../src/cli/main.js";
import { defaultConfig, initConfig, loadConfig } from "../src/core/config.js";

const dirs: string[] = [];

async function tempDir(): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "detdoc-config-"));
  dirs.push(dir);
  return dir;
}

afterEach(async () => {
  await Promise.all(dirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })));
});

describe("config", () => {
  it("creates default config", async () => {
    const cwd = await tempDir();
    const result = await initConfig(cwd);

    expect(result.created).toBe(true);
    expect(result.path).toBe(join(cwd, ".detdoc", "config.yml"));

    const text = await readFile(result.path, "utf8");
    expect(text).toContain("docs:");
    expect(text).toContain("validation:");
    expect(text).toContain("agent:");

    const config = await loadConfig(cwd);
    expect(config.docs.include).toEqual(["**/*.md"]);
    expect(config.agent.provider).toBe("pi-sdk");
  });

  it("does not overwrite an existing config", async () => {
    const cwd = await tempDir();
    await initConfig(cwd);
    const result = await initConfig(cwd);

    expect(result.created).toBe(false);
  });

  it("registers init command", async () => {
    const cwd = await tempDir();
    const oldCwd = process.cwd();
    process.chdir(cwd);
    try {
      const io = createTestIO();
      const code = await runCli(["node", "detdoc", "init"], io);
      expect(code).toBe(0);
      expect(io.stdoutText()).toContain("Created .detdoc/config.yml");
    } finally {
      process.chdir(oldCwd);
    }
  });

  it("has stable defaults", () => {
    expect(defaultConfig()).toEqual({
      docs: {
        include: ["**/*.md"],
        exclude: [".detdoc/**", "node_modules/**"],
      },
      paths: {
        deny: [".env", ".env.*", "node_modules/**", ".git/**"],
      },
      validation: {
        commands: [],
      },
      agent: {
        provider: "pi-sdk",
        model: null,
        thinking: "high",
      },
      worktree: {
        keepOnFailure: true,
      },
    });
  });
});
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
npm test -- tests/config-init.test.ts
```

Expected: FAIL because `src/core/config.ts` and init command registration do not exist.

- [ ] **Step 3: Implement config parsing and defaults**

Create `src/core/config.ts`:

```ts
import { access, mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import YAML from "yaml";
import { z } from "zod";
import { DetDocError } from "./errors.js";

const validationCommandSchema = z.object({
  name: z.string().min(1),
  run: z.string().min(1),
});

const configSchema = z.object({
  docs: z.object({
    include: z.array(z.string().min(1)).default(["**/*.md"]),
    exclude: z.array(z.string().min(1)).default([".detdoc/**", "node_modules/**"]),
  }),
  paths: z.object({
    deny: z.array(z.string().min(1)).default([".env", ".env.*", "node_modules/**", ".git/**"]),
  }),
  validation: z.object({
    commands: z.array(validationCommandSchema).default([]),
  }),
  agent: z.object({
    provider: z.literal("pi-sdk").default("pi-sdk"),
    model: z.string().nullable().default(null),
    thinking: z.enum(["off", "minimal", "low", "medium", "high", "xhigh"]).default("high"),
  }),
  worktree: z.object({
    keepOnFailure: z.boolean().default(true),
  }),
});

export type ValidationCommand = z.infer<typeof validationCommandSchema>;
export type DetDocConfig = z.infer<typeof configSchema>;

export function configPath(cwd: string): string {
  return join(cwd, ".detdoc", "config.yml");
}

export function defaultConfig(): DetDocConfig {
  return {
    docs: {
      include: ["**/*.md"],
      exclude: [".detdoc/**", "node_modules/**"],
    },
    paths: {
      deny: [".env", ".env.*", "node_modules/**", ".git/**"],
    },
    validation: {
      commands: [],
    },
    agent: {
      provider: "pi-sdk",
      model: null,
      thinking: "high",
    },
    worktree: {
      keepOnFailure: true,
    },
  };
}

export function defaultConfigYaml(): string {
  return YAML.stringify(defaultConfig());
}

async function exists(path: string): Promise<boolean> {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

export async function initConfig(cwd: string): Promise<{ created: boolean; path: string }> {
  const path = configPath(cwd);
  if (await exists(path)) return { created: false, path };

  await mkdir(dirname(path), { recursive: true });
  await mkdir(join(cwd, ".detdoc", "runs"), { recursive: true });
  await writeFile(path, defaultConfigYaml(), "utf8");
  await writeFile(join(cwd, ".detdoc", "runs", ".gitkeep"), "", "utf8");
  return { created: true, path };
}

export async function loadConfig(cwd: string): Promise<DetDocConfig> {
  const path = configPath(cwd);
  if (!(await exists(path))) {
    throw new DetDocError("Missing .detdoc/config.yml. Run `detdoc init` first.", "CONFIG_MISSING");
  }

  const raw = await readFile(path, "utf8");
  const parsed = YAML.parse(raw) as unknown;
  const result = configSchema.safeParse(parsed);
  if (!result.success) {
    throw new DetDocError(`Invalid .detdoc/config.yml: ${result.error.message}`, "CONFIG_INVALID");
  }
  return result.data;
}
```

- [ ] **Step 4: Implement init command and register it**

Create `src/cli/commands/init.ts`:

```ts
import type { Command } from "commander";
import type { CliIO } from "../output.js";
import { writeLine } from "../output.js";
import { initConfig } from "../../core/config.js";

export function registerInitCommand(program: Command, io: CliIO): void {
  program
    .command("init")
    .description("Create .detdoc/config.yml")
    .action(async () => {
      const result = await initConfig(process.cwd());
      if (result.created) {
        writeLine(io.stdout, "Created .detdoc/config.yml");
      } else {
        writeLine(io.stdout, ".detdoc/config.yml already exists");
      }
    });
}
```

Modify `src/cli/main.ts` so the command registration imports and uses `registerInitCommand`. The resulting file should look like this:

```ts
import { Command } from "commander";
import { registerInitCommand } from "./commands/init.js";
import { defaultIO, type CliIO, writeLine } from "./output.js";
import { toErrorMessage } from "../core/errors.js";

function addCommand(program: Command, name: string, description: string): void {
  program
    .command(name)
    .description(description)
    .allowUnknownOption(false)
    .action(() => {
      throw new Error(`Command '${name}' is registered but not implemented in this build`);
    });
}

export async function runCli(argv: string[], io: CliIO = defaultIO()): Promise<number> {
  const program = new Command();
  program
    .name("detdoc")
    .description("Deterministic documentation-driven agent orchestration")
    .exitOverride()
    .configureOutput({
      writeOut: (text) => io.stdout.write(text),
      writeErr: (text) => io.stderr.write(text),
    });

  registerInitCommand(program, io);
  addCommand(program, "diff", "Print normalized documentation diff");
  addCommand(program, "plan", "Create an approved implementation plan without applying code changes");
  addCommand(program, "run", "Run the documentation-diff workflow");
  addCommand(program, "fix", "Run the bugfix-intent workflow");
  addCommand(program, "apply", "Apply a saved DetDoc patch");
  addCommand(program, "replay", "Replay a saved DetDoc patch without calling an agent");

  try {
    await program.parseAsync(argv);
    return 0;
  } catch (error) {
    const message = toErrorMessage(error);
    if (message.includes("outputHelp")) return 0;
    if (message.includes("unknown command")) {
      writeLine(io.stderr, message);
      return 1;
    }
    if (message.includes("registered but not implemented")) {
      writeLine(io.stderr, message);
      return 1;
    }
    if (message.includes("(outputHelp)")) return 0;
    writeLine(io.stderr, message);
    return 1;
  }
}
```

- [ ] **Step 5: Run config and skeleton tests**

Run:

```bash
npm test -- tests/config-init.test.ts tests/cli-skeleton.test.ts
npm run typecheck
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add src tests package.json package-lock.json
git commit -m "feat: add config loader and init command"
```

---

### Task 3: Git Fixtures, Git Wrapper, Path Matching, and Dirty-State Policy

**Files:**
- Create: `tests/helpers/git-fixture.ts`
- Create: `src/core/git.ts`
- Create: `src/core/paths.ts`
- Test: `tests/git-policy.test.ts`

**Interfaces:**
- Consumes: `DetDocConfig`.
- Produces:
  - `createGitFixture(files: Record<string,string>): Promise<GitFixture>` for tests
  - `GitRepository` class with `root()`, `headCommit()`, `statusPorcelain()`, `diff()`, `applyPatch()`, `changedFilesFromPatch()`, `fileSha256()`
  - `isDocPath(path: string, config: DetDocConfig): boolean`
  - `isDeniedPath(path: string, config: DetDocConfig): boolean`
  - `assertRunDirtyPolicy(repo, config)`
  - `assertFixDirtyPolicy(repo, config)`

- [ ] **Step 1: Write failing dirty-policy tests**

Create `tests/git-policy.test.ts`:

```ts
import { writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { defaultConfig } from "../src/core/config.js";
import { DetDocError } from "../src/core/errors.js";
import { GitRepository } from "../src/core/git.js";
import { assertFixDirtyPolicy, assertRunDirtyPolicy, isDeniedPath, isDocPath } from "../src/core/paths.js";
import { createGitFixture, cleanupFixtures } from "./helpers/git-fixture.js";

afterEach(cleanupFixtures);

describe("path matching", () => {
  it("classifies docs and denied paths", () => {
    const config = defaultConfig();
    expect(isDocPath("docs/spec.md", config)).toBe(true);
    expect(isDocPath("README.md", config)).toBe(true);
    expect(isDocPath("src/index.ts", config)).toBe(false);
    expect(isDocPath(".detdoc/runs/x.md", config)).toBe(false);

    expect(isDeniedPath(".env", config)).toBe(true);
    expect(isDeniedPath(".env.local", config)).toBe(true);
    expect(isDeniedPath("node_modules/pkg/index.js", config)).toBe(true);
    expect(isDeniedPath("src/index.ts", config)).toBe(false);
  });
});

describe("dirty-state policy", () => {
  it("allows run when only docs are dirty", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const x = 1;\n" });
    await writeFile(join(fixture.cwd, "docs/spec.md"), "new\n", "utf8");

    await expect(assertRunDirtyPolicy(new GitRepository(fixture.cwd), defaultConfig())).resolves.toEqual([
      { path: "docs/spec.md", status: " M" },
    ]);
  });

  it("rejects run when code is dirty", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const x = 1;\n" });
    await writeFile(join(fixture.cwd, "src/app.ts"), "export const x = 2;\n", "utf8");

    await expect(assertRunDirtyPolicy(new GitRepository(fixture.cwd), defaultConfig())).rejects.toThrow(DetDocError);
  });

  it("allows fix with dirty docs but rejects dirty code", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const x = 1;\n" });
    await writeFile(join(fixture.cwd, "docs/spec.md"), "new\n", "utf8");
    await expect(assertFixDirtyPolicy(new GitRepository(fixture.cwd), defaultConfig())).resolves.toEqual([
      { path: "docs/spec.md", status: " M" },
    ]);

    await writeFile(join(fixture.cwd, "src/app.ts"), "export const x = 2;\n", "utf8");
    await expect(assertFixDirtyPolicy(new GitRepository(fixture.cwd), defaultConfig())).rejects.toThrow("dirty non-documentation changes");
  });
});
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
npm test -- tests/git-policy.test.ts
```

Expected: FAIL because git fixture, git wrapper, and path functions do not exist.

- [ ] **Step 3: Implement git test fixture**

Create `tests/helpers/git-fixture.ts`:

```ts
import { execFile } from "node:child_process";
import { mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const fixtureDirs: string[] = [];

export interface GitFixture {
  cwd: string;
  git(args: string[]): Promise<{ stdout: string; stderr: string }>;
}

export async function cleanupFixtures(): Promise<void> {
  await Promise.all(fixtureDirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })));
}

export async function createGitFixture(files: Record<string, string>): Promise<GitFixture> {
  const cwd = await import("node:fs/promises").then((fs) => fs.mkdtemp(join(tmpdir(), "detdoc-git-")));
  fixtureDirs.push(cwd);

  const git = async (args: string[]) => {
    const { stdout, stderr } = await execFileAsync("git", args, {
      cwd,
      env: {
        ...process.env,
        GIT_AUTHOR_NAME: "DetDoc Test",
        GIT_AUTHOR_EMAIL: "detdoc@example.com",
        GIT_COMMITTER_NAME: "DetDoc Test",
        GIT_COMMITTER_EMAIL: "detdoc@example.com",
      },
    });
    return { stdout, stderr };
  };

  await git(["init", "-b", "main"]);
  await git(["config", "user.name", "DetDoc Test"]);
  await git(["config", "user.email", "detdoc@example.com"]);

  for (const [path, content] of Object.entries(files)) {
    const absolute = join(cwd, path);
    await mkdir(dirname(absolute), { recursive: true });
    await writeFile(absolute, content, "utf8");
  }

  await git(["add", "."]);
  await git(["commit", "-m", "initial"]);

  return { cwd, git };
}
```

- [ ] **Step 4: Implement git wrapper**

Create `src/core/git.ts`:

```ts
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { promisify } from "node:util";
import { DetDocError } from "./errors.js";

const execFileAsync = promisify(execFile);

export interface DirtyFile {
  path: string;
  status: string;
}

export class GitRepository {
  constructor(readonly cwd: string) {}

  async git(args: string[], options: { input?: string } = {}): Promise<string> {
    try {
      const { stdout } = await execFileAsync("git", ["-c", "core.quotepath=false", ...args], {
        cwd: this.cwd,
        input: options.input,
        maxBuffer: 20 * 1024 * 1024,
      });
      return stdout;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      throw new DetDocError(`git ${args.join(" ")} failed: ${message}`, "GIT_FAILED");
    }
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
```

- [ ] **Step 5: Implement path matching and dirty policies**

Create `src/core/paths.ts`:

```ts
import picomatch from "picomatch";
import type { DetDocConfig } from "./config.js";
import { DetDocError } from "./errors.js";
import type { DirtyFile, GitRepository } from "./git.js";

function normalizePath(path: string): string {
  return path.replaceAll("\\", "/");
}

function matches(path: string, patterns: string[]): boolean {
  const normalized = normalizePath(path);
  return picomatch(patterns, { dot: true })(normalized);
}

export function isDocPath(path: string, config: DetDocConfig): boolean {
  const normalized = normalizePath(path);
  return matches(normalized, config.docs.include) && !matches(normalized, config.docs.exclude);
}

export function isDeniedPath(path: string, config: DetDocConfig): boolean {
  return matches(normalizePath(path), config.paths.deny);
}

function nonDocDirty(files: DirtyFile[], config: DetDocConfig): DirtyFile[] {
  return files.filter((file) => !isDocPath(file.path, config));
}

export async function assertRunDirtyPolicy(repo: GitRepository, config: DetDocConfig): Promise<DirtyFile[]> {
  const dirty = await repo.statusPorcelain();
  const offenders = nonDocDirty(dirty, config);
  if (offenders.length > 0) {
    throw new DetDocError(
      `detdoc run requires dirty changes only in documentation files. Found dirty non-documentation changes: ${offenders.map((file) => file.path).join(", ")}`,
      "DIRTY_NON_DOC_CHANGES",
    );
  }
  return dirty;
}

export async function assertFixDirtyPolicy(repo: GitRepository, config: DetDocConfig): Promise<DirtyFile[]> {
  const dirty = await repo.statusPorcelain();
  const offenders = nonDocDirty(dirty, config);
  if (offenders.length > 0) {
    throw new DetDocError(
      `detdoc fix requires no dirty non-documentation changes. Found dirty non-documentation changes: ${offenders.map((file) => file.path).join(", ")}`,
      "DIRTY_NON_DOC_CHANGES",
    );
  }
  return dirty;
}
```

- [ ] **Step 6: Run tests and typecheck**

Run:

```bash
npm test -- tests/git-policy.test.ts
npm run typecheck
```

Expected: both pass.

- [ ] **Step 7: Commit**

```bash
git add src tests
git commit -m "feat: add git dirty-state policy"
```

---

### Task 4: Normalized Documentation Diff and `detdoc diff`

**Files:**
- Create: `src/core/diff.ts`
- Create: `src/cli/commands/diff.ts`
- Modify: `src/cli/main.ts`
- Test: `tests/diff.test.ts`

**Interfaces:**
- Consumes: `GitRepository`, `DetDocConfig`, dirty policy.
- Produces:
  - `getNormalizedDocDiff(repo: GitRepository, config: DetDocConfig): Promise<string>`
  - `registerDiffCommand(program: Command, io: CliIO): void`

- [ ] **Step 1: Write failing diff tests**

Create `tests/diff.test.ts`:

```ts
import { writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createTestIO } from "./helpers/test-io.js";
import { cleanupFixtures, createGitFixture } from "./helpers/git-fixture.js";
import { runCli } from "../src/cli/main.js";
import { initConfig } from "../src/core/config.js";
import { getNormalizedDocDiff } from "../src/core/diff.js";
import { GitRepository } from "../src/core/git.js";
import { defaultConfig } from "../src/core/config.js";

afterEach(cleanupFixtures);

describe("normalized doc diff", () => {
  it("returns stable git diff for dirty docs", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const x = 1;\n" });
    await writeFile(join(fixture.cwd, "docs/spec.md"), "new\n", "utf8");

    const diff = await getNormalizedDocDiff(new GitRepository(fixture.cwd), defaultConfig());

    expect(diff).toContain("diff --git a/docs/spec.md b/docs/spec.md");
    expect(diff).toContain("-old");
    expect(diff).toContain("+new");
    expect(diff.endsWith("\n")).toBe(true);
  });

  it("prints diff through CLI", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n" });
    await initConfig(fixture.cwd);
    await writeFile(join(fixture.cwd, "docs/spec.md"), "new\n", "utf8");

    const oldCwd = process.cwd();
    process.chdir(fixture.cwd);
    try {
      const io = createTestIO();
      const code = await runCli(["node", "detdoc", "diff"], io);
      expect(code).toBe(0);
      expect(io.stdoutText()).toContain("diff --git a/docs/spec.md b/docs/spec.md");
    } finally {
      process.chdir(oldCwd);
    }
  });
});
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
npm test -- tests/diff.test.ts
```

Expected: FAIL because `src/core/diff.ts` and command registration do not exist.

- [ ] **Step 3: Implement normalized diff**

Create `src/core/diff.ts`:

```ts
import type { DetDocConfig } from "./config.js";
import { DetDocError } from "./errors.js";
import type { GitRepository } from "./git.js";
import { assertRunDirtyPolicy } from "./paths.js";

export async function getNormalizedDocDiff(repo: GitRepository, config: DetDocConfig): Promise<string> {
  await assertRunDirtyPolicy(repo, config);
  const diff = await repo.diff();
  if (diff.trim().length === 0) {
    throw new DetDocError("No documentation changes found.", "NO_DOC_DIFF");
  }
  return diff.endsWith("\n") ? diff : `${diff}\n`;
}
```

- [ ] **Step 4: Implement and register diff command**

Create `src/cli/commands/diff.ts`:

```ts
import type { Command } from "commander";
import type { CliIO } from "../output.js";
import { loadConfig } from "../../core/config.js";
import { getNormalizedDocDiff } from "../../core/diff.js";
import { GitRepository } from "../../core/git.js";

export function registerDiffCommand(program: Command, io: CliIO): void {
  program
    .command("diff")
    .description("Print normalized documentation diff")
    .action(async () => {
      const cwd = process.cwd();
      const config = await loadConfig(cwd);
      const diff = await getNormalizedDocDiff(new GitRepository(cwd), config);
      io.stdout.write(diff);
    });
}
```

Modify `src/cli/main.ts` to import and call `registerDiffCommand` instead of the stub for `diff`:

```ts
import { registerDiffCommand } from "./commands/diff.js";
```

Inside `runCli` command setup, replace `addCommand(program, "diff", ...)` with:

```ts
registerDiffCommand(program, io);
```

- [ ] **Step 5: Run tests and typecheck**

Run:

```bash
npm test -- tests/diff.test.ts tests/git-policy.test.ts tests/config-init.test.ts
npm run typecheck
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add src tests
git commit -m "feat: add normalized documentation diff command"
```

---

### Task 5: Worktree Lifecycle and Applying Documentation Diff

**Files:**
- Create: `src/core/worktree.ts`
- Test: `tests/worktree.test.ts`

**Interfaces:**
- Consumes: `GitRepository`, normalized doc diff.
- Produces:
  - `WorktreeManager`
  - `createFromHead(baseRepo: GitRepository, options?: { prefix?: string }): Promise<TemporaryWorktree>`
  - `TemporaryWorktree` with `path`, `repo`, `cleanup()`

- [ ] **Step 1: Write failing worktree test**

Create `tests/worktree.test.ts`:

```ts
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { defaultConfig } from "../src/core/config.js";
import { getNormalizedDocDiff } from "../src/core/diff.js";
import { GitRepository } from "../src/core/git.js";
import { WorktreeManager } from "../src/core/worktree.js";
import { cleanupFixtures, createGitFixture } from "./helpers/git-fixture.js";

afterEach(cleanupFixtures);

describe("WorktreeManager", () => {
  it("creates worktree from HEAD and applies only doc diff", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const x = 1;\n" });
    await writeFile(join(fixture.cwd, "docs/spec.md"), "new\n", "utf8");
    const baseRepo = new GitRepository(fixture.cwd);
    const diff = await getNormalizedDocDiff(baseRepo, defaultConfig());

    const manager = new WorktreeManager();
    const worktree = await manager.createFromHead(baseRepo, { prefix: "detdoc-test-" });
    try {
      await worktree.repo.applyPatch(diff);
      expect(await readFile(join(worktree.path, "docs/spec.md"), "utf8")).toBe("new\n");
      expect(await readFile(join(worktree.path, "src/app.ts"), "utf8")).toBe("export const x = 1;\n");
    } finally {
      await worktree.cleanup();
    }
  });
});
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
npm test -- tests/worktree.test.ts
```

Expected: FAIL because `src/core/worktree.ts` does not exist.

- [ ] **Step 3: Implement worktree manager**

Create `src/core/worktree.ts`:

```ts
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { GitRepository } from "./git.js";

export interface TemporaryWorktree {
  path: string;
  repo: GitRepository;
  cleanup(): Promise<void>;
}

export class WorktreeManager {
  async createFromHead(baseRepo: GitRepository, options: { prefix?: string } = {}): Promise<TemporaryWorktree> {
    const prefix = options.prefix ?? "detdoc-worktree-";
    const path = await mkdtemp(join(tmpdir(), prefix));
    const head = await baseRepo.headCommit();
    await baseRepo.git(["worktree", "add", "--detach", path, head]);

    const repo = new GitRepository(path);
    return {
      path,
      repo,
      cleanup: async () => {
        await baseRepo.git(["worktree", "remove", "--force", path]).catch(async () => {
          await rm(path, { recursive: true, force: true });
        });
      },
    };
  }
}
```

- [ ] **Step 4: Run tests and typecheck**

Run:

```bash
npm test -- tests/worktree.test.ts tests/diff.test.ts
npm run typecheck
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add src tests
git commit -m "feat: create isolated git worktrees"
```

---

### Task 6: Manifest, Hashing, and Artifact Store

**Files:**
- Create: `src/core/hash.ts`
- Create: `src/core/manifest.ts`
- Create: `src/core/artifacts.ts`
- Test: `tests/artifacts.test.ts`

**Interfaces:**
- Consumes: config, git metadata, input diff or intent.
- Produces:
  - `sha256Text(text: string): string`
  - `createRunId(mode: RunMode, inputHash: string, date?: Date): string`
  - `createInitialManifest(input): RunManifest`
  - `ArtifactStore` with `createRun`, `writeText`, `writeJson`, `readRun`

- [ ] **Step 1: Write failing artifact tests**

Create `tests/artifacts.test.ts`:

```ts
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { defaultConfig } from "../src/core/config.js";
import { ArtifactStore } from "../src/core/artifacts.js";
import { createInitialManifest, createRunId } from "../src/core/manifest.js";
import { sha256Text } from "../src/core/hash.js";
import { GitRepository } from "../src/core/git.js";
import { cleanupFixtures, createGitFixture } from "./helpers/git-fixture.js";

afterEach(cleanupFixtures);

describe("artifacts", () => {
  it("creates stable run id", () => {
    expect(createRunId("run", "abcdef1234567890", new Date("2026-06-19T20:00:00Z"))).toBe("20260619T200000Z-run-abcdef12");
  });

  it("writes manifest and input artifacts", async () => {
    const fixture = await createGitFixture({ "README.md": "hello\n" });
    const repo = new GitRepository(fixture.cwd);
    const config = defaultConfig();
    const input = "diff text\n";
    const manifest = await createInitialManifest({
      mode: "run",
      repo,
      config,
      input,
      createdAt: new Date("2026-06-19T20:00:00Z"),
    });

    const store = new ArtifactStore(fixture.cwd);
    const dir = await store.createRun(manifest);
    await store.writeText(manifest.runId, "input.diff.md", input);

    const manifestText = await readFile(join(dir, "manifest.json"), "utf8");
    expect(JSON.parse(manifestText).inputHash).toBe(sha256Text(input));
    expect(await readFile(join(dir, "input.diff.md"), "utf8")).toBe(input);
  });
});
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
npm test -- tests/artifacts.test.ts
```

Expected: FAIL because hash, manifest, and artifact store modules do not exist.

- [ ] **Step 3: Implement hashing**

Create `src/core/hash.ts`:

```ts
import { createHash } from "node:crypto";

export function sha256Text(text: string): string {
  return createHash("sha256").update(text, "utf8").digest("hex");
}
```

- [ ] **Step 4: Implement manifest creation**

Create `src/core/manifest.ts`:

```ts
import YAML from "yaml";
import type { DetDocConfig } from "./config.js";
import type { GitRepository } from "./git.js";
import { sha256Text } from "./hash.js";

export type RunMode = "run" | "fix";

export interface TouchedFileHash {
  path: string;
  before: string | null;
  after: string | null;
}

export interface RunManifest {
  runId: string;
  mode: RunMode;
  baseCommit: string;
  baseTreeHash: string;
  inputHash: string;
  configHash: string;
  createdAt: string;
  docGlobs: string[];
  ignoredPaths: string[];
  validationCommands: Array<{ name: string; run: string }>;
  agent: "pi-sdk";
  model: string | null;
  thinking: string;
  approvedTargets: string[];
  touchedFiles: TouchedFileHash[];
}

export function createRunId(mode: RunMode, inputHash: string, date = new Date()): string {
  const stamp = date.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
  return `${stamp}-${mode}-${inputHash.slice(0, 8)}`;
}

export async function createInitialManifest(input: {
  mode: RunMode;
  repo: GitRepository;
  config: DetDocConfig;
  input: string;
  createdAt?: Date;
}): Promise<RunManifest> {
  const createdAt = input.createdAt ?? new Date();
  const inputHash = sha256Text(input.input);
  const configSnapshot = YAML.stringify(input.config);
  return {
    runId: createRunId(input.mode, inputHash, createdAt),
    mode: input.mode,
    baseCommit: await input.repo.headCommit(),
    baseTreeHash: (await input.repo.git(["rev-parse", "HEAD^{tree}"])).trim(),
    inputHash,
    configHash: sha256Text(configSnapshot),
    createdAt: createdAt.toISOString(),
    docGlobs: input.config.docs.include,
    ignoredPaths: input.config.docs.exclude,
    validationCommands: input.config.validation.commands,
    agent: "pi-sdk",
    model: input.config.agent.model,
    thinking: input.config.agent.thinking,
    approvedTargets: [],
    touchedFiles: [],
  };
}
```

- [ ] **Step 5: Implement artifact store**

Create `src/core/artifacts.ts`:

```ts
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import type { RunManifest } from "./manifest.js";

export class ArtifactStore {
  constructor(readonly cwd: string) {}

  runDir(runId: string): string {
    return join(this.cwd, ".detdoc", "runs", runId);
  }

  async createRun(manifest: RunManifest): Promise<string> {
    const dir = this.runDir(manifest.runId);
    await mkdir(dir, { recursive: true });
    await this.writeJson(manifest.runId, "manifest.json", manifest);
    return dir;
  }

  async writeText(runId: string, name: string, content: string): Promise<void> {
    await writeFile(join(this.runDir(runId), name), content, "utf8");
  }

  async writeJson(runId: string, name: string, value: unknown): Promise<void> {
    await this.writeText(runId, name, `${JSON.stringify(value, null, 2)}\n`);
  }

  async readText(runId: string, name: string): Promise<string> {
    return readFile(join(this.runDir(runId), name), "utf8");
  }

  async readJson<T>(runId: string, name: string): Promise<T> {
    return JSON.parse(await this.readText(runId, name)) as T;
  }
}
```

- [ ] **Step 6: Run tests and typecheck**

Run:

```bash
npm test -- tests/artifacts.test.ts
npm run typecheck
```

Expected: both pass.

- [ ] **Step 7: Commit**

```bash
git add src tests
git commit -m "feat: add run manifests and artifact storage"
```

---

### Task 7: Structured Plan Schema, Plan Validation, and Fake Agent Runner

**Files:**
- Create: `src/core/plan.ts`
- Create: `src/core/agent/agent-runner.ts`
- Create: `src/core/agent/fake-agent-runner.ts`
- Test: `tests/plan.test.ts`

**Interfaces:**
- Consumes: `DetDocConfig`, `RunManifest`.
- Produces:
  - `PlanSchema`, `type ProposedPlan`
  - `validateProposedPlan(plan, { config, mode }): ProposedPlan`
  - `approvedTargetsFromPlan(plan): string[]`
  - `AgentRunner` interface
  - `FakeAgentRunner`

- [ ] **Step 1: Write failing plan tests**

Create `tests/plan.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { defaultConfig } from "../src/core/config.js";
import { FakeAgentRunner } from "../src/core/agent/fake-agent-runner.js";
import { approvedTargetsFromPlan, validateProposedPlan } from "../src/core/plan.js";

describe("plan validation", () => {
  it("accepts a plan with diff-linked target files", () => {
    const plan = validateProposedPlan(
      {
        summary: "Update API behavior",
        changes: [
          {
            reason: "doc-diff:docs/api.md:L1-L4",
            targetFiles: ["src/api.ts"],
            kind: "modify",
            rationale: "The API implementation must follow the changed behavior.",
          },
        ],
        questions: [],
        risk: "low",
      },
      { config: defaultConfig(), mode: "run" },
    );

    expect(approvedTargetsFromPlan(plan)).toEqual(["src/api.ts"]);
  });

  it("rejects denied target paths", () => {
    expect(() =>
      validateProposedPlan(
        {
          summary: "Bad plan",
          changes: [
            {
              reason: "intent:fix",
              targetFiles: [".env"],
              kind: "modify",
              rationale: "This should never be allowed.",
            },
          ],
          questions: [],
          risk: "low",
        },
        { config: defaultConfig(), mode: "fix" },
      ),
    ).toThrow("denied path");
  });

  it("rejects doc targets for fix mode", () => {
    expect(() =>
      validateProposedPlan(
        {
          summary: "Bad fix plan",
          changes: [
            {
              reason: "intent:fix",
              targetFiles: ["docs/spec.md"],
              kind: "modify",
              rationale: "Fix mode must not change docs in the MVP.",
            },
          ],
          questions: [],
          risk: "low",
        },
        { config: defaultConfig(), mode: "fix" },
      ),
    ).toThrow("fix plans must not target documentation files");
  });
});

describe("FakeAgentRunner", () => {
  it("returns configured plan", async () => {
    const runner = new FakeAgentRunner({
      plan: {
        summary: "Fake plan",
        changes: [
          {
            reason: "intent:fix",
            targetFiles: ["src/app.ts"],
            kind: "modify",
            rationale: "The fake runner is deterministic.",
          },
        ],
        questions: [],
        risk: "low",
      },
    });

    const plan = await runner.plan({ mode: "fix", input: "fix bug", config: defaultConfig(), cwd: "/tmp/project" });
    expect(plan.summary).toBe("Fake plan");
  });
});
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
npm test -- tests/plan.test.ts
```

Expected: FAIL because plan and agent modules do not exist.

- [ ] **Step 3: Implement plan schema and validation**

Create `src/core/plan.ts`:

```ts
import { z } from "zod";
import type { DetDocConfig } from "./config.js";
import type { RunMode } from "./manifest.js";
import { isDeniedPath, isDocPath } from "./paths.js";

export const PlanChangeSchema = z.object({
  reason: z.string().min(1),
  targetFiles: z.array(z.string().min(1)).min(1),
  kind: z.enum(["create", "modify", "delete", "rename"]),
  rationale: z.string().min(1),
});

export const PlanSchema = z.object({
  summary: z.string().min(1),
  changes: z.array(PlanChangeSchema).min(1),
  questions: z.array(z.string()).default([]),
  risk: z.enum(["low", "medium", "high"]),
});

export type ProposedPlan = z.infer<typeof PlanSchema>;

export function validateProposedPlan(
  value: unknown,
  options: { config: DetDocConfig; mode: RunMode },
): ProposedPlan {
  const plan = PlanSchema.parse(value);

  for (const change of plan.changes) {
    if (options.mode === "run" && !change.reason.startsWith("doc-diff:")) {
      throw new Error(`run plan change must use doc-diff reason: ${change.reason}`);
    }
    if (options.mode === "fix" && !change.reason.startsWith("intent:")) {
      throw new Error(`fix plan change must use intent reason: ${change.reason}`);
    }
    for (const target of change.targetFiles) {
      if (isDeniedPath(target, options.config)) {
        throw new Error(`plan targets denied path: ${target}`);
      }
      if (options.mode === "fix" && isDocPath(target, options.config)) {
        throw new Error(`fix plans must not target documentation files: ${target}`);
      }
    }
  }

  return plan;
}

export function approvedTargetsFromPlan(plan: ProposedPlan): string[] {
  return [...new Set(plan.changes.flatMap((change) => change.targetFiles))].sort();
}
```

- [ ] **Step 4: Implement AgentRunner interface and fake runner**

Create `src/core/agent/agent-runner.ts`:

```ts
import type { DetDocConfig } from "../config.js";
import type { RunMode } from "../manifest.js";
import type { ProposedPlan } from "../plan.js";

export interface PlanRequest {
  mode: RunMode;
  input: string;
  config: DetDocConfig;
  cwd: string;
}

export interface ImplementRequest {
  mode: RunMode;
  input: string;
  config: DetDocConfig;
  cwd: string;
  approvedPlan: ProposedPlan;
  approvedTargets: string[];
}

export interface AgentRunner {
  plan(request: PlanRequest): Promise<ProposedPlan>;
  implement(request: ImplementRequest): Promise<void>;
}
```

Create `src/core/agent/fake-agent-runner.ts`:

```ts
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import type { AgentRunner, ImplementRequest, PlanRequest } from "./agent-runner.js";
import type { ProposedPlan } from "../plan.js";

export class FakeAgentRunner implements AgentRunner {
  constructor(
    private readonly options: {
      plan: ProposedPlan;
      writes?: Record<string, string>;
    },
  ) {}

  async plan(_request: PlanRequest): Promise<ProposedPlan> {
    return this.options.plan;
  }

  async implement(request: ImplementRequest): Promise<void> {
    for (const [relativePath, content] of Object.entries(this.options.writes ?? {})) {
      if (!request.approvedTargets.includes(relativePath)) {
        throw new Error(`FakeAgentRunner attempted unapproved write: ${relativePath}`);
      }
      const absolute = join(request.cwd, relativePath);
      await mkdir(dirname(absolute), { recursive: true });
      await writeFile(absolute, content, "utf8");
    }
  }
}
```

- [ ] **Step 5: Run tests and typecheck**

Run:

```bash
npm test -- tests/plan.test.ts
npm run typecheck
```

Expected: both pass.

- [ ] **Step 6: Commit**

```bash
git add src tests
git commit -m "feat: add structured plan validation"
```

---

### Task 8: Approval UI, Patch Validation, and Validation Commands

**Files:**
- Create: `src/core/approval.ts`
- Create: `src/core/validation.ts`
- Test: `tests/validation.test.ts`

**Interfaces:**
- Consumes: `ProposedPlan`, `RunManifest`, `DetDocConfig`, `GitRepository`.
- Produces:
  - `ApprovalUI` interface
  - `TerminalApprovalUI`
  - `AutoApprovalUI`
  - `collectPatch(worktreeRepo): Promise<string>`
  - `validatePatch({ patch, repo, config, mode, approvedTargets }): Promise<PatchValidationResult>`
  - `runValidationCommands({ cwd, config }): Promise<string>`

- [ ] **Step 1: Write failing validation tests**

Create `tests/validation.test.ts`:

```ts
import { writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { defaultConfig } from "../src/core/config.js";
import { GitRepository } from "../src/core/git.js";
import { collectPatch, runValidationCommands, validatePatch } from "../src/core/validation.js";
import { cleanupFixtures, createGitFixture } from "./helpers/git-fixture.js";

afterEach(cleanupFixtures);

describe("patch validation", () => {
  it("accepts patch touching approved target", async () => {
    const fixture = await createGitFixture({ "src/app.ts": "export const x = 1;\n" });
    await writeFile(join(fixture.cwd, "src/app.ts"), "export const x = 2;\n", "utf8");
    const repo = new GitRepository(fixture.cwd);
    const patch = await collectPatch(repo);

    const result = await validatePatch({
      patch,
      repo,
      config: defaultConfig(),
      mode: "run",
      approvedTargets: ["src/app.ts"],
    });

    expect(result.changedFiles).toEqual(["src/app.ts"]);
  });

  it("rejects unapproved target", async () => {
    const fixture = await createGitFixture({ "src/app.ts": "export const x = 1;\n" });
    await writeFile(join(fixture.cwd, "src/app.ts"), "export const x = 2;\n", "utf8");
    const repo = new GitRepository(fixture.cwd);
    const patch = await collectPatch(repo);

    await expect(
      validatePatch({ patch, repo, config: defaultConfig(), mode: "run", approvedTargets: ["src/other.ts"] }),
    ).rejects.toThrow("unapproved path");
  });

  it("rejects doc changes in fix mode", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n" });
    await writeFile(join(fixture.cwd, "docs/spec.md"), "new\n", "utf8");
    const repo = new GitRepository(fixture.cwd);
    const patch = await collectPatch(repo);

    await expect(
      validatePatch({ patch, repo, config: defaultConfig(), mode: "fix", approvedTargets: ["docs/spec.md"] }),
    ).rejects.toThrow("fix patches must not modify documentation files");
  });
});

describe("validation commands", () => {
  it("captures configured command output", async () => {
    const fixture = await createGitFixture({ "package.json": "{\"scripts\":{\"check\":\"node -e \\\"console.log('ok')\\\"\"}}\n" });
    const config = defaultConfig();
    config.validation.commands = [{ name: "check", run: "npm run check" }];

    const log = await runValidationCommands({ cwd: fixture.cwd, config });
    expect(log).toContain("$ npm run check");
    expect(log).toContain("ok");
  });
});
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
npm test -- tests/validation.test.ts
```

Expected: FAIL because approval and validation modules do not exist.

- [ ] **Step 3: Implement approval abstractions**

Create `src/core/approval.ts`:

```ts
import { createInterface } from "node:readline/promises";
import type { CliIO } from "../cli/output.js";
import { writeLine } from "../cli/output.js";
import type { ProposedPlan } from "./plan.js";

export interface ApprovalUI {
  approvePlan(plan: ProposedPlan): Promise<boolean>;
  approvePatch(patch: string): Promise<boolean>;
}

export class AutoApprovalUI implements ApprovalUI {
  constructor(private readonly approved = true) {}

  async approvePlan(_plan: ProposedPlan): Promise<boolean> {
    return this.approved;
  }

  async approvePatch(_patch: string): Promise<boolean> {
    return this.approved;
  }
}

export class TerminalApprovalUI implements ApprovalUI {
  constructor(private readonly io: CliIO) {}

  async approvePlan(plan: ProposedPlan): Promise<boolean> {
    writeLine(this.io.stdout, JSON.stringify(plan, null, 2));
    return this.confirm("Approve this plan? Type 'approve' to continue: ");
  }

  async approvePatch(patch: string): Promise<boolean> {
    writeLine(this.io.stdout, patch);
    return this.confirm("Apply this patch? Type 'approve' to continue: ");
  }

  private async confirm(prompt: string): Promise<boolean> {
    if (!this.io.isInteractive) return false;
    const rl = createInterface({ input: this.io.stdin, output: this.io.stdout });
    try {
      const answer = await rl.question(prompt);
      return answer.trim() === "approve";
    } finally {
      rl.close();
    }
  }
}
```

- [ ] **Step 4: Implement patch validation and command runner**

Create `src/core/validation.ts`:

```ts
import { exec } from "node:child_process";
import { promisify } from "node:util";
import type { DetDocConfig } from "./config.js";
import { DetDocError } from "./errors.js";
import type { GitRepository } from "./git.js";
import type { RunMode } from "./manifest.js";
import { isDeniedPath, isDocPath } from "./paths.js";

const execAsync = promisify(exec);

export interface PatchValidationResult {
  changedFiles: string[];
}

export async function collectPatch(repo: GitRepository): Promise<string> {
  const patch = await repo.diff();
  if (patch.trim().length === 0) {
    throw new DetDocError("Agent produced no code changes.", "EMPTY_PATCH");
  }
  return patch.endsWith("\n") ? patch : `${patch}\n`;
}

export async function validatePatch(input: {
  patch: string;
  repo: GitRepository;
  config: DetDocConfig;
  mode: RunMode;
  approvedTargets: string[];
}): Promise<PatchValidationResult> {
  const changedFiles = (await input.repo.changedFilesFromPatch(input.patch)).sort();
  const approved = new Set(input.approvedTargets);

  for (const file of changedFiles) {
    if (isDeniedPath(file, input.config)) {
      throw new DetDocError(`Patch touches denied path: ${file}`, "PATCH_DENIED_PATH");
    }
    if (!approved.has(file)) {
      throw new DetDocError(`Patch touches unapproved path: ${file}`, "PATCH_UNAPPROVED_PATH");
    }
    if (input.mode === "fix" && isDocPath(file, input.config)) {
      throw new DetDocError(`fix patches must not modify documentation files: ${file}`, "FIX_PATCH_DOC_CHANGE");
    }
    if (file.startsWith(".detdoc/runs/")) {
      throw new DetDocError(`Patch must not include run artifacts: ${file}`, "PATCH_ARTIFACT_CHANGE");
    }
  }

  return { changedFiles };
}

export async function runValidationCommands(input: { cwd: string; config: DetDocConfig }): Promise<string> {
  let log = "";
  for (const command of input.config.validation.commands) {
    log += `\n# ${command.name}\n$ ${command.run}\n`;
    try {
      const { stdout, stderr } = await execAsync(command.run, {
        cwd: input.cwd,
        maxBuffer: 20 * 1024 * 1024,
      });
      log += stdout;
      log += stderr;
    } catch (error) {
      const anyError = error as { stdout?: string; stderr?: string; message?: string };
      log += anyError.stdout ?? "";
      log += anyError.stderr ?? "";
      throw new DetDocError(`Validation command failed: ${command.name}\n${log}`, "VALIDATION_FAILED");
    }
  }
  return log.trimStart();
}
```

- [ ] **Step 5: Run tests and typecheck**

Run:

```bash
npm test -- tests/validation.test.ts
npm run typecheck
```

Expected: both pass.

- [ ] **Step 6: Commit**

```bash
git add src tests
git commit -m "feat: validate generated patches"
```

---

### Task 9: High-Level Flow for `plan`, `run`, and `fix` with Fake Agent

**Files:**
- Create: `src/core/flow.ts`
- Create: `src/cli/commands/plan.ts`
- Create: `src/cli/commands/run.ts`
- Create: `src/cli/commands/fix.ts`
- Modify: `src/cli/main.ts`
- Test: `tests/flow-run.test.ts`

**Interfaces:**
- Consumes: all previous core modules.
- Produces:
  - `createPlanFlow(input): Promise<FlowResult>`
  - `runDocFlow(input): Promise<FlowResult>`
  - `runFixFlow(input): Promise<FlowResult>`
  - CLI commands for `plan`, `run`, `fix`

- [ ] **Step 1: Write failing flow tests with fake agent**

Create `tests/flow-run.test.ts`:

```ts
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { AutoApprovalUI } from "../src/core/approval.js";
import { initConfig } from "../src/core/config.js";
import { FakeAgentRunner } from "../src/core/agent/fake-agent-runner.js";
import { runDocFlow, runFixFlow } from "../src/core/flow.js";
import { cleanupFixtures, createGitFixture } from "./helpers/git-fixture.js";

afterEach(cleanupFixtures);

describe("DetDoc flows", () => {
  it("runs doc-diff flow and applies approved patch", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const value = 1;\n" });
    await initConfig(fixture.cwd);
    await writeFile(join(fixture.cwd, "docs/spec.md"), "new behavior\n", "utf8");

    const agent = new FakeAgentRunner({
      plan: {
        summary: "Update app value",
        changes: [
          {
            reason: "doc-diff:docs/spec.md:L1-L1",
            targetFiles: ["src/app.ts"],
            kind: "modify",
            rationale: "The changed documentation requires value 2.",
          },
        ],
        questions: [],
        risk: "low",
      },
      writes: { "src/app.ts": "export const value = 2;\n" },
    });

    const result = await runDocFlow({ cwd: fixture.cwd, agent, approval: new AutoApprovalUI(true) });

    expect(result.applied).toBe(true);
    expect(await readFile(join(fixture.cwd, "src/app.ts"), "utf8")).toBe("export const value = 2;\n");
    expect(result.runId).toMatch(/-run-/);
  });

  it("runs fix flow while ignoring dirty docs", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const value = 1;\n" });
    await initConfig(fixture.cwd);
    await writeFile(join(fixture.cwd, "docs/spec.md"), "dirty but ignored\n", "utf8");

    const agent = new FakeAgentRunner({
      plan: {
        summary: "Fix value",
        changes: [
          {
            reason: "intent:fix",
            targetFiles: ["src/app.ts"],
            kind: "modify",
            rationale: "The bugfix intent says the value is wrong.",
          },
        ],
        questions: [],
        risk: "low",
      },
      writes: { "src/app.ts": "export const value = 3;\n" },
    });

    const result = await runFixFlow({ cwd: fixture.cwd, message: "fix wrong value", agent, approval: new AutoApprovalUI(true) });

    expect(result.applied).toBe(true);
    expect(await readFile(join(fixture.cwd, "src/app.ts"), "utf8")).toBe("export const value = 3;\n");
    expect(await readFile(join(fixture.cwd, "docs/spec.md"), "utf8")).toBe("dirty but ignored\n");
  });
});
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
npm test -- tests/flow-run.test.ts
```

Expected: FAIL because `src/core/flow.ts` and CLI commands do not exist.

- [ ] **Step 3: Implement orchestration flow**

Create `src/core/flow.ts`:

```ts
import YAML from "yaml";
import type { AgentRunner } from "./agent/agent-runner.js";
import type { ApprovalUI } from "./approval.js";
import { ArtifactStore } from "./artifacts.js";
import { loadConfig } from "./config.js";
import { getNormalizedDocDiff } from "./diff.js";
import { DetDocError } from "./errors.js";
import { GitRepository } from "./git.js";
import { createInitialManifest, type RunManifest } from "./manifest.js";
import { assertFixDirtyPolicy } from "./paths.js";
import { approvedTargetsFromPlan, validateProposedPlan } from "./plan.js";
import { collectPatch, runValidationCommands, validatePatch } from "./validation.js";
import { WorktreeManager } from "./worktree.js";

export interface FlowResult {
  runId: string;
  applied: boolean;
  patch: string;
}

async function updateManifest(store: ArtifactStore, manifest: RunManifest): Promise<void> {
  await store.writeJson(manifest.runId, "manifest.json", manifest);
}

async function applyPatchToMain(repo: GitRepository, patch: string): Promise<void> {
  await repo.applyPatch(patch);
}

export async function createPlanFlow(input: { cwd: string; agent: AgentRunner; mode?: "run" | "fix"; message?: string }): Promise<{ runId: string }> {
  const cwd = input.cwd;
  const config = await loadConfig(cwd);
  const repo = new GitRepository(cwd);
  const mode = input.mode ?? "run";
  const taskInput = mode === "run" ? await getNormalizedDocDiff(repo, config) : input.message ?? "";
  if (mode === "fix") await assertFixDirtyPolicy(repo, config);
  if (mode === "fix" && taskInput.trim().length === 0) throw new DetDocError("detdoc fix requires a non-empty message.", "EMPTY_FIX_MESSAGE");

  const manifest = await createInitialManifest({ mode, repo, config, input: taskInput });
  const store = new ArtifactStore(cwd);
  await store.createRun(manifest);
  await store.writeText(manifest.runId, mode === "run" ? "input.diff.md" : "intent.md", taskInput);
  await store.writeText(manifest.runId, "config.snapshot.yml", YAML.stringify(config));

  const plan = validateProposedPlan(await input.agent.plan({ mode, input: taskInput, config, cwd }), { config, mode });
  await store.writeJson(manifest.runId, "plan.proposed.json", plan);
  return { runId: manifest.runId };
}

async function runFlow(input: { cwd: string; mode: "run" | "fix"; message?: string; agent: AgentRunner; approval: ApprovalUI }): Promise<FlowResult> {
  const cwd = input.cwd;
  const config = await loadConfig(cwd);
  const mainRepo = new GitRepository(cwd);
  const taskInput = input.mode === "run" ? await getNormalizedDocDiff(mainRepo, config) : input.message ?? "";
  if (input.mode === "fix") await assertFixDirtyPolicy(mainRepo, config);
  if (input.mode === "fix" && taskInput.trim().length === 0) throw new DetDocError("detdoc fix requires a non-empty message.", "EMPTY_FIX_MESSAGE");

  const manifest = await createInitialManifest({ mode: input.mode, repo: mainRepo, config, input: taskInput });
  const store = new ArtifactStore(cwd);
  await store.createRun(manifest);
  await store.writeText(manifest.runId, input.mode === "run" ? "input.diff.md" : "intent.md", taskInput);
  await store.writeText(manifest.runId, "config.snapshot.yml", YAML.stringify(config));

  const worktree = await new WorktreeManager().createFromHead(mainRepo);
  let keepWorktree = config.worktree.keepOnFailure;
  try {
    if (input.mode === "run") await worktree.repo.applyPatch(taskInput);

    const proposedPlan = validateProposedPlan(
      await input.agent.plan({ mode: input.mode, input: taskInput, config, cwd: worktree.path }),
      { config, mode: input.mode },
    );
    await store.writeJson(manifest.runId, "plan.proposed.json", proposedPlan);

    if (!(await input.approval.approvePlan(proposedPlan))) {
      throw new DetDocError("Plan was not approved.", "PLAN_NOT_APPROVED");
    }

    await store.writeJson(manifest.runId, "plan.approved.json", proposedPlan);
    const approvedTargets = approvedTargetsFromPlan(proposedPlan);
    manifest.approvedTargets = approvedTargets;
    await updateManifest(store, manifest);

    await input.agent.implement({
      mode: input.mode,
      input: taskInput,
      config,
      cwd: worktree.path,
      approvedPlan: proposedPlan,
      approvedTargets,
    });

    const patch = await collectPatch(worktree.repo);
    const validation = await validatePatch({ patch, repo: worktree.repo, config, mode: input.mode, approvedTargets });
    const validationLog = await runValidationCommands({ cwd: worktree.path, config });

    manifest.touchedFiles = await Promise.all(
      validation.changedFiles.map(async (path) => ({
        path,
        before: await mainRepo.fileSha256(path),
        after: await worktree.repo.fileSha256(path),
      })),
    );
    await store.writeText(manifest.runId, "changes.patch", patch);
    await store.writeText(manifest.runId, "validation.log", validationLog);
    await updateManifest(store, manifest);

    if (!(await input.approval.approvePatch(patch))) {
      return { runId: manifest.runId, applied: false, patch };
    }

    await applyPatchToMain(mainRepo, patch);
    keepWorktree = false;
    return { runId: manifest.runId, applied: true, patch };
  } finally {
    if (!keepWorktree) await worktree.cleanup();
  }
}

export async function runDocFlow(input: { cwd: string; agent: AgentRunner; approval: ApprovalUI }): Promise<FlowResult> {
  return runFlow({ ...input, mode: "run" });
}

export async function runFixFlow(input: { cwd: string; message: string; agent: AgentRunner; approval: ApprovalUI }): Promise<FlowResult> {
  return runFlow({ ...input, mode: "fix" });
}
```

- [ ] **Step 4: Add CLI commands wired to fake-agent fallback for tests**

Create `src/cli/commands/plan.ts`:

```ts
import type { Command } from "commander";
import type { CliIO } from "../output.js";
import { writeLine } from "../output.js";
import { FakeAgentRunner } from "../../core/agent/fake-agent-runner.js";
import { createPlanFlow } from "../../core/flow.js";

function testAgent(): FakeAgentRunner {
  return new FakeAgentRunner({
    plan: {
      summary: "Test plan",
      changes: [{ reason: "doc-diff:docs/spec.md:L1-L1", targetFiles: ["src/app.ts"], kind: "modify", rationale: "Test agent plan." }],
      questions: [],
      risk: "low",
    },
  });
}

export function registerPlanCommand(program: Command, io: CliIO): void {
  program
    .command("plan")
    .description("Create an implementation plan without applying code changes")
    .action(async () => {
      const result = await createPlanFlow({ cwd: process.cwd(), agent: testAgent() });
      writeLine(io.stdout, `Plan saved for run ${result.runId}`);
    });
}
```

Create `src/cli/commands/run.ts`:

```ts
import type { Command } from "commander";
import type { CliIO } from "../output.js";
import { writeLine } from "../output.js";
import { FakeAgentRunner } from "../../core/agent/fake-agent-runner.js";
import { TerminalApprovalUI } from "../../core/approval.js";
import { runDocFlow } from "../../core/flow.js";

export function registerRunCommand(program: Command, io: CliIO): void {
  program
    .command("run")
    .description("Run the documentation-diff workflow")
    .action(async () => {
      const agent = new FakeAgentRunner({
        plan: {
          summary: "Test plan",
          changes: [{ reason: "doc-diff:docs/spec.md:L1-L1", targetFiles: ["src/app.ts"], kind: "modify", rationale: "Test agent plan." }],
          questions: [],
          risk: "low",
        },
        writes: {},
      });
      const result = await runDocFlow({ cwd: process.cwd(), agent, approval: new TerminalApprovalUI(io) });
      writeLine(io.stdout, `Run ${result.runId} ${result.applied ? "applied" : "saved"}`);
    });
}
```

Create `src/cli/commands/fix.ts`:

```ts
import type { Command } from "commander";
import type { CliIO } from "../output.js";
import { writeLine } from "../output.js";
import { FakeAgentRunner } from "../../core/agent/fake-agent-runner.js";
import { TerminalApprovalUI } from "../../core/approval.js";
import { runFixFlow } from "../../core/flow.js";

export function registerFixCommand(program: Command, io: CliIO): void {
  program
    .command("fix")
    .argument("<message...>", "Bugfix intent message")
    .description("Run the bugfix-intent workflow")
    .action(async (messageParts: string[]) => {
      const agent = new FakeAgentRunner({
        plan: {
          summary: "Test fix plan",
          changes: [{ reason: "intent:fix", targetFiles: ["src/app.ts"], kind: "modify", rationale: "Test agent plan." }],
          questions: [],
          risk: "low",
        },
        writes: {},
      });
      const result = await runFixFlow({ cwd: process.cwd(), message: messageParts.join(" "), agent, approval: new TerminalApprovalUI(io) });
      writeLine(io.stdout, `Run ${result.runId} ${result.applied ? "applied" : "saved"}`);
    });
}
```

Modify `src/cli/main.ts` to import and register `registerPlanCommand`, `registerRunCommand`, and `registerFixCommand`. Replace the stubs for `plan`, `run`, and `fix` with those registrations.

- [ ] **Step 5: Run flow tests and typecheck**

Run:

```bash
npm test -- tests/flow-run.test.ts tests/plan.test.ts tests/validation.test.ts
npm run typecheck
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add src tests
git commit -m "feat: orchestrate approved DetDoc flows"
```

---

### Task 10: `apply` and `replay` Commands

**Files:**
- Modify: `src/core/flow.ts`
- Create: `src/cli/commands/apply.ts`
- Create: `src/cli/commands/replay.ts`
- Modify: `src/cli/main.ts`
- Test: `tests/apply-replay.test.ts`

**Interfaces:**
- Consumes: artifacts, manifest, patch, validation.
- Produces:
  - `applyRun({ cwd, runId, approval }): Promise<FlowResult>`
  - `replayRun({ cwd, runId }): Promise<FlowResult>`
  - CLI commands for `apply <run-id>` and `replay <run-id>`

- [ ] **Step 1: Write failing apply/replay tests**

Create `tests/apply-replay.test.ts`:

```ts
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { FakeAgentRunner } from "../src/core/agent/fake-agent-runner.js";
import { AutoApprovalUI } from "../src/core/approval.js";
import { initConfig } from "../src/core/config.js";
import { applyRun, replayRun, runDocFlow } from "../src/core/flow.js";
import { cleanupFixtures, createGitFixture } from "./helpers/git-fixture.js";

afterEach(cleanupFixtures);

describe("apply and replay", () => {
  it("applies a saved patch that was not applied during run", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const value = 1;\n" });
    await initConfig(fixture.cwd);
    await writeFile(join(fixture.cwd, "docs/spec.md"), "new behavior\n", "utf8");

    const agent = new FakeAgentRunner({
      plan: {
        summary: "Update app value",
        changes: [{ reason: "doc-diff:docs/spec.md:L1-L1", targetFiles: ["src/app.ts"], kind: "modify", rationale: "Update value." }],
        questions: [],
        risk: "low",
      },
      writes: { "src/app.ts": "export const value = 2;\n" },
    });

    const result = await runDocFlow({ cwd: fixture.cwd, agent, approval: new AutoApprovalUI(false) });
    expect(result.applied).toBe(false);
    expect(await readFile(join(fixture.cwd, "src/app.ts"), "utf8")).toBe("export const value = 1;\n");

    const applied = await applyRun({ cwd: fixture.cwd, runId: result.runId, approval: new AutoApprovalUI(true) });
    expect(applied.applied).toBe(true);
    expect(await readFile(join(fixture.cwd, "src/app.ts"), "utf8")).toBe("export const value = 2;\n");
  });

  it("replays a saved patch on matching preimage", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const value = 1;\n" });
    await initConfig(fixture.cwd);
    await writeFile(join(fixture.cwd, "docs/spec.md"), "new behavior\n", "utf8");

    const agent = new FakeAgentRunner({
      plan: {
        summary: "Update app value",
        changes: [{ reason: "doc-diff:docs/spec.md:L1-L1", targetFiles: ["src/app.ts"], kind: "modify", rationale: "Update value." }],
        questions: [],
        risk: "low",
      },
      writes: { "src/app.ts": "export const value = 2;\n" },
    });

    const result = await runDocFlow({ cwd: fixture.cwd, agent, approval: new AutoApprovalUI(false) });
    const replayed = await replayRun({ cwd: fixture.cwd, runId: result.runId });
    expect(replayed.applied).toBe(true);
    expect(await readFile(join(fixture.cwd, "src/app.ts"), "utf8")).toBe("export const value = 2;\n");
  });
});
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
npm test -- tests/apply-replay.test.ts
```

Expected: FAIL because `applyRun` and `replayRun` do not exist.

- [ ] **Step 3: Add apply/replay functions to flow**

Append these exports to `src/core/flow.ts`:

```ts
export async function applyRun(input: { cwd: string; runId: string; approval: ApprovalUI }): Promise<FlowResult> {
  const repo = new GitRepository(input.cwd);
  const store = new ArtifactStore(input.cwd);
  const manifest = await store.readJson<RunManifest>(input.runId, "manifest.json");
  const patch = await store.readText(input.runId, "changes.patch");

  const head = await repo.headCommit();
  if (head !== manifest.baseCommit) {
    throw new DetDocError(`Cannot apply ${input.runId}: current HEAD ${head} does not match base ${manifest.baseCommit}.`, "APPLY_BASE_MISMATCH");
  }

  for (const file of manifest.touchedFiles) {
    const current = await repo.fileSha256(file.path);
    if (current !== file.before) {
      throw new DetDocError(`Cannot apply ${input.runId}: preimage hash mismatch for ${file.path}.`, "APPLY_PREIMAGE_MISMATCH");
    }
  }

  if (!(await input.approval.approvePatch(patch))) {
    return { runId: input.runId, applied: false, patch };
  }

  await repo.applyPatch(patch);
  return { runId: input.runId, applied: true, patch };
}

export async function replayRun(input: { cwd: string; runId: string }): Promise<FlowResult> {
  const repo = new GitRepository(input.cwd);
  const store = new ArtifactStore(input.cwd);
  const manifest = await store.readJson<RunManifest>(input.runId, "manifest.json");
  const patch = await store.readText(input.runId, "changes.patch");
  const config = await loadConfig(input.cwd);

  const head = await repo.headCommit();
  if (head !== manifest.baseCommit) {
    throw new DetDocError(`Cannot replay ${input.runId}: current HEAD ${head} does not match base ${manifest.baseCommit}.`, "REPLAY_BASE_MISMATCH");
  }

  for (const file of manifest.touchedFiles) {
    const current = await repo.fileSha256(file.path);
    if (current !== file.before) {
      throw new DetDocError(`Cannot replay ${input.runId}: preimage hash mismatch for ${file.path}.`, "REPLAY_PREIMAGE_MISMATCH");
    }
  }

  await repo.applyPatch(patch);
  const validationLog = await runValidationCommands({ cwd: input.cwd, config });
  await store.writeText(input.runId, "replay.log", validationLog);
  return { runId: input.runId, applied: true, patch };
}
```

- [ ] **Step 4: Implement CLI commands and register them**

Create `src/cli/commands/apply.ts`:

```ts
import type { Command } from "commander";
import type { CliIO } from "../output.js";
import { writeLine } from "../output.js";
import { TerminalApprovalUI } from "../../core/approval.js";
import { applyRun } from "../../core/flow.js";

export function registerApplyCommand(program: Command, io: CliIO): void {
  program
    .command("apply")
    .argument("<run-id>")
    .description("Apply a saved DetDoc patch")
    .action(async (runId: string) => {
      const result = await applyRun({ cwd: process.cwd(), runId, approval: new TerminalApprovalUI(io) });
      writeLine(io.stdout, `Run ${result.runId} ${result.applied ? "applied" : "not applied"}`);
    });
}
```

Create `src/cli/commands/replay.ts`:

```ts
import type { Command } from "commander";
import type { CliIO } from "../output.js";
import { writeLine } from "../output.js";
import { replayRun } from "../../core/flow.js";

export function registerReplayCommand(program: Command, io: CliIO): void {
  program
    .command("replay")
    .argument("<run-id>")
    .description("Replay a saved DetDoc patch without calling an agent")
    .action(async (runId: string) => {
      const result = await replayRun({ cwd: process.cwd(), runId });
      writeLine(io.stdout, `Run ${result.runId} replayed`);
    });
}
```

Modify `src/cli/main.ts` to import and register `registerApplyCommand` and `registerReplayCommand`. Replace the stubs for `apply` and `replay` with those registrations.

- [ ] **Step 5: Run tests and typecheck**

Run:

```bash
npm test -- tests/apply-replay.test.ts tests/flow-run.test.ts
npm run typecheck
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add src tests
git commit -m "feat: add patch apply and replay"
```

---

### Task 11: Embedded pi SDK Runner with Structured Planning and Guarded Writes

**Files:**
- Create: `src/core/agent/pi-sdk-runner.ts`
- Modify: `src/cli/commands/plan.ts`
- Modify: `src/cli/commands/run.ts`
- Modify: `src/cli/commands/fix.ts`
- Test: `tests/pi-runner-smoke.test.ts`

**Interfaces:**
- Consumes: `AgentRunner`, `ProposedPlan`, pi SDK.
- Produces:
  - `PiSdkRunner implements AgentRunner`
  - `createDefaultAgentRunner(): AgentRunner`
  - CLI commands use `PiSdkRunner` by default and `FakeAgentRunner` only when `DETDOC_FAKE_AGENT=1`.

- [ ] **Step 1: Write pi runner smoke test that is skipped without opt-in**

Create `tests/pi-runner-smoke.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { defaultConfig } from "../src/core/config.js";
import { PiSdkRunner } from "../src/core/agent/pi-sdk-runner.js";

const runSmoke = process.env.DETDOC_PI_SMOKE === "1";

describe.skipIf(!runSmoke)("PiSdkRunner smoke", () => {
  it("can be constructed and exposes AgentRunner methods", async () => {
    const runner = new PiSdkRunner();
    expect(typeof runner.plan).toBe("function");
    expect(typeof runner.implement).toBe("function");
    expect(defaultConfig().agent.provider).toBe("pi-sdk");
  });
});
```

- [ ] **Step 2: Run smoke test without opt-in**

Run:

```bash
npm test -- tests/pi-runner-smoke.test.ts
```

Expected: PASS with the suite skipped.

- [ ] **Step 3: Implement `PiSdkRunner` planning and implementation**

Create `src/core/agent/pi-sdk-runner.ts`:

```ts
import {
  AuthStorage,
  createAgentSession,
  DefaultResourceLoader,
  defineTool,
  ModelRegistry,
  SessionManager,
  SettingsManager,
  type ExtensionFactory,
  isToolCallEventType,
} from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import type { AgentRunner, ImplementRequest, PlanRequest } from "./agent-runner.js";
import { isDeniedPath } from "../paths.js";
import { PlanSchema, type ProposedPlan, validateProposedPlan } from "../plan.js";

function extractLastAssistantText(messages: Array<{ role?: string; content?: unknown }>): string {
  for (const message of [...messages].reverse()) {
    if (message.role !== "assistant") continue;
    if (typeof message.content === "string") return message.content;
    if (Array.isArray(message.content)) {
      return message.content
        .map((part) => (typeof part === "object" && part && "text" in part ? String((part as { text: unknown }).text) : ""))
        .join("");
    }
  }
  return "";
}

function guardExtension(request: ImplementRequest): ExtensionFactory {
  const allowed = new Set(request.approvedTargets);
  return (pi) => {
    pi.on("tool_call", async (event) => {
      if (isToolCallEventType("edit", event) || isToolCallEventType("write", event)) {
        const rawPath = typeof event.input.path === "string" ? event.input.path.replace(/^@/, "") : "";
        if (isDeniedPath(rawPath, request.config)) {
          return { block: true, reason: `DetDoc blocked denied path: ${rawPath}` };
        }
        if (!allowed.has(rawPath)) {
          return { block: true, reason: `DetDoc blocked unapproved path: ${rawPath}` };
        }
      }
      return undefined;
    });
  };
}

export class PiSdkRunner implements AgentRunner {
  async plan(request: PlanRequest): Promise<ProposedPlan> {
    let capturedPlan: ProposedPlan | undefined;
    const submitPlan = defineTool({
      name: "submit_plan",
      label: "Submit Plan",
      description: "Submit the final DetDoc implementation plan as structured JSON.",
      parameters: Type.Object({
        summary: Type.String(),
        changes: Type.Array(
          Type.Object({
            reason: Type.String(),
            targetFiles: Type.Array(Type.String()),
            kind: Type.Union([Type.Literal("create"), Type.Literal("modify"), Type.Literal("delete"), Type.Literal("rename")]),
            rationale: Type.String(),
          }),
        ),
        questions: Type.Array(Type.String()),
        risk: Type.Union([Type.Literal("low"), Type.Literal("medium"), Type.Literal("high")]),
      }),
      async execute(_toolCallId, params) {
        capturedPlan = PlanSchema.parse(params);
        return {
          content: [{ type: "text", text: "DetDoc plan captured." }],
          details: { plan: capturedPlan },
          terminate: true,
        };
      },
    });

    const loader = new DefaultResourceLoader({ cwd: request.cwd });
    await loader.reload();
    const authStorage = AuthStorage.create();
    const modelRegistry = ModelRegistry.create(authStorage);
    const settingsManager = SettingsManager.inMemory({ compaction: { enabled: false } });
    const { session } = await createAgentSession({
      cwd: request.cwd,
      authStorage,
      modelRegistry,
      settingsManager,
      resourceLoader: loader,
      sessionManager: SessionManager.inMemory(request.cwd),
      tools: ["read", "grep", "find", "ls", "submit_plan"],
      customTools: [submitPlan],
      thinkingLevel: request.config.agent.thinking,
    });

    try {
      const prompt = [
        "You are DetDoc planning phase.",
        "Inspect the repository using read-only tools.",
        "Do not modify files.",
        "When ready, call submit_plan exactly once.",
        `Mode: ${request.mode}`,
        "Input:",
        request.input,
      ].join("\n\n");
      await session.prompt(prompt);
      if (capturedPlan) return validateProposedPlan(capturedPlan, { config: request.config, mode: request.mode });

      const text = extractLastAssistantText(session.messages as Array<{ role?: string; content?: unknown }>);
      return validateProposedPlan(JSON.parse(text), { config: request.config, mode: request.mode });
    } finally {
      session.dispose();
    }
  }

  async implement(request: ImplementRequest): Promise<void> {
    const loader = new DefaultResourceLoader({
      cwd: request.cwd,
      extensionFactories: [guardExtension(request)],
    });
    await loader.reload();
    const authStorage = AuthStorage.create();
    const modelRegistry = ModelRegistry.create(authStorage);
    const settingsManager = SettingsManager.inMemory({ compaction: { enabled: false } });
    const { session } = await createAgentSession({
      cwd: request.cwd,
      authStorage,
      modelRegistry,
      settingsManager,
      resourceLoader: loader,
      sessionManager: SessionManager.inMemory(request.cwd),
      tools: ["read", "grep", "find", "ls", "edit", "write"],
      thinkingLevel: request.config.agent.thinking,
    });

    try {
      const prompt = [
        "You are DetDoc implementation phase.",
        "Implement only the approved plan.",
        "Use edit/write only for approved target paths.",
        "If another file is required, stop and explain instead of editing it.",
        `Mode: ${request.mode}`,
        "Approved plan:",
        JSON.stringify(request.approvedPlan, null, 2),
        "Original input:",
        request.input,
      ].join("\n\n");
      await session.prompt(prompt);
    } finally {
      session.dispose();
    }
  }
}

export function createDefaultAgentRunner(): AgentRunner {
  return new PiSdkRunner();
}
```

- [ ] **Step 4: Replace CLI fake defaults with pi default and explicit fake opt-in**

In `src/cli/commands/plan.ts`, `src/cli/commands/run.ts`, and `src/cli/commands/fix.ts`, add a helper like this:

```ts
import type { AgentRunner } from "../../core/agent/agent-runner.js";
import { createDefaultAgentRunner } from "../../core/agent/pi-sdk-runner.js";

function agentFromEnv(fake: FakeAgentRunner): AgentRunner {
  return process.env.DETDOC_FAKE_AGENT === "1" ? fake : createDefaultAgentRunner();
}
```

Use `agentFromEnv(fakeAgent)` where the previous code passed the fake directly. This keeps tests deterministic while making production CLI use embedded pi.

- [ ] **Step 5: Run typecheck and skipped smoke test**

Run:

```bash
npm test -- tests/pi-runner-smoke.test.ts
npm run typecheck
```

Expected: smoke suite skips by default, typecheck passes.

- [ ] **Step 6: Optional local pi smoke command**

Run only when pi credentials are configured:

```bash
DETDOC_PI_SMOKE=1 npm test -- tests/pi-runner-smoke.test.ts
```

Expected: runner construction test passes. Do not require a live model call in default tests.

- [ ] **Step 7: Commit**

```bash
git add src tests
git commit -m "feat: add embedded pi SDK runner"
```

---

### Task 12: Final CLI Polish, End-to-End Verification, and Documentation

**Files:**
- Modify: `README.md`
- Modify: `src/cli/main.ts`
- Modify: existing command files if command descriptions or error messages need exact alignment
- Test: all tests

**Interfaces:**
- Consumes: full MVP.
- Produces: documented CLI with verified commands.

- [ ] **Step 1: Write README usage content**

Create or replace `README.md`:

```md
# DetDoc

DetDoc turns Markdown documentation changes or explicit bugfix intent into approved, validated, replayable code patches using embedded pi.

## Commands

```bash
detdoc init
detdoc diff
detdoc plan
detdoc run
detdoc fix "message to fix"
detdoc apply <run-id>
detdoc replay <run-id>
```

## Workflow

1. Edit Markdown documentation.
2. Run `detdoc run`.
3. Approve the structured plan.
4. Review the generated patch.
5. Type `approve` to apply the patch.

For bug fixes that should not require a documentation edit, run:

```bash
detdoc fix "describe the bug and expected behavior"
```

## Reproducibility

DetDoc stores each run under `.detdoc/runs/<run-id>/`. The stored `changes.patch` can be applied again with:

```bash
detdoc replay <run-id>
```

Replay checks the recorded base commit and preimage file hashes before applying the patch.

## Configuration

Project config lives at `.detdoc/config.yml`.
```

- [ ] **Step 2: Run complete deterministic verification**

Run:

```bash
npm test
npm run typecheck
npm run build
```

Expected: all pass.

- [ ] **Step 3: Run manual CLI smoke with fake agent**

Run:

```bash
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
git init -b main
git config user.name "DetDoc Smoke"
git config user.email "detdoc-smoke@example.com"
echo "old" > README.md
mkdir -p src
echo "export const value = 1;" > src/app.ts
git add .
git commit -m initial
node /absolute/path/to/detdoc/dist/index.js init
echo "new" > README.md
DETDOC_FAKE_AGENT=1 node /absolute/path/to/detdoc/dist/index.js diff
```

Expected: `detdoc init` creates `.detdoc/config.yml`; `detdoc diff` prints a diff for `README.md`.

- [ ] **Step 4: Inspect git status**

Run:

```bash
git status --short
```

Expected in the DetDoc repo: only intended source, test, README, and package files are modified before commit.

- [ ] **Step 5: Commit final polish**

```bash
git add README.md src tests package.json package-lock.json tsconfig.json vitest.config.ts
git commit -m "docs: document DetDoc MVP workflow"
```

---

## Self-Review Checklist

- Spec coverage:
  - Markdown diff input: Tasks 3, 4, 5, 9.
  - `detdoc fix` input: Tasks 7, 9, 10.
  - pi SDK backend: Task 11.
  - temp worktree isolation: Task 5 and Task 9.
  - pre-implementation plan approval: Task 8 and Task 9.
  - final patch approval: Task 8 and Task 9.
  - artifact storage: Task 6 and Task 9.
  - replay without LLM: Task 10.
  - structural and configured validation: Task 8 and Task 9.
  - dirty-state rules: Task 3.
  - CLI commands: Tasks 2, 4, 9, 10, 12.
- Placeholder scan: no task contains missing implementation markers.
- Type consistency:
  - `AgentRunner` methods are `plan` and `implement` throughout.
  - `RunMode` is `"run" | "fix"` throughout.
  - `ProposedPlan` is produced by `PlanSchema` and consumed by approval, validation, flow, fake runner, and pi runner.
  - `RunManifest` fields match artifact, apply, and replay usage.
