import type { Command } from "commander";
import type { CliIO } from "../output.js";
import { writeLine } from "../output.js";
import type { AgentRunner } from "../../core/agent/agent-runner.js";
import { FakeAgentRunner } from "../../core/agent/fake-agent-runner.js";
import { createDefaultAgentRunner } from "../../core/agent/pi-sdk-runner.js";
import { TerminalApprovalUI } from "../../core/approval.js";
import { runFixFlow } from "../../core/flow.js";

function agentFromEnv(fake: FakeAgentRunner): AgentRunner {
  return process.env.DETDOC_FAKE_AGENT === "1" ? fake : createDefaultAgentRunner();
}

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
        agent: agentFromEnv(agent),
        approval: new TerminalApprovalUI(io),
      });
      writeLine(io.stdout, `Run ${result.runId} ${result.applied ? "applied" : "saved"}`);
    });
}
