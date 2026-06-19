import { execFile } from "node:child_process";
import { access, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import { afterEach, describe, expect, it } from "vitest";
import { createTestIO } from "./helpers/test-io.js";
import { runCli } from "../src/cli/main.js";
import { defaultConfig, initConfig, loadConfig } from "../src/core/config.js";

const execFileAsync = promisify(execFile);
const dirs: string[] = [];

async function tempDir(): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "detdoc-config-"));
  dirs.push(dir);
  return dir;
}

async function git(cwd: string, args: string[]): Promise<string> {
  const { stdout } = await execFileAsync("git", args, {
    cwd,
    env: {
      ...process.env,
      GIT_AUTHOR_NAME: "DetDoc Test",
      GIT_AUTHOR_EMAIL: "detdoc@example.com",
      GIT_COMMITTER_NAME: "DetDoc Test",
      GIT_COMMITTER_EMAIL: "detdoc@example.com",
    },
  });
  return stdout;
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

  it("creates starter project documentation without README files", async () => {
    const cwd = await tempDir();
    await initConfig(cwd);

    const idea = await readFile(join(cwd, "docs", "idea.md"), "utf8");
    const technicalSpec = await readFile(join(cwd, "docs", "technical-spec.md"), "utf8");
    const featuresGuide = await readFile(join(cwd, "docs", "features", "_guide.md"), "utf8");
    const featureBrief = await readFile(join(cwd, "docs", "features", "example-feature", "brief.md"), "utf8");
    const featurePlan = await readFile(join(cwd, "docs", "features", "example-feature", "plan.md"), "utf8");
    const featureNotes = await readFile(join(cwd, "docs", "features", "example-feature", "notes.md"), "utf8");

    expect(idea).toContain("# Project Idea");
    expect(technicalSpec).toContain("# Technical Specification");
    expect(featuresGuide).toContain("# Feature Planning Guide");
    expect(featureBrief).toContain("# Example Feature Brief");
    expect(featurePlan).toContain("# Example Feature Plan");
    expect(featureNotes).toContain("# Example Feature Notes");

    await expect(access(join(cwd, "README.md"))).rejects.toThrow();
    await expect(access(join(cwd, "docs", "README.md"))).rejects.toThrow();
    await expect(access(join(cwd, "docs", "features", "README.md"))).rejects.toThrow();
  });

  it("does not overwrite existing starter documentation", async () => {
    const cwd = await tempDir();
    await mkdir(join(cwd, "docs"), { recursive: true });
    await writeFile(join(cwd, "docs", "idea.md"), "custom idea\n", "utf8");

    await initConfig(cwd);

    expect(await readFile(join(cwd, "docs", "idea.md"), "utf8")).toBe("custom idea\n");
    expect(await readFile(join(cwd, "docs", "technical-spec.md"), "utf8")).toContain("# Technical Specification");
  });

  it("creates gitignore with macOS metadata ignored", async () => {
    const cwd = await tempDir();

    await initConfig(cwd);

    expect(await readFile(join(cwd, ".gitignore"), "utf8")).toBe(".DS_Store\n");
  });

  it("creates an initial DetDoc setup commit in an empty git repository", async () => {
    const cwd = await tempDir();
    await git(cwd, ["init", "-b", "main"]);
    await git(cwd, ["config", "user.name", "DetDoc Test"]);
    await git(cwd, ["config", "user.email", "detdoc@example.com"]);

    const result = await initConfig(cwd);

    expect(result.initialCommitCreated).toBe(true);
    expect((await git(cwd, ["log", "--oneline", "-1"]))).toContain("Initial DetDoc setup");
    expect(await git(cwd, ["status", "--short"])).toBe("");
    expect(await git(cwd, ["show", "--name-only", "--format=", "HEAD"])).toContain(".gitignore");
    expect(await git(cwd, ["show", "--name-only", "--format=", "HEAD"])).toContain(".detdoc/config.yml");
    expect(await git(cwd, ["show", "--name-only", "--format=", "HEAD"])).toContain("docs/idea.md");
  });

  it("does not create an initial commit when an empty git repository already has user changes", async () => {
    const cwd = await tempDir();
    await git(cwd, ["init", "-b", "main"]);
    await writeFile(join(cwd, "user-file.txt"), "keep me uncommitted\n", "utf8");

    const result = await initConfig(cwd);

    expect(result.initialCommitCreated).toBe(false);
    await expect(git(cwd, ["rev-parse", "--verify", "HEAD"])).rejects.toThrow();
    expect(await git(cwd, ["status", "--short"])).toContain("user-file.txt");
  });

  it("adds macOS metadata ignore to existing gitignore without duplicating it", async () => {
    const cwd = await tempDir();
    await writeFile(join(cwd, ".gitignore"), "node_modules/\n", "utf8");

    await initConfig(cwd);
    await initConfig(cwd);

    expect(await readFile(join(cwd, ".gitignore"), "utf8")).toBe("node_modules/\n.DS_Store\n");
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
