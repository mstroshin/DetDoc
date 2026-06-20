import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { runCli } from "../src/cli/main.js";
import { initConfig } from "../src/core/config.js";
import { cleanupFixtures, createGitFixture } from "./helpers/git-fixture.js";
import { createTestIO } from "./helpers/test-io.js";

afterEach(cleanupFixtures);

async function runWithFakeAgentInFixture(args: string[]) {
  const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const value = 1;\n" });
  await initConfig(fixture.cwd);
  await writeFile(join(fixture.cwd, "docs/spec.md"), "new behavior\n", "utf8");

  const previousCwd = process.cwd();
  const previousFakeAgent = process.env.DETDOC_FAKE_AGENT;
  process.chdir(fixture.cwd);
  process.env.DETDOC_FAKE_AGENT = "1";
  try {
    const io = createTestIO();
    const code = await runCli(["node", "detdoc", ...args], io);
    return { code, io, fixture };
  } finally {
    process.chdir(previousCwd);
    if (previousFakeAgent === undefined) delete process.env.DETDOC_FAKE_AGENT;
    else process.env.DETDOC_FAKE_AGENT = previousFakeAgent;
  }
}

describe("run command options", () => {
  it("documents auto approval and auto apply flags", async () => {
    const io = createTestIO();
    const code = await runCli(["node", "detdoc", "run", "--help"], io);

    expect(code).toBe(0);
    expect(io.stdoutText()).toContain("--auto-approve");
    expect(io.stdoutText()).toContain("--auto-apply");
  });

  it("documents token usage flag", async () => {
    const io = createTestIO();
    const code = await runCli(["node", "detdoc", "run", "--help"], io);

    expect(code).toBe(0);
    expect(io.stdoutText()).toContain("--show-token-usage");
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
      expect(io.stderrText()).not.toContain("Waiting for plan approval");
      expect(io.stdoutText()).toMatch(/Run .* saved/);
      expect(await readFile(join(fixture.cwd, "src/app.ts"), "utf8")).toBe("export const value = 1;\n");
    } finally {
      process.chdir(previousCwd);
      if (previousFakeAgent === undefined) delete process.env.DETDOC_FAKE_AGENT;
      else process.env.DETDOC_FAKE_AGENT = previousFakeAgent;
    }
  });

  it("does not print token usage without the flag", async () => {
    const { code, io } = await runWithFakeAgentInFixture(["run", "--auto-approve"]);

    expect(code).toBe(0);
    expect(io.stdoutText()).toMatch(/Run .* saved/);
    expect(io.stdoutText()).not.toContain("Token usage:");
  });

  it("prints token usage with the flag", async () => {
    const { code, io } = await runWithFakeAgentInFixture(["run", "--auto-approve", "--show-token-usage"]);

    expect(code).toBe(0);
    expect(io.stdoutText()).toMatch(/Run .* saved/);
    expect(io.stdoutText()).toContain("Token usage:");
    expect(io.stdoutText()).toContain("plan: input 0, output 0, cache read 0, cache write 0, total 0");
    expect(io.stdoutText()).toContain("implement: input 0, output 0, cache read 0, cache write 0, total 0");
    expect(io.stdoutText()).toContain("total: input 0, output 0, cache read 0, cache write 0, total 0");
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
      expect(io.stderrText()).not.toContain("Waiting for plan approval");
      expect(io.stderrText()).not.toContain("Waiting for apply approval");
      expect(io.stdoutText()).toMatch(/Run .* applied/);
      expect(await readFile(join(fixture.cwd, "src/app.ts"), "utf8")).toBe("export const value = 2;\n");
    } finally {
      process.chdir(previousCwd);
      if (previousFakeAgent === undefined) delete process.env.DETDOC_FAKE_AGENT;
      else process.env.DETDOC_FAKE_AGENT = previousFakeAgent;
    }
  });
});
