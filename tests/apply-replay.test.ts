import { access, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { ArtifactStore } from "../src/core/artifacts.js";
import { defaultConfig, initConfig } from "../src/core/config.js";
import { applyRun, replayRun } from "../src/core/flow.js";
import { createInitialManifest } from "../src/core/manifest.js";
import { GitRepository } from "../src/core/git.js";
import { cleanupFixtures, createGitFixture } from "./helpers/git-fixture.js";

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
  await fixtureCheckout(cwd, "src/app.ts");
  await store.writeText(manifest.runId, "changes.patch", patch.endsWith("\n") ? patch : `${patch}\n`);
  await store.writeJson(manifest.runId, "manifest.json", manifest);
  return manifest.runId;
}

async function fixtureCheckout(cwd: string, path: string): Promise<void> {
  await new GitRepository(cwd).git(["checkout", "--", path]);
}

describe("apply and replay", () => {
  it("applies a saved patch without asking for code approval and removes the run artifacts", async () => {
    const fixture = await createGitFixture({ "src/app.ts": "export const value = 1;\n" });
    await initConfig(fixture.cwd);
    const runId = await createSavedPatchRun(fixture.cwd);

    const applied = await applyRun({ cwd: fixture.cwd, runId });

    expect(applied.applied).toBe(true);
    expect(await readFile(join(fixture.cwd, "src", "app.ts"), "utf8")).toBe("export const value = 2;\n");
    await expect(access(join(fixture.cwd, ".detdoc", "runs", runId))).rejects.toThrow();
  });

  it("replays a saved patch on matching preimage without deleting the run artifacts", async () => {
    const fixture = await createGitFixture({ "src/app.ts": "export const value = 1;\n" });
    await initConfig(fixture.cwd);
    const runId = await createSavedPatchRun(fixture.cwd);

    const replayed = await replayRun({ cwd: fixture.cwd, runId });

    expect(replayed.applied).toBe(true);
    expect(await readFile(join(fixture.cwd, "src", "app.ts"), "utf8")).toBe("export const value = 2;\n");
    await expect(access(join(fixture.cwd, ".detdoc", "runs", runId, "manifest.json"))).resolves.toBeUndefined();
  });
});
