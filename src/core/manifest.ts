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
