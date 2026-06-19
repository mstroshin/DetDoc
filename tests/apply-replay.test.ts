import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { FakeAgentRunner } from "../src/core/agent/fake-agent-runner.js";
import { AutoApprovalUI } from "../src/core/approval.js";
import { initConfig } from "../src/core/config.js";
import { applyRun, replayRun, runDocFlow } from "../src/core/flow.js";
import { cleanupFixtures, createGitFixture } from "./helpers/git-fixture.js";

afterEach(cleanupFixtures);

function updateValueAgent(value: number): FakeAgentRunner {
  return new FakeAgentRunner({
    plan: {
      summary: "Update app value",
      changes: [
        {
          reason: "doc-diff:docs/spec.md:L1-L1",
          targetFiles: ["src/app.ts"],
          kind: "modify",
          rationale: "Update value.",
        },
      ],
      questions: [],
      risk: "low",
    },
    writes: { "src/app.ts": `export const value = ${value};\n` },
  });
}

describe("apply and replay", () => {
  it("applies a saved patch without asking for code approval", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const value = 1;\n" });
    await initConfig(fixture.cwd);
    await writeFile(join(fixture.cwd, "docs/spec.md"), "new behavior\n", "utf8");

    const result = await runDocFlow({ cwd: fixture.cwd, agent: updateValueAgent(2), approval: new AutoApprovalUI(true) });
    expect(result.applied).toBe(true);
    expect(await readFile(join(fixture.cwd, "src/app.ts"), "utf8")).toBe("export const value = 2;\n");

    await fixture.git(["checkout", "--", "src/app.ts"]);
    expect(await readFile(join(fixture.cwd, "src/app.ts"), "utf8")).toBe("export const value = 1;\n");

    const applied = await applyRun({ cwd: fixture.cwd, runId: result.runId });
    expect(applied.applied).toBe(true);
    expect(await readFile(join(fixture.cwd, "src/app.ts"), "utf8")).toBe("export const value = 2;\n");
  });

  it("replays a saved patch on matching preimage", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const value = 1;\n" });
    await initConfig(fixture.cwd);
    await writeFile(join(fixture.cwd, "docs/spec.md"), "new behavior\n", "utf8");

    const result = await runDocFlow({ cwd: fixture.cwd, agent: updateValueAgent(2), approval: new AutoApprovalUI(true) });
    await fixture.git(["checkout", "--", "src/app.ts"]);

    const replayed = await replayRun({ cwd: fixture.cwd, runId: result.runId });
    expect(replayed.applied).toBe(true);
    expect(await readFile(join(fixture.cwd, "src/app.ts"), "utf8")).toBe("export const value = 2;\n");
  });
});
