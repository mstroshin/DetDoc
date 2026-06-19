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
