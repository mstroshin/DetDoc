import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { runCli } from "../src/cli/main.js";
import { initConfig } from "../src/core/config.js";
import { cleanupFixtures, createGitFixture } from "./helpers/git-fixture.js";
import { createTestIO } from "./helpers/test-io.js";

afterEach(cleanupFixtures);

describe("run command options", () => {
  it("documents auto approval and auto apply flags", async () => {
    const io = createTestIO();
    const code = await runCli(["node", "detdoc", "run", "--help"], io);

    expect(code).toBe(0);
    expect(io.stdoutText()).toContain("--auto-approve");
    expect(io.stdoutText()).toContain("--auto-apply");
  });

  it("auto-approves the plan without applying when --auto-apply is omitted", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const value = 1;\n" });
    await initConfig(fixture.cwd);
    await writeFile(join(fixture.cwd, "docs/spec.md"), "new behavior\n", "utf8");

    const previousCwd = process.cwd();
    const previousFakeAgent = process.env.DETDOC_FAKE_AGENT;
    process.chdir(fixture.cwd);
    process.env.DETDOC_FAKE_AGENT = "1";
    try {
      const io = createTestIO();
      const code = await runCli(["node", "detdoc", "run", "--auto-approve"], io);

      expect(code).toBe(0);
      expect(io.stderrText()).not.toContain("unknown option");
      expect(io.stderrText()).not.toContain("Plan was not approved");
      expect(io.stdoutText()).toMatch(/Run .* saved/);
      expect(await readFile(join(fixture.cwd, "src/app.ts"), "utf8")).toBe("export const value = 1;\n");
    } finally {
      process.chdir(previousCwd);
      if (previousFakeAgent === undefined) delete process.env.DETDOC_FAKE_AGENT;
      else process.env.DETDOC_FAKE_AGENT = previousFakeAgent;
    }
  });

  it("auto-approves and auto-applies when both run flags are provided", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const value = 1;\n" });
    await initConfig(fixture.cwd);
    await writeFile(join(fixture.cwd, "docs/spec.md"), "new behavior\n", "utf8");

    const previousCwd = process.cwd();
    const previousFakeAgent = process.env.DETDOC_FAKE_AGENT;
    process.chdir(fixture.cwd);
    process.env.DETDOC_FAKE_AGENT = "1";
    try {
      const io = createTestIO();
      const code = await runCli(["node", "detdoc", "run", "--auto-approve", "--auto-apply"], io);

      expect(code).toBe(0);
      expect(io.stderrText()).not.toContain("unknown option");
      expect(io.stderrText()).not.toContain("Plan was not approved");
      expect(io.stdoutText()).toMatch(/Run .* applied/);
      expect(await readFile(join(fixture.cwd, "src/app.ts"), "utf8")).toBe("export const value = 2;\n");
    } finally {
      process.chdir(previousCwd);
      if (previousFakeAgent === undefined) delete process.env.DETDOC_FAKE_AGENT;
      else process.env.DETDOC_FAKE_AGENT = previousFakeAgent;
    }
  });
});
