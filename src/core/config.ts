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
