import { describe, expect, it } from "vitest";
import { defaultConfig } from "../src/core/config.js";
import {
  buildImplementationPrompt,
  buildPlanningPrompt,
  buildValidationRepairPrompt,
  implementationToolNames,
  validateAgentToolPath,
} from "../src/core/agent/pi-sdk-runner.js";

describe("PiSdkRunner planning prompt", () => {
  it("states exact reason requirements for run mode", () => {
    const prompt = buildPlanningPrompt({
      mode: "run",
      input: "diff --git a/docs/spec.md b/docs/spec.md\n",
      config: defaultConfig(),
      cwd: "/tmp/project",
    });

    expect(prompt).toContain("Every changes[].reason MUST start with `doc-diff:`");
    expect(prompt).toContain("Example: `doc-diff:docs/spec.md:L1-L20`");
    expect(prompt).toContain("Do not use free-form prose in changes[].reason");
    expect(prompt).toContain("If the documentation names validation or generation commands");
    expect(prompt).toContain("include `.detdoc/config.yml` in targetFiles");
    expect(prompt).toContain("Prefer validation.commands entries shaped as `{ name, run }`");
    expect(prompt).toContain("Do not target documentation files");
  });

  it("states exact reason requirements for fix mode", () => {
    const prompt = buildPlanningPrompt({
      mode: "fix",
      input: "fix wrong greeting",
      config: defaultConfig(),
      cwd: "/tmp/project",
    });

    expect(prompt).toContain("Every changes[].reason MUST be `intent:fix`");
    expect(prompt).toContain("Fix mode MUST NOT target documentation files");
  });
});

describe("PiSdkRunner implementation phase", () => {
  it("allows bash for diagnostics while keeping source edits scoped", () => {
    expect(implementationToolNames).toContain("bash");

    const request = {
      mode: "run" as const,
      input: "diff --git a/docs/spec.md b/docs/spec.md\n",
      config: defaultConfig(),
      cwd: "/tmp/project",
      approvedPlan: {
        summary: "Update app",
        changes: [
          {
            reason: "doc-diff:docs/spec.md:L1-L1",
            targetFiles: ["src/app.ts"],
            kind: "modify" as const,
            rationale: "Update app behavior.",
          },
        ],
        questions: [],
        risk: "low" as const,
      },
      approvedTargets: ["src/app.ts"],
    };

    const prompt = buildImplementationPrompt(request);

    expect(prompt).toContain("Use bash for diagnostics, generation, builds, and tests");
    expect(prompt).toContain("Use edit/write only for approved target paths");
    expect(prompt).toContain("Documentation files are read-only");
  });

  it("allows bash while repairing validation failures", () => {
    const prompt = buildValidationRepairPrompt({
      mode: "run",
      input: "diff --git a/docs/spec.md b/docs/spec.md\n",
      config: defaultConfig(),
      cwd: "/tmp/project",
      approvedPlan: {
        summary: "Update app",
        changes: [
          {
            reason: "doc-diff:docs/spec.md:L1-L1",
            targetFiles: ["src/app.ts"],
            kind: "modify",
            rationale: "Update app behavior.",
          },
        ],
        questions: [],
        risk: "low",
      },
      approvedTargets: ["src/app.ts"],
      validationLog: "xcodebuild failed",
      attempt: 1,
    });

    expect(prompt).toContain("Use bash to inspect and reproduce the validation failure");
    expect(prompt).toContain("Fix the failure by editing only approved target paths");
  });
});

describe("PiSdkRunner path guard", () => {
  it("blocks writes outside the project root", () => {
    const result = validateAgentToolPath({
      cwd: "/tmp/project",
      toolName: "write",
      rawPath: "../outside.txt",
      approvedTargets: ["src/app.ts"],
      config: defaultConfig(),
    });

    if (result.allowed) throw new Error("expected path to be blocked");
    expect(result.reason).toContain("outside project root");
  });

  it("blocks writes to documentation files even if approved", () => {
    const result = validateAgentToolPath({
      cwd: "/tmp/project",
      toolName: "write",
      rawPath: "docs/spec.md",
      approvedTargets: ["docs/spec.md"],
      config: defaultConfig(),
    });

    if (result.allowed) throw new Error("expected docs path to be blocked");
    expect(result.reason).toContain("documentation files are read-only");
  });
});
