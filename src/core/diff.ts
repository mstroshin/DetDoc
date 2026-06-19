import { readFile } from "node:fs/promises";
import { join } from "node:path";
import type { DetDocConfig } from "./config.js";
import { DetDocError } from "./errors.js";
import type { DirtyFile, GitRepository } from "./git.js";
import { assertRunDirtyPolicy, isDocPath } from "./paths.js";

function newFilePatch(relativePath: string, content: string): string {
  const hasTrailingNewline = content.endsWith("\n");
  const lines = hasTrailingNewline ? content.slice(0, -1).split("\n") : content.split("\n");
  const lineCount = lines.length === 1 && lines[0] === "" ? 0 : lines.length;
  const hunk = lineCount === 0 ? "" : [`@@ -0,0 +1,${lineCount} @@`, ...lines.map((line) => `+${line}`), ...(hasTrailingNewline ? [] : ["\\ No newline at end of file"])].join("\n") + "\n";

  return [
    `diff --git a/${relativePath} b/${relativePath}`,
    "new file mode 100644",
    "--- /dev/null",
    `+++ b/${relativePath}`,
    hunk.trimEnd(),
  ]
    .filter((line) => line.length > 0)
    .join("\n") + "\n";
}

async function untrackedDocPatch(repo: GitRepository, files: DirtyFile[]): Promise<string> {
  const patches = await Promise.all(
    files.map(async (file) => newFilePatch(file.path, await readFile(join(repo.cwd, file.path), "utf8"))),
  );
  return patches.join("");
}

export async function getNormalizedDocDiff(repo: GitRepository, config: DetDocConfig): Promise<string> {
  const dirty = await assertRunDirtyPolicy(repo, config);
  const docFiles = dirty.filter((file) => isDocPath(file.path, config)).sort((a, b) => a.path.localeCompare(b.path));
  const trackedDocPaths = docFiles.filter((file) => file.status !== "??").map((file) => file.path);
  const untrackedDocFiles = docFiles.filter((file) => file.status === "??");
  const diff = `${await repo.diffPaths(trackedDocPaths)}${await untrackedDocPatch(repo, untrackedDocFiles)}`;
  if (diff.trim().length === 0) {
    throw new DetDocError("No documentation changes found.", "NO_DOC_DIFF");
  }
  return diff.endsWith("\n") ? diff : `${diff}\n`;
}
