import { access, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import YAML from "yaml";
import { AutoApprovalUI, type ApprovalUI } from "../src/core/approval.js";
import { defaultConfig, initConfig } from "../src/core/config.js";
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

    const progress: string[] = [];
    const approval: ApprovalUI = {
      async approvePlan() {
        return true;
      },
    };
    const result = await runDocFlow({ cwd: fixture.cwd, agent, approval, progress: (event) => progress.push(event.phase) });

    expect(progress).toEqual([
      "load_config",
      "collect_input",
      "create_run",
      "create_worktree",
      "apply_input_to_worktree",
      "plan",
      "approve_plan",
      "implement",
      "implement",
      "collect_patch",
      "validate_patch",
      "apply_patch",
      "cleanup_worktree",
      "done",
    ]);
    expect(result.applied).toBe(true);
    expect(await readFile(join(fixture.cwd, "src/app.ts"), "utf8")).toBe("export const value = 2;\n");
    expect(result.runId).toMatch(/-run-/);
  });

  it("reports concrete files while the agent writes approved targets", async () => {
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
    const implementMessages: string[] = [];

    await runDocFlow({
      cwd: fixture.cwd,
      agent,
      approval: new AutoApprovalUI(true),
      progress: (event) => {
        if (event.phase === "implement") implementMessages.push(event.message);
      },
    });

    expect(implementMessages).toContain("Agent is writing src/app.ts");
  });

  it("does not report done when plan approval is rejected", async () => {
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
    const progress: string[] = [];

    await expect(runDocFlow({ cwd: fixture.cwd, agent, approval: new AutoApprovalUI(false), progress: (event) => progress.push(event.phase) })).rejects.toThrow(
      "Plan was not approved.",
    );

    expect(progress).toContain("approve_plan");
    expect(progress).not.toContain("done");
  });

  it("runs validation commands again after applying the patch to the main worktree", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const value = 1;\n" });
    await initConfig(fixture.cwd);
    const config = defaultConfig();
    config.validation.commands = [
      {
        name: "Generate project artifact",
        run: 'node -e "const fs=require(\'fs\');fs.mkdirSync(\'Generated.xcodeproj\',{recursive:true});fs.writeFileSync(\'Generated.xcodeproj/project.pbxproj\',\'generated\')"',
      },
    ];
    await writeFile(join(fixture.cwd, ".detdoc", "config.yml"), YAML.stringify(config), "utf8");
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
    const progress: string[] = [];

    await expect(access(join(fixture.cwd, "Generated.xcodeproj", "project.pbxproj"))).rejects.toThrow();
    const result = await runDocFlow({ cwd: fixture.cwd, agent, approval: new AutoApprovalUI(true), progress: (event) => progress.push(event.phase) });

    expect(result.applied).toBe(true);
    expect(progress).toContain("post_apply_validation");
    expect(await readFile(join(fixture.cwd, "Generated.xcodeproj", "project.pbxproj"), "utf8")).toBe("generated");
    expect(await readFile(join(fixture.cwd, ".detdoc", "runs", result.runId, "post-apply-validation.log"), "utf8")).toContain("Generate project artifact");
  });

  it("uses validation commands added to config by the approved patch in the same run", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const value = 1;\n" });
    await initConfig(fixture.cwd);
    await writeFile(join(fixture.cwd, "docs/spec.md"), "new behavior with generated project\n", "utf8");
    const updatedConfig = defaultConfig();
    updatedConfig.validation.commands = [
      {
        name: "Generate project from updated config",
        run: 'node -e "const fs=require(\'fs\');fs.mkdirSync(\'GeneratedFromUpdatedConfig.xcodeproj\',{recursive:true});fs.writeFileSync(\'GeneratedFromUpdatedConfig.xcodeproj/project.pbxproj\',\'generated from updated config\')"',
      },
    ];

    const agent = new FakeAgentRunner({
      plan: {
        summary: "Update app and DetDoc validation",
        changes: [
          {
            reason: "doc-diff:docs/spec.md:L1-L1",
            targetFiles: [".detdoc/config.yml", "src/app.ts"],
            kind: "modify",
            rationale: "The documentation requires generated project validation to run through DetDoc.",
          },
        ],
        questions: [],
        risk: "low",
      },
      writes: {
        ".detdoc/config.yml": YAML.stringify(updatedConfig),
        "src/app.ts": "export const value = 2;\n",
      },
    });

    const result = await runDocFlow({ cwd: fixture.cwd, agent, approval: new AutoApprovalUI(true) });

    expect(result.applied).toBe(true);
    expect(await readFile(join(fixture.cwd, "GeneratedFromUpdatedConfig.xcodeproj", "project.pbxproj"), "utf8")).toBe("generated from updated config");
    expect(await readFile(join(fixture.cwd, ".detdoc", "runs", result.runId, "validation.log"), "utf8")).toContain("Generate project from updated config");
    expect(await readFile(join(fixture.cwd, ".detdoc", "runs", result.runId, "post-apply-validation.log"), "utf8")).toContain(
      "Generate project from updated config",
    );
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
