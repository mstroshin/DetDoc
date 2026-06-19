import type { Command } from "commander";
import type { CliIO } from "../output.js";
import { writeLine } from "../output.js";
import { FakeAgentRunner } from "../../core/agent/fake-agent-runner.js";
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

export function registerPlanCommand(program: Command, io: CliIO): void {
  program
    .command("plan")
    .description("Create an implementation plan without applying code changes")
    .action(async () => {
      const result = await createPlanFlow({ cwd: process.cwd(), agent: testAgent() });
      writeLine(io.stdout, `Plan saved for run ${result.runId}`);
    });
}
