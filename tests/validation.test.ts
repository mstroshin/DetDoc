import { writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { defaultConfig } from "../src/core/config.js";
import { GitRepository } from "../src/core/git.js";
import { collectPatch, runValidationCommands, validatePatch } from "../src/core/validation.js";
import { cleanupFixtures, createGitFixture } from "./helpers/git-fixture.js";

afterEach(cleanupFixtures);

describe("patch validation", () => {
  it("accepts patch touching approved target", async () => {
    const fixture = await createGitFixture({ "src/app.ts": "export const x = 1;\n" });
    await writeFile(join(fixture.cwd, "src/app.ts"), "export const x = 2;\n", "utf8");
    const repo = new GitRepository(fixture.cwd);
    const patch = await collectPatch(repo);

    const result = await validatePatch({
      patch,
      repo,
      config: defaultConfig(),
      mode: "run",
      approvedTargets: ["src/app.ts"],
    });

    expect(result.changedFiles).toEqual(["src/app.ts"]);
  });

  it("rejects unapproved target", async () => {
    const fixture = await createGitFixture({ "src/app.ts": "export const x = 1;\n" });
    await writeFile(join(fixture.cwd, "src/app.ts"), "export const x = 2;\n", "utf8");
    const repo = new GitRepository(fixture.cwd);
    const patch = await collectPatch(repo);

    await expect(
      validatePatch({ patch, repo, config: defaultConfig(), mode: "run", approvedTargets: ["src/other.ts"] }),
    ).rejects.toThrow("unapproved path");
  });

  it("rejects doc changes in fix mode", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n" });
    await writeFile(join(fixture.cwd, "docs/spec.md"), "new\n", "utf8");
    const repo = new GitRepository(fixture.cwd);
    const patch = await collectPatch(repo);

    await expect(
      validatePatch({ patch, repo, config: defaultConfig(), mode: "fix", approvedTargets: ["docs/spec.md"] }),
    ).rejects.toThrow("fix patches must not modify documentation files");
  });
});

describe("validation commands", () => {
  it("captures configured command output", async () => {
    const fixture = await createGitFixture({ "package.json": "{\"scripts\":{\"check\":\"node -e \\\"console.log('ok')\\\"\"}}\n" });
    const config = defaultConfig();
    config.validation.commands = [{ name: "check", run: "npm run check" }];

    const log = await runValidationCommands({ cwd: fixture.cwd, config });
    expect(log).toContain("$ npm run check");
    expect(log).toContain("ok");
  });
});
