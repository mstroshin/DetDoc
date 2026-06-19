import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createTestIO } from "./helpers/test-io.js";
import { cleanupFixtures, createGitFixture } from "./helpers/git-fixture.js";
import { runCli } from "../src/cli/main.js";
import { initConfig } from "../src/core/config.js";
import { getNormalizedDocDiff } from "../src/core/diff.js";
import { GitRepository } from "../src/core/git.js";
import { defaultConfig } from "../src/core/config.js";

afterEach(cleanupFixtures);

describe("normalized doc diff", () => {
  it("returns stable git diff for dirty docs", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const x = 1;\n" });
    await writeFile(join(fixture.cwd, "docs/spec.md"), "new\n", "utf8");

    const diff = await getNormalizedDocDiff(new GitRepository(fixture.cwd), defaultConfig());

    expect(diff).toContain("diff --git a/docs/spec.md b/docs/spec.md");
    expect(diff).toContain("-old");
    expect(diff).toContain("+new");
    expect(diff.endsWith("\n")).toBe(true);
  });

  it("includes untracked markdown files as new file patches without staging them", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n" });
    await mkdir(join(fixture.cwd, "docs", "features"), { recursive: true });
    await writeFile(join(fixture.cwd, "docs", "features", "main_screen.md"), "# Main Screen\n\nShow songs.\n", "utf8");

    const diff = await getNormalizedDocDiff(new GitRepository(fixture.cwd), defaultConfig());

    expect(diff).toContain("diff --git a/docs/features/main_screen.md b/docs/features/main_screen.md");
    expect(diff).toContain("new file mode 100644");
    expect(diff).toContain("+# Main Screen");
    expect(await fixture.git(["status", "--short", "--untracked-files=all"])).toMatchObject({
      stdout: expect.stringContaining("?? docs/features/main_screen.md"),
    });
  });

  it("excludes tracked DetDoc metadata from normalized doc diff", async () => {
    const fixture = await createGitFixture({ "README.md": "old\n", ".detdoc/config.yml": "old-config\n" });
    await writeFile(join(fixture.cwd, "README.md"), "new\n", "utf8");
    await writeFile(join(fixture.cwd, ".detdoc/config.yml"), "new-config\n", "utf8");

    const diff = await getNormalizedDocDiff(new GitRepository(fixture.cwd), defaultConfig());

    expect(diff).toContain("diff --git a/README.md b/README.md");
    expect(diff).not.toContain(".detdoc/config.yml");
  });

  it("prints diff through CLI", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n" });
    await initConfig(fixture.cwd);
    await writeFile(join(fixture.cwd, "docs/spec.md"), "new\n", "utf8");

    const oldCwd = process.cwd();
    process.chdir(fixture.cwd);
    try {
      const io = createTestIO();
      const code = await runCli(["node", "detdoc", "diff"], io);
      expect(code).toBe(0);
      expect(io.stdoutText()).toContain("diff --git a/docs/spec.md b/docs/spec.md");
    } finally {
      process.chdir(oldCwd);
    }
  });
});
