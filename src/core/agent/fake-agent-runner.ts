import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import type { AgentRunner, ImplementRequest, PlanRequest } from "./agent-runner.js";
import type { ProposedPlan } from "../plan.js";

export class FakeAgentRunner implements AgentRunner {
  constructor(
    private readonly options: {
      plan: ProposedPlan;
      writes?: Record<string, string>;
    },
  ) {}

  async plan(_request: PlanRequest): Promise<ProposedPlan> {
    return this.options.plan;
  }

  async implement(request: ImplementRequest): Promise<void> {
    for (const [relativePath, content] of Object.entries(this.options.writes ?? {})) {
      if (!request.approvedTargets.includes(relativePath)) {
        throw new Error(`FakeAgentRunner attempted unapproved write: ${relativePath}`);
      }
      request.progress?.({ action: "write", path: relativePath });
      const absolute = join(request.cwd, relativePath);
      await mkdir(dirname(absolute), { recursive: true });
      await writeFile(absolute, content, "utf8");
    }
  }
}
