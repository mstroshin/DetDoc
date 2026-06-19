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
