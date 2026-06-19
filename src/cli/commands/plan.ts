import type { Command } from "commander";
import type { CliIO } from "../output.js";
import { writeLine } from "../output.js";
import type { AgentRunner } from "../../core/agent/agent-runner.js";
import { FakeAgentRunner } from "../../core/agent/fake-agent-runner.js";
import { createDefaultAgentRunner } from "../../core/agent/pi-sdk-runner.js";
import { createPlanFlow } from "../../core/flow.js";

function testAgent(): FakeAgentRunner {
  return new FakeAgentRunner({
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
  });
}

function agentFromEnv(fake: FakeAgentRunner): AgentRunner {
  return process.env.DETDOC_FAKE_AGENT === "1" ? fake : createDefaultAgentRunner();
}

export function registerPlanCommand(program: Command, io: CliIO): void {
  program
    .command("plan")
    .description("Create an implementation plan without applying code changes")
    .action(async () => {
      const fakeAgent = testAgent();
      const result = await createPlanFlow({ cwd: process.cwd(), agent: agentFromEnv(fakeAgent) });
      writeLine(io.stdout, `Plan saved for run ${result.runId}`);
    });
}
