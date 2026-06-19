import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { defaultConfig } from "../src/core/config.js";
import { ArtifactStore } from "../src/core/artifacts.js";
import { createInitialManifest, createRunId } from "../src/core/manifest.js";
import { sha256Text } from "../src/core/hash.js";
import { GitRepository } from "../src/core/git.js";
import { cleanupFixtures, createGitFixture } from "./helpers/git-fixture.js";

afterEach(cleanupFixtures);

describe("artifacts", () => {
  it("creates stable run id", () => {
    expect(createRunId("run", "abcdef1234567890", new Date("2026-06-19T20:00:00Z"))).toBe("20260619T200000Z-run-abcdef12");
  });

  it("writes manifest and input artifacts", async () => {
    const fixture = await createGitFixture({ "README.md": "hello\n" });
    const repo = new GitRepository(fixture.cwd);
    const config = defaultConfig();
    const input = "diff text\n";
    const manifest = await createInitialManifest({
      mode: "run",
      repo,
      config,
      input,
      createdAt: new Date("2026-06-19T20:00:00Z"),
    });

    const store = new ArtifactStore(fixture.cwd);
    const dir = await store.createRun(manifest);
    await store.writeText(manifest.runId, "input.diff.md", input);

    const manifestText = await readFile(join(dir, "manifest.json"), "utf8");
    expect(JSON.parse(manifestText).inputHash).toBe(sha256Text(input));
    expect(await readFile(join(dir, "input.diff.md"), "utf8")).toBe(input);
  });
});
