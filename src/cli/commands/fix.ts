import type { Command } from "commander";
import type { CliIO } from "../output.js";
import { writeLine } from "../output.js";
import { FakeAgentRunner } from "../../core/agent/fake-agent-runner.js";
import { TerminalApprovalUI } from "../../core/approval.js";
import { runFixFlow } from "../../core/flow.js";

export function registerFixCommand(program: Command, io: CliIO): void {
  program
    .command("fix")
    .argument("<message...>", "Bugfix intent message")
    .description("Run the bugfix-intent workflow")
    .action(async (messageParts: string[]) => {
      const agent = new FakeAgentRunner({
        plan: {
          summary: "Test fix plan",
          changes: [
            {
              reason: "intent:fix",
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
      const result = await runFixFlow({
        cwd: process.cwd(),
        message: messageParts.join(" "),
        agent,
        approval: new TerminalApprovalUI(io),
      });
      writeLine(io.stdout, `Run ${result.runId} ${result.applied ? "applied" : "saved"}`);
    });
}
