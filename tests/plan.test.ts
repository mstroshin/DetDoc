import { describe, expect, it } from "vitest";
import { defaultConfig } from "../src/core/config.js";
import { FakeAgentRunner } from "../src/core/agent/fake-agent-runner.js";
import { approvedTargetsFromPlan, validateProposedPlan } from "../src/core/plan.js";

describe("plan validation", () => {
  it("accepts a plan with diff-linked target files", () => {
    const plan = validateProposedPlan(
      {
        summary: "Update API behavior",
        changes: [
          {
            reason: "doc-diff:docs/api.md:L1-L4",
            targetFiles: ["src/api.ts"],
            kind: "modify",
            rationale: "The API implementation must follow the changed behavior.",
          },
        ],
        questions: [],
        risk: "low",
      },
      { config: defaultConfig(), mode: "run" },
    );

    expect(approvedTargetsFromPlan(plan)).toEqual(["src/api.ts"]);
  });

  it("rejects denied target paths", () => {
    expect(() =>
      validateProposedPlan(
        {
          summary: "Bad plan",
          changes: [
            {
              reason: "intent:fix",
              targetFiles: [".env"],
              kind: "modify",
              rationale: "This should never be allowed.",
            },
          ],
          questions: [],
          risk: "low",
        },
        { config: defaultConfig(), mode: "fix" },
      ),
    ).toThrow("denied path");
  });

  it("rejects documentation targets for run mode", () => {
    expect(() =>
      validateProposedPlan(
        {
          summary: "Bad run plan",
          changes: [
            {
              reason: "doc-diff:docs/spec.md:L1-L1",
              targetFiles: ["docs/spec.md"],
              kind: "modify",
              rationale: "Implementation must not rewrite source documentation.",
            },
          ],
          questions: [],
          risk: "low",
        },
        { config: defaultConfig(), mode: "run" },
      ),
    ).toThrow("plans must not target documentation files");
  });

  it("rejects doc targets for fix mode", () => {
    expect(() =>
      validateProposedPlan(
        {
          summary: "Bad fix plan",
          changes: [
            {
              reason: "intent:fix",
              targetFiles: ["docs/spec.md"],
              kind: "modify",
              rationale: "Fix mode must not change docs in the MVP.",
            },
          ],
          questions: [],
          risk: "low",
        },
        { config: defaultConfig(), mode: "fix" },
      ),
    ).toThrow("plans must not target documentation files");
  });
});

describe("FakeAgentRunner", () => {
  it("returns configured plan", async () => {
    const runner = new FakeAgentRunner({
      plan: {
        summary: "Fake plan",
        changes: [
          {
            reason: "intent:fix",
            targetFiles: ["src/app.ts"],
            kind: "modify",
            rationale: "The fake runner is deterministic.",
          },
        ],
        questions: [],
        risk: "low",
      },
    });

    const plan = await runner.plan({ mode: "fix", input: "fix bug", config: defaultConfig(), cwd: "/tmp/project" });
    expect(plan.summary).toBe("Fake plan");
  });
});
