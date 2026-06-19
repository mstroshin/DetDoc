import { describe, expect, it } from "vitest";
import { defaultConfig } from "../src/core/config.js";
import { buildPlanningPrompt } from "../src/core/agent/pi-sdk-runner.js";

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
