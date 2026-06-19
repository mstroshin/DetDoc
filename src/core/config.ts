import { execFile } from "node:child_process";
import { access, mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { promisify } from "node:util";
import YAML from "yaml";
import { z } from "zod";
import { DetDocError } from "./errors.js";

const execFileAsync = promisify(execFile);

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

interface StarterDoc {
  path: string;
  content: string;
}

function starterDocs(): StarterDoc[] {
  return [
    {
      path: "docs/idea.md",
      content: `# Project Idea

Describe the product in plain language.

## Problem

What user problem should this project solve?

## Users

Who uses it, and in what context?

## Desired Outcome

What should be true when the project works well?
`,
    },
    {
      path: "docs/technical-spec.md",
      content: `# Technical Specification

Keep durable technical decisions here. This file is intentionally free-form Markdown.

## Architecture

Describe the main components and how data flows between them.

## Constraints

List platform, dependency, security, performance, and compatibility constraints.

## Validation

List deterministic commands or checks that prove the project still works.
`,
    },
    {
      path: "docs/features/_guide.md",
      content: `# Feature Planning Guide

Use this folder for free-form feature planning.

A feature may be a single Markdown file or a folder with several documents. Prefer whatever shape makes the intent clear to a human reviewer and to DetDoc.

Suggested per-feature files:

- \`brief.md\` — what the feature should do and why.
- \`plan.md\` — implementation notes, sequencing, and open questions.
- \`notes.md\` — decisions, trade-offs, examples, or sketches.

Do not treat these headings as a strict schema. DetDoc reads normal Markdown diffs.
`,
    },
    {
      path: "docs/features/example-feature/brief.md",
      content: `# Example Feature Brief

## Goal

Describe the user-visible behavior this feature should add or change.

## Acceptance Notes

- What should be observable when the feature is complete?
- Which cases should not be changed?
`,
    },
    {
      path: "docs/features/example-feature/plan.md",
      content: `# Example Feature Plan

Use this file for free-form implementation planning.

## Possible Approach

Describe the likely code areas and sequencing.

## Open Questions

- What needs clarification before implementation?
`,
    },
    {
      path: "docs/features/example-feature/notes.md",
      content: `# Example Feature Notes

Use this file for decisions, examples, rejected approaches, or follow-up ideas.
`,
    },
  ];
}

async function writeIfMissing(path: string, content: string): Promise<boolean> {
  if (await exists(path)) return false;
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, content, "utf8");
  return true;
}

async function git(cwd: string, args: string[]): Promise<string> {
  const { stdout } = await execFileAsync("git", args, { cwd, env: process.env });
  return stdout;
}

async function isInsideGitRepository(cwd: string): Promise<boolean> {
  try {
    return (await git(cwd, ["rev-parse", "--is-inside-work-tree"])).trim() === "true";
  } catch {
    return false;
  }
}

async function hasGitHead(cwd: string): Promise<boolean> {
  try {
    await git(cwd, ["rev-parse", "--verify", "HEAD"]);
    return true;
  } catch {
    return false;
  }
}

async function gitStatus(cwd: string): Promise<string> {
  return git(cwd, ["status", "--porcelain=v1", "--untracked-files=all"]);
}

async function shouldCreateInitialCommit(cwd: string): Promise<boolean> {
  if (!(await isInsideGitRepository(cwd))) return false;
  if (await hasGitHead(cwd)) return false;
  return (await gitStatus(cwd)).trim() === "";
}

async function createInitialCommit(cwd: string, files: string[]): Promise<boolean> {
  if (files.length === 0) return false;
  await git(cwd, ["add", "--", ...files]);
  await git(cwd, ["commit", "-m", "Initial DetDoc setup"]);
  return true;
}

async function ensureGitignoreEntry(cwd: string, entry: string): Promise<boolean> {
  const path = join(cwd, ".gitignore");
  if (!(await exists(path))) {
    await writeFile(path, `${entry}\n`, "utf8");
    return true;
  }

  const current = await readFile(path, "utf8");
  const lines = current.split(/\r?\n/).map((line) => line.trim());
  if (lines.includes(entry)) return false;

  const separator = current.length === 0 || current.endsWith("\n") ? "" : "\n";
  await writeFile(path, `${current}${separator}${entry}\n`, "utf8");
  return true;
}

export async function initStarterDocs(cwd: string): Promise<string[]> {
  const created: string[] = [];
  for (const doc of starterDocs()) {
    const absolutePath = join(cwd, doc.path);
    if (await writeIfMissing(absolutePath, doc.content)) {
      created.push(doc.path);
    }
  }
  return created;
}

export async function initConfig(cwd: string): Promise<{ created: boolean; path: string; docsCreated: string[]; initialCommitCreated: boolean }> {
  const path = configPath(cwd);
  const configExists = await exists(path);
  const createInitialCommitAfterInit = await shouldCreateInitialCommit(cwd);
  const generatedFiles: string[] = [];

  await mkdir(dirname(path), { recursive: true });
  await mkdir(join(cwd, ".detdoc", "runs"), { recursive: true });
  if (!configExists) {
    await writeFile(path, defaultConfigYaml(), "utf8");
    generatedFiles.push(".detdoc/config.yml");
  }
  if (await writeIfMissing(join(cwd, ".detdoc", "runs", ".gitkeep"), "")) {
    generatedFiles.push(".detdoc/runs/.gitkeep");
  }
  if (await ensureGitignoreEntry(cwd, ".DS_Store")) {
    generatedFiles.push(".gitignore");
  }
  const docsCreated = await initStarterDocs(cwd);
  generatedFiles.push(...docsCreated);
  const initialCommitCreated = createInitialCommitAfterInit ? await createInitialCommit(cwd, generatedFiles) : false;
  return { created: !configExists, path, docsCreated, initialCommitCreated };
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
