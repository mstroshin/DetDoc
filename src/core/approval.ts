import { createInterface } from "node:readline/promises";
import boxen from "boxen";
import pc from "picocolors";
import type { CliIO } from "../cli/output.js";
import { writeLine } from "../cli/output.js";
import type { ProposedPlan } from "./plan.js";

export interface ApplyApprovalContext {
  runId: string;
  changedFiles: string[];
}

export interface ApprovalUI {
  approvePlan(plan: ProposedPlan): Promise<boolean>;
  approveApply?(context: ApplyApprovalContext): Promise<boolean>;
}

export class AutoApprovalUI implements ApprovalUI {
  constructor(
    private readonly approved = true,
    private readonly applyApproved = approved,
  ) {}

  async approvePlan(_plan: ProposedPlan): Promise<boolean> {
    return this.approved;
  }

  async approveApply(_context: ApplyApprovalContext): Promise<boolean> {
    return this.applyApproved;
  }
}

function riskColor(risk: ProposedPlan["risk"], colors: ReturnType<typeof pc.createColors>): string {
  if (risk === "low") return colors.green(risk);
  if (risk === "medium") return colors.yellow(risk);
  return colors.red(risk);
}

function kindColor(kind: ProposedPlan["changes"][number]["kind"], colors: ReturnType<typeof pc.createColors>): string {
  if (kind === "create") return colors.green(kind);
  if (kind === "delete") return colors.red(kind);
  return colors.cyan(kind);
}

function formatPlan(plan: ProposedPlan, colors = pc.createColors()): string {
  const summaryBox = boxen(
    [
      `${colors.bold("Summary:")} ${plan.summary}`,
      `${colors.bold("Risk:")} ${riskColor(plan.risk, colors)}`,
      `${colors.bold("Changes:")} ${colors.cyan(plan.changes.length)}`,
    ].join("\n"),
    {
      title: colors.bold(colors.cyan("DetDoc proposed plan")),
      titleAlignment: "center",
      padding: 1,
      borderStyle: "round",
      borderColor: "cyan",
    },
  );

  const lines: string[] = [summaryBox, ""];

  if (plan.questions.length > 0) {
    lines.push(colors.bold(colors.yellow("Questions")));
    for (const question of plan.questions) lines.push(`${colors.yellow("?")} ${question}`);
    lines.push("");
  }

  lines.push(colors.bold(colors.cyan("Changes")));
  plan.changes.forEach((change, index) => {
    lines.push(`${colors.bold(`${index + 1}.`)} ${kindColor(change.kind, colors)}`);
    lines.push(`   ${colors.dim("Reason:")} ${colors.gray(change.reason)}`);
    lines.push(`   ${colors.dim("Target files:")}`);
    for (const file of change.targetFiles) lines.push(`   ${colors.cyan("-")} ${colors.cyan(file)}`);
    lines.push(`   ${colors.dim("Rationale:")} ${change.rationale}`);
    lines.push("");
  });

  return lines.join("\n");
}

export class TerminalApprovalUI implements ApprovalUI {
  constructor(private readonly io: CliIO) {}

  async approvePlan(plan: ProposedPlan): Promise<boolean> {
    writeLine(this.io.stdout, formatPlan(plan, pc.createColors(this.io.isInteractive || process.env.FORCE_COLOR !== undefined)));
    return this.confirm("Approve this plan? [y/N]: ");
  }

  async approveApply(context: ApplyApprovalContext): Promise<boolean> {
    const colors = pc.createColors(this.io.isInteractive || process.env.FORCE_COLOR !== undefined);
    writeLine(
      this.io.stdout,
      boxen(
        [
          `${colors.bold("Run:")} ${context.runId}`,
          `${colors.bold("Validated changed files:")} ${colors.cyan(context.changedFiles.length)}`,
          ...context.changedFiles.map((file) => `${colors.cyan("-")} ${colors.cyan(file)}`),
        ].join("\n"),
        {
          title: colors.bold(colors.cyan("DetDoc validated changes")),
          titleAlignment: "center",
          padding: 1,
          borderStyle: "round",
          borderColor: "cyan",
        },
      ),
    );
    return this.confirm("Apply validated changes? [y/N]: ");
  }

  private async confirm(prompt: string): Promise<boolean> {
    if (!this.io.isInteractive) return false;
    const rl = createInterface({ input: this.io.stdin, output: this.io.stdout });
    try {
      const answer = await rl.question(prompt);
      return ["y", "yes"].includes(answer.trim().toLowerCase());
    } finally {
      rl.close();
    }
  }
}
