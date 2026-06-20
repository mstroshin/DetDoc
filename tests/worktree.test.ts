import { access, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { defaultConfig } from "../src/core/config.js";
import { getNormalizedDocDiff } from "../src/core/diff.js";
import { GitRepository } from "../src/core/git.js";
import { WorktreeManager } from "../src/core/worktree.js";
import { cleanupFixtures, createGitFixture } from "./helpers/git-fixture.js";

afterEach(cleanupFixtures);

describe("WorktreeManager", () => {
  it("creates worktree from HEAD and applies only doc diff", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const x = 1;\n" });
    await writeFile(join(fixture.cwd, "docs/spec.md"), "new\n", "utf8");
    const baseRepo = new GitRepository(fixture.cwd);
    const diff = await getNormalizedDocDiff(baseRepo, defaultConfig());

    const manager = new WorktreeManager();
    const worktree = await manager.createFromHead(baseRepo, { prefix: "detdoc-test-" });
    try {
      await worktree.repo.applyPatch(diff);
      expect(await readFile(join(worktree.path, "docs/spec.md"), "utf8")).toBe("new\n");
      expect(await readFile(join(worktree.path, "src/app.ts"), "utf8")).toBe("export const x = 1;\n");
    } finally {
      await worktree.cleanup();
    }
  });

  it("creates a visible branch worktree and cleans up its branch", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const x = 1;\n" });
    const baseRepo = new GitRepository(fixture.cwd);
    const manager = new WorktreeManager();
    const runId = "20260620T121500Z-run-abcdef12";
    const path = join(fixture.cwd, ".worktrees", runId);

    const worktree = await manager.createFromHead(baseRepo, { path, branchName: runId });
    try {
      expect(worktree.path).toBe(path);
      await expect(worktree.repo.git(["branch", "--show-current"])).resolves.toBe(`${runId}\n`);
      await expect(access(path)).resolves.toBeUndefined();
    } finally {
      await worktree.cleanup();
    }

    await expect(access(path)).rejects.toThrow();
    const branches = await baseRepo.git(["branch", "--list", runId]);
    expect(branches.trim()).toBe("");
  });
});
