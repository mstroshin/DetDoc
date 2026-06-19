import type { Command } from "commander";
import type { CliIO } from "../output.js";
import { writeLine } from "../output.js";
import { replayRun } from "../../core/flow.js";

export function registerReplayCommand(program: Command, io: CliIO): void {
  program
    .command("replay")
    .argument("<run-id>")
    .description("Replay a saved DetDoc patch without calling an agent")
    .action(async (runId: string) => {
      const result = await replayRun({ cwd: process.cwd(), runId });
      writeLine(io.stdout, `Run ${result.runId} replayed`);
    });
}
