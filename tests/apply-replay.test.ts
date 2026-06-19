import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { FakeAgentRunner } from "../src/core/agent/fake-agent-runner.js";
import { AutoApprovalUI, type ApprovalUI } from "../src/core/approval.js";
import { initConfig } from "../src/core/config.js";
import { applyRun, replayRun, runDocFlow } from "../src/core/flow.js";
import type { ProposedPlan } from "../src/core/plan.js";
import { cleanupFixtures, createGitFixture } from "./helpers/git-fixture.js";

afterEach(cleanupFixtures);

class ApprovePlanRejectPatchUI implements ApprovalUI {
  async approvePlan(_plan: ProposedPlan): Promise<boolean> {
    return true;
  }

  async approvePatch(_patch: string): Promise<boolean> {
    return false;
  }
}

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
  it("applies a saved patch that was not applied during run", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const value = 1;\n" });
    await initConfig(fixture.cwd);
    await writeFile(join(fixture.cwd, "docs/spec.md"), "new behavior\n", "utf8");

    const result = await runDocFlow({ cwd: fixture.cwd, agent: updateValueAgent(2), approval: new ApprovePlanRejectPatchUI() });
    expect(result.applied).toBe(false);
    expect(await readFile(join(fixture.cwd, "src/app.ts"), "utf8")).toBe("export const value = 1;\n");

    const applied = await applyRun({ cwd: fixture.cwd, runId: result.runId, approval: new AutoApprovalUI(true) });
    expect(applied.applied).toBe(true);
    expect(await readFile(join(fixture.cwd, "src/app.ts"), "utf8")).toBe("export const value = 2;\n");
  });

  it("replays a saved patch on matching preimage", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const value = 1;\n" });
    await initConfig(fixture.cwd);
    await writeFile(join(fixture.cwd, "docs/spec.md"), "new behavior\n", "utf8");

    const result = await runDocFlow({ cwd: fixture.cwd, agent: updateValueAgent(2), approval: new ApprovePlanRejectPatchUI() });
    const replayed = await replayRun({ cwd: fixture.cwd, runId: result.runId });
    expect(replayed.applied).toBe(true);
    expect(await readFile(join(fixture.cwd, "src/app.ts"), "utf8")).toBe("export const value = 2;\n");
  });
});
