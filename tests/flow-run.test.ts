import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { AutoApprovalUI } from "../src/core/approval.js";
import { initConfig } from "../src/core/config.js";
import { FakeAgentRunner } from "../src/core/agent/fake-agent-runner.js";
import { runDocFlow, runFixFlow } from "../src/core/flow.js";
import { cleanupFixtures, createGitFixture } from "./helpers/git-fixture.js";

afterEach(cleanupFixtures);

describe("DetDoc flows", () => {
  it("runs doc-diff flow and applies approved patch", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const value = 1;\n" });
    await initConfig(fixture.cwd);
    await writeFile(join(fixture.cwd, "docs/spec.md"), "new behavior\n", "utf8");

    const agent = new FakeAgentRunner({
      plan: {
        summary: "Update app value",
        changes: [
          {
            reason: "doc-diff:docs/spec.md:L1-L1",
            targetFiles: ["src/app.ts"],
            kind: "modify",
            rationale: "The changed documentation requires value 2.",
          },
        ],
        questions: [],
        risk: "low",
      },
      writes: { "src/app.ts": "export const value = 2;\n" },
    });

    const result = await runDocFlow({ cwd: fixture.cwd, agent, approval: new AutoApprovalUI(true) });

    expect(result.applied).toBe(true);
    expect(await readFile(join(fixture.cwd, "src/app.ts"), "utf8")).toBe("export const value = 2;\n");
    expect(result.runId).toMatch(/-run-/);
  });

  it("runs doc-diff flow that creates new approved files", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n" });
    await initConfig(fixture.cwd);
    await writeFile(join(fixture.cwd, "docs/spec.md"), "create a tiny greeter\n", "utf8");

    const agent = new FakeAgentRunner({
      plan: {
        summary: "Create greeter files",
        changes: [
          {
            reason: "doc-diff:docs/spec.md:L1-L1",
            targetFiles: ["package.json", "src/index.js"],
            kind: "create",
            rationale: "The changed documentation asks for a tiny greeter project.",
          },
        ],
        questions: [],
        risk: "low",
      },
      writes: {
        "package.json": "{\"scripts\":{\"start\":\"node src/index.js\"}}\n",
        "src/index.js": "console.log('Hello from DetDoc!');\n",
      },
    });

    const result = await runDocFlow({ cwd: fixture.cwd, agent, approval: new AutoApprovalUI(true) });

    expect(result.applied).toBe(true);
    expect(await readFile(join(fixture.cwd, "package.json"), "utf8")).toContain("start");
    expect(await readFile(join(fixture.cwd, "src/index.js"), "utf8")).toContain("Hello from DetDoc!");
  });

  it("runs fix flow while ignoring dirty docs", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const value = 1;\n" });
    await initConfig(fixture.cwd);
    await writeFile(join(fixture.cwd, "docs/spec.md"), "dirty but ignored\n", "utf8");

    const agent = new FakeAgentRunner({
      plan: {
        summary: "Fix value",
        changes: [
          {
            reason: "intent:fix",
            targetFiles: ["src/app.ts"],
            kind: "modify",
            rationale: "The bugfix intent says the value is wrong.",
          },
        ],
        questions: [],
        risk: "low",
      },
      writes: { "src/app.ts": "export const value = 3;\n" },
    });

    const result = await runFixFlow({ cwd: fixture.cwd, message: "fix wrong value", agent, approval: new AutoApprovalUI(true) });

    expect(result.applied).toBe(true);
    expect(await readFile(join(fixture.cwd, "src/app.ts"), "utf8")).toBe("export const value = 3;\n");
    expect(await readFile(join(fixture.cwd, "docs/spec.md"), "utf8")).toBe("dirty but ignored\n");
  });
});
