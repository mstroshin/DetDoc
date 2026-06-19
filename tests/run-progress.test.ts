import { describe, expect, it } from "vitest";
import { createRunProgressReporter } from "../src/cli/progress.js";
import { createTestIO } from "./helpers/test-io.js";

describe("run progress reporter", () => {
  it("prints readable progress lines when the terminal is not interactive", () => {
    const io = createTestIO();
    const progress = createRunProgressReporter(io);

    progress({ phase: "collect_input", message: "Collecting documentation changes" });
    progress({ phase: "plan", message: "Asking agent for implementation plan" });
    progress({ phase: "approve_plan", message: "Waiting for plan approval" });
    progress({ phase: "implement", message: "Implementing approved plan" });
    progress({ phase: "done", message: "Run complete" });

    expect(io.stderrText()).toContain("◇ Collecting documentation changes");
    expect(io.stderrText()).toContain("◇ Asking agent for implementation plan");
    expect(io.stderrText()).toContain("◇ Waiting for plan approval");
    expect(io.stderrText()).toContain("◇ Implementing approved plan");
    expect(io.stderrText()).toContain("✓ Run complete");
  });
});
