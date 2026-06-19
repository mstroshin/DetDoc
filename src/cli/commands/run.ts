import type { Command } from "commander";
import type { CliIO } from "../output.js";
import { writeLine } from "../output.js";
import { FakeAgentRunner } from "../../core/agent/fake-agent-runner.js";
import { TerminalApprovalUI } from "../../core/approval.js";
import { runDocFlow } from "../../core/flow.js";

export function registerRunCommand(program: Command, io: CliIO): void {
  program
    .command("run")
    .description("Run the documentation-diff workflow")
    .action(async () => {
      const agent = new FakeAgentRunner({
        plan: {
          summary: "Test plan",
          changes: [
            {
              reason: "doc-diff:docs/spec.md:L1-L1",
              targetFiles: ["src/app.ts"],
              kind: "modify",
              rationale: "Test agent plan.",
            },
          ],
          questions: [],
          risk: "low",
        },
        writes: {},
      });
      const result = await runDocFlow({ cwd: process.cwd(), agent, approval: new TerminalApprovalUI(io) });
      writeLine(io.stdout, `Run ${result.runId} ${result.applied ? "applied" : "saved"}`);
    });
}
