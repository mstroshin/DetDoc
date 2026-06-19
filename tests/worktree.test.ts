import { readFile, writeFile } from "node:fs/promises";
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
});
