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
