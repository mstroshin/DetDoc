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

    expect(await readFile(join(cwd, ".gitignore"), "utf8")).toBe(".DS_Store\n.detdoc/runs/*\n!.detdoc/runs/.gitkeep\n.worktrees/\n");
  });

  it("initializes git and creates a setup commit when no repository exists", async () => {
    const cwd = await tempDir();
    await writeFile(join(cwd, "user-file.txt"), "keep me untracked\n", "utf8");

    const result = await initConfig(cwd);

    expect(result.gitInitialized).toBe(true);
    expect(result.initialCommitCreated).toBe(true);
    expect((await git(cwd, ["rev-parse", "--is-inside-work-tree"])).trim()).toBe("true");
    expect((await git(cwd, ["log", "--oneline", "-1"]))).toContain("Initial DetDoc setup");

    const committedFiles = await git(cwd, ["show", "--name-only", "--format=", "HEAD"]);
    expect(committedFiles).toContain(".gitignore");
    expect(committedFiles).toContain(".detdoc/config.yml");
    expect(committedFiles).toContain(".detdoc/runs/.gitkeep");
    expect(committedFiles).not.toContain("docs/idea.md");
    expect(committedFiles).not.toContain("user-file.txt");

    const status = await git(cwd, ["status", "--short", "--untracked-files=all"]);
    expect(status).toContain("?? docs/idea.md");
    expect(status).toContain("?? user-file.txt");
  });

  it("creates an initial DetDoc setup commit without committing starter docs", async () => {
    const cwd = await tempDir();
    await git(cwd, ["init", "-b", "main"]);
    await git(cwd, ["config", "user.name", "DetDoc Test"]);
    await git(cwd, ["config", "user.email", "detdoc@example.com"]);

    const result = await initConfig(cwd);

    expect(result.initialCommitCreated).toBe(true);
    expect((await git(cwd, ["log", "--oneline", "-1"]))).toContain("Initial DetDoc setup");
    const committedFiles = await git(cwd, ["show", "--name-only", "--format=", "HEAD"]);
    expect(committedFiles).toContain(".gitignore");
    expect(committedFiles).toContain(".detdoc/config.yml");
    expect(committedFiles).toContain(".detdoc/runs/.gitkeep");
    expect(committedFiles).not.toContain("docs/idea.md");
    expect(committedFiles).not.toContain("docs/technical-spec.md");

    const status = await git(cwd, ["status", "--short", "--untracked-files=all"]);
    expect(status).toContain("?? docs/idea.md");
    expect(status).toContain("?? docs/technical-spec.md");
    expect(await readFile(join(cwd, "docs", "idea.md"), "utf8")).toContain("# Project Idea");
  });

  it("creates a DetDoc setup commit in an existing clean git repository", async () => {
    const cwd = await tempDir();
    await git(cwd, ["init", "-b", "main"]);
    await git(cwd, ["config", "user.name", "DetDoc Test"]);
    await git(cwd, ["config", "user.email", "detdoc@example.com"]);
    await writeFile(join(cwd, "existing.txt"), "already committed\n", "utf8");
    await git(cwd, ["add", "existing.txt"]);
    await git(cwd, ["commit", "-m", "Existing project"]);

    const result = await initConfig(cwd);

    expect(result.initialCommitCreated).toBe(true);
    expect((await git(cwd, ["log", "--oneline", "-1"]))).toContain("Initial DetDoc setup");
    const committedFiles = await git(cwd, ["show", "--name-only", "--format=", "HEAD"]);
    expect(committedFiles).toContain(".gitignore");
    expect(committedFiles).toContain(".detdoc/config.yml");
    expect(committedFiles).toContain(".detdoc/runs/.gitkeep");
    expect(committedFiles).not.toContain("docs/idea.md");

    const status = await git(cwd, ["status", "--short", "--untracked-files=all"]);
    expect(status).toContain("?? docs/idea.md");
    expect(status).toContain("?? docs/technical-spec.md");
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

    expect(await readFile(join(cwd, ".gitignore"), "utf8")).toBe("node_modules/\n.DS_Store\n.detdoc/runs/*\n!.detdoc/runs/.gitkeep\n.worktrees/\n");
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
      expect(io.stdoutText()).toContain("Initialized git repository");
      expect(io.stdoutText()).toContain("Created .detdoc/config.yml");
    } finally {
      process.chdir(oldCwd);
    }
  });

  it("accepts validation commands written with command aliases", async () => {
    const cwd = await tempDir();
    await initConfig(cwd);
    await writeFile(
      join(cwd, ".detdoc", "config.yml"),
      `docs:
  include:
    - "**/*.md"
  exclude:
    - .detdoc/**
    - node_modules/**
paths:
  deny:
    - .env
    - .env.*
    - node_modules/**
    - .git/**
validation:
  commands:
    - name: Generate Xcode project
      command: xcodegen generate
    - cmd: swift test
agent:
  provider: pi-sdk
  model: null
  thinking: high
worktree:
  keepOnFailure: true
`,
      "utf8",
    );

    const config = await loadConfig(cwd);

    expect(config.validation.commands).toEqual([
      { name: "Generate Xcode project", run: "xcodegen generate" },
      { name: "swift test", run: "swift test" },
    ]);
  });

  it("accepts validation commands written as string shorthand", async () => {
    const cwd = await tempDir();
    await initConfig(cwd);
    await writeFile(
      join(cwd, ".detdoc", "config.yml"),
      `docs:
  include:
    - "**/*.md"
  exclude:
    - .detdoc/**
    - node_modules/**
paths:
  deny:
    - .env
    - .env.*
    - node_modules/**
    - .git/**
validation:
  commands:
    - xcodegen generate
    - swift test
agent:
  provider: pi-sdk
  model: null
  thinking: high
worktree:
  keepOnFailure: true
`,
      "utf8",
    );

    const config = await loadConfig(cwd);

    expect(config.validation.commands).toEqual([
      { name: "xcodegen generate", run: "xcodegen generate" },
      { name: "swift test", run: "swift test" },
    ]);
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
