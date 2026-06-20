import { writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { runCli } from "../src/cli/main.js";
import { ArtifactStore } from "../src/core/artifacts.js";
import { defaultConfig, initConfig } from "../src/core/config.js";
import { GitRepository } from "../src/core/git.js";
import { createInitialManifest } from "../src/core/manifest.js";
import { cleanupFixtures, createGitFixture } from "./helpers/git-fixture.js";
import { createTestIO } from "./helpers/test-io.js";

afterEach(cleanupFixtures);

async function createSavedPatchRun(cwd: string): Promise<string> {
  const repo = new GitRepository(cwd);
  const config = defaultConfig();
  const manifest = await createInitialManifest({ mode: "run", repo, config, input: "test input" });
  manifest.approvedTargets = ["src/app.ts"];
  manifest.touchedFiles = [
    {
      path: "src/app.ts",
      before: await repo.fileSha256("src/app.ts"),
      after: null,
    },
  ];
  const store = new ArtifactStore(cwd);
  await store.createRun(manifest);
  await writeFile(join(cwd, "src", "app.ts"), "export const value = 2;\n", "utf8");
  const patch = await repo.git(["diff", "--no-color", "--no-ext-diff", "--binary", "--", "src/app.ts"]);
  await repo.git(["checkout", "--", "src/app.ts"]);
  await store.writeText(manifest.runId, "changes.patch", patch.endsWith("\n") ? patch : `${patch}\n`);
  await store.writeJson(manifest.runId, "manifest.json", manifest);
  return manifest.runId;
}

describe("apply command progress", () => {
  it("prints progress while applying a saved run", async () => {
    const fixture = await createGitFixture({ "src/app.ts": "export const value = 1;\n" });
    await initConfig(fixture.cwd);
    const runId = await createSavedPatchRun(fixture.cwd);

    const previousCwd = process.cwd();
    process.chdir(fixture.cwd);
    try {
      const io = createTestIO();
      const code = await runCli(["node", "detdoc", "apply", runId], io);

      expect(code).toBe(0);
      expect(io.stderrText()).toContain("◇ Applying saved patch");
      expect(io.stderrText()).toContain("◇ Removing run artifacts");
      expect(io.stderrText()).toContain("◇ Committing applied changes");
      expect(io.stderrText()).toContain("✓ Apply complete");
      expect(io.stdoutText()).toContain(`Run ${runId} applied`);
    } finally {
      process.chdir(previousCwd);
    }
  });
});
