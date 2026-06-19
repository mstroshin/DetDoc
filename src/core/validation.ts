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
