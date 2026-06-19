import type { Command } from "commander";
import type { CliIO } from "../output.js";
import { writeLine } from "../output.js";
import type { AgentRunner } from "../../core/agent/agent-runner.js";
import { FakeAgentRunner } from "../../core/agent/fake-agent-runner.js";
import { createDefaultAgentRunner } from "../../core/agent/pi-sdk-runner.js";
import { TerminalApprovalUI } from "../../core/approval.js";
import { runDocFlow } from "../../core/flow.js";
import { createRunProgressController } from "../progress.js";

function agentFromEnv(fake: FakeAgentRunner): AgentRunner {
  return process.env.DETDOC_FAKE_AGENT === "1" ? fake : createDefaultAgentRunner();
}

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
      const progress = createRunProgressController(io);
      try {
        const result = await runDocFlow({ cwd: process.cwd(), agent: agentFromEnv(agent), approval: new TerminalApprovalUI(io), progress: progress.report });
        writeLine(io.stdout, `Run ${result.runId} ${result.applied ? "applied" : "saved"}`);
      } catch (error) {
        progress.fail();
        throw error;
      }
    });
}
