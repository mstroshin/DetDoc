import { createInterface } from "node:readline/promises";
import type { CliIO } from "../cli/output.js";
import { writeLine } from "../cli/output.js";
import type { ProposedPlan } from "./plan.js";

export interface ApprovalUI {
  approvePlan(plan: ProposedPlan): Promise<boolean>;
  approvePatch(patch: string): Promise<boolean>;
}

export class AutoApprovalUI implements ApprovalUI {
  constructor(private readonly approved = true) {}

  async approvePlan(_plan: ProposedPlan): Promise<boolean> {
    return this.approved;
  }

  async approvePatch(_patch: string): Promise<boolean> {
    return this.approved;
  }
}

export class TerminalApprovalUI implements ApprovalUI {
  constructor(private readonly io: CliIO) {}

  async approvePlan(plan: ProposedPlan): Promise<boolean> {
    writeLine(this.io.stdout, JSON.stringify(plan, null, 2));
    return this.confirm("Approve this plan? Type 'approve' to continue: ");
  }

  async approvePatch(patch: string): Promise<boolean> {
    writeLine(this.io.stdout, patch);
    return this.confirm("Apply this patch? Type 'approve' to continue: ");
  }

  private async confirm(prompt: string): Promise<boolean> {
    if (!this.io.isInteractive) return false;
    const rl = createInterface({ input: this.io.stdin, output: this.io.stdout });
    try {
      const answer = await rl.question(prompt);
      return answer.trim() === "approve";
    } finally {
      rl.close();
    }
  }
}
