import type { Command } from "commander";
import type { CliIO } from "../output.js";
import { writeLine } from "../output.js";
import type { AgentRunner } from "../../core/agent/agent-runner.js";
import { FakeAgentRunner } from "../../core/agent/fake-agent-runner.js";
import { createDefaultAgentRunner } from "../../core/agent/pi-sdk-runner.js";
import { TerminalApprovalUI, type ApplyApprovalContext } from "../../core/approval.js";
import { runDocFlow, type FlowProgressReporter } from "../../core/flow.js";
import { createRunProgressController } from "../progress.js";

function agentFromEnv(fake: FakeAgentRunner): AgentRunner {
  return process.env.DETDOC_FAKE_AGENT === "1" ? fake : createDefaultAgentRunner();
}

function approvalFromOptions(io: CliIO, options: RunOptions) {
  const terminal = new TerminalApprovalUI(io);
  return {
    approvePlan: options.autoApprove ? async () => true : terminal.approvePlan.bind(terminal),
    approveApply: options.autoApply ? async (_context: ApplyApprovalContext) => true : terminal.approveApply.bind(terminal),
  };
}

function progressFromOptions(report: FlowProgressReporter, options: RunOptions): FlowProgressReporter {
  return (event) => {
    if (options.autoApprove && event.phase === "approve_plan") return;
    if (options.autoApply && event.phase === "approve_apply") return;
    report(event);
  };
}

interface RunOptions {
  autoApprove?: boolean;
  autoApply?: boolean;
}

export function registerRunCommand(program: Command, io: CliIO): void {
  program
    .command("run")
    .description("Run the documentation-diff workflow")
    .option("--auto-approve", "approve the proposed plan without prompting")
    .option("--auto-apply", "apply generated changes without prompting")
    .action(async (options: RunOptions) => {
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
        writes: { "src/app.ts": "export const value = 2;\n" },
      });
      const progress = createRunProgressController(io);
      try {
        const approval = approvalFromOptions(io, options);
        const result = await runDocFlow({ cwd: process.cwd(), agent: agentFromEnv(agent), approval, progress: progressFromOptions(progress.report, options) });
        writeLine(io.stdout, `Run ${result.runId} ${result.applied ? "applied" : "saved"}`);
      } catch (error) {
        progress.fail();
        throw error;
      }
    });
}
