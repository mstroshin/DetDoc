import type { Command } from "commander";
import type { CliIO } from "../output.js";
import { writeLine } from "../output.js";
import { TerminalApprovalUI } from "../../core/approval.js";
import { applyRun } from "../../core/flow.js";

export function registerApplyCommand(program: Command, io: CliIO): void {
  program
    .command("apply")
    .argument("<run-id>")
    .description("Apply a saved DetDoc patch")
    .action(async (runId: string) => {
      const result = await applyRun({ cwd: process.cwd(), runId, approval: new TerminalApprovalUI(io) });
      writeLine(io.stdout, `Run ${result.runId} ${result.applied ? "applied" : "not applied"}`);
    });
}
