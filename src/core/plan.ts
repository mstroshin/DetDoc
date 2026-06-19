import { z } from "zod";
import type { DetDocConfig } from "./config.js";
import type { RunMode } from "./manifest.js";
import { isDeniedPath, isDocPath } from "./paths.js";

export const PlanChangeSchema = z.object({
  reason: z.string().min(1),
  targetFiles: z.array(z.string().min(1)).min(1),
  kind: z.enum(["create", "modify", "delete", "rename"]),
  rationale: z.string().min(1),
});

export const PlanSchema = z.object({
  summary: z.string().min(1),
  changes: z.array(PlanChangeSchema).min(1),
  questions: z.array(z.string()).default([]),
  risk: z.enum(["low", "medium", "high"]),
});

export type ProposedPlan = z.infer<typeof PlanSchema>;

export function validateProposedPlan(
  value: unknown,
  options: { config: DetDocConfig; mode: RunMode },
): ProposedPlan {
  const plan = PlanSchema.parse(value);

  for (const change of plan.changes) {
    if (options.mode === "run" && !change.reason.startsWith("doc-diff:")) {
      throw new Error(`run plan change must use doc-diff reason: ${change.reason}`);
    }
    if (options.mode === "fix" && !change.reason.startsWith("intent:")) {
      throw new Error(`fix plan change must use intent reason: ${change.reason}`);
    }
    for (const target of change.targetFiles) {
      if (isDeniedPath(target, options.config)) {
        throw new Error(`plan targets denied path: ${target}`);
      }
      if (options.mode === "fix" && isDocPath(target, options.config)) {
        throw new Error(`fix plans must not target documentation files: ${target}`);
      }
    }
  }

  return plan;
}

export function approvedTargetsFromPlan(plan: ProposedPlan): string[] {
  return [...new Set(plan.changes.flatMap((change) => change.targetFiles))].sort();
}
