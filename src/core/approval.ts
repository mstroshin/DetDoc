import { createInterface } from "node:readline/promises";
import boxen from "boxen";
import pc from "picocolors";
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

function formatPlan(plan: ProposedPlan): string {
  const summaryBox = boxen([`Summary: ${plan.summary}`, `Risk: ${plan.risk}`, `Changes: ${plan.changes.length}`].join("\n"), {
    title: pc.bold("DetDoc proposed plan"),
    titleAlignment: "center",
    padding: 1,
    borderStyle: "round",
    borderColor: "cyan",
  });

  const lines: string[] = [summaryBox, ""];

  if (plan.questions.length > 0) {
    lines.push(pc.bold("Questions"));
    for (const question of plan.questions) lines.push(`- ${question}`);
    lines.push("");
  }

  lines.push(pc.bold("Changes"));
  plan.changes.forEach((change, index) => {
    lines.push(`${index + 1}. ${change.kind}`);
    lines.push(`   Reason: ${change.reason}`);
    lines.push("   Target files:");
    for (const file of change.targetFiles) lines.push(`   - ${file}`);
    lines.push(`   Rationale: ${change.rationale}`);
    lines.push("");
  });

  return lines.join("\n");
}

export class TerminalApprovalUI implements ApprovalUI {
  constructor(private readonly io: CliIO) {}

  async approvePlan(plan: ProposedPlan): Promise<boolean> {
    writeLine(this.io.stdout, formatPlan(plan));
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
