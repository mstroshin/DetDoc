import { describe, expect, it } from "vitest";
import { createRunProgressReporter } from "../src/cli/progress.js";
import { createTestIO } from "./helpers/test-io.js";

describe("run progress reporter", () => {
  it("prints readable progress lines when the terminal is not interactive", () => {
    const io = createTestIO();
    const progress = createRunProgressReporter(io);

    progress({ phase: "collect_input", message: "Collecting documentation changes" });
    progress({ phase: "plan", message: "Agent is planning code changes" });
    progress({ phase: "approve_plan", message: "Waiting for plan approval" });
    progress({ phase: "implement", message: "Agent is editing approved files" });
    progress({ phase: "repair_validation", message: "Agent is fixing validation failure (1/2)" });
    progress({ phase: "merge_worktree", message: "Merging validated worktree changes into main" });
    progress({ phase: "post_apply_validation", message: "Running validation commands in main worktree" });
    progress({ phase: "cleanup_run", message: "Removing run artifacts" });
    progress({ phase: "done", message: "Run complete" });

    expect(io.stderrText()).toContain("◇ Collecting documentation changes");
    expect(io.stderrText()).toContain("◇ Agent is planning code changes");
    expect(io.stderrText()).toContain("◇ Waiting for plan approval");
    expect(io.stderrText()).toContain("◇ Agent is editing approved files");
    expect(io.stderrText()).toContain("◇ Agent is fixing validation failure (1/2)");
    expect(io.stderrText()).toContain("◇ Merging validated worktree changes into main");
    expect(io.stderrText()).toContain("◇ Running validation commands in main worktree");
    expect(io.stderrText()).toContain("◇ Removing run artifacts");
    expect(io.stderrText()).toContain("✓ Run complete");
  });
});
