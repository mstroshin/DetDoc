import type { Command } from "commander";
import type { CliIO } from "../output.js";
import { writeLine } from "../output.js";
import { applyRun } from "../../core/flow.js";
import { createRunProgressController } from "../progress.js";

export function registerApplyCommand(program: Command, io: CliIO): void {
  program
    .command("apply")
    .argument("<run-id>")
    .description("Apply a saved DetDoc patch")
    .action(async (runId: string) => {
      const progress = createRunProgressController(io);
      try {
        const result = await applyRun({ cwd: process.cwd(), runId, progress: progress.report });
        writeLine(io.stdout, `Run ${result.runId} ${result.applied ? "applied" : "not applied"}`);
      } catch (error) {
        progress.fail("Apply failed");
        throw error;
      }
    });
}
