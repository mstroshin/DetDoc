import type { DetDocConfig } from "./config.js";
import { DetDocError } from "./errors.js";
import type { GitRepository } from "./git.js";
import { assertRunDirtyPolicy, isDocPath } from "./paths.js";

export async function getNormalizedDocDiff(repo: GitRepository, config: DetDocConfig): Promise<string> {
  const dirty = await assertRunDirtyPolicy(repo, config);
  const docPaths = dirty.map((file) => file.path).filter((path) => isDocPath(path, config)).sort();
  const diff = await repo.diffPaths(docPaths);
  if (diff.trim().length === 0) {
    throw new DetDocError("No documentation changes found.", "NO_DOC_DIFF");
  }
  return diff.endsWith("\n") ? diff : `${diff}\n`;
}
