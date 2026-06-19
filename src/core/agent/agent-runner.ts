import type { DetDocConfig } from "../config.js";
import type { RunMode } from "../manifest.js";
import type { ProposedPlan } from "../plan.js";

export interface PlanRequest {
  mode: RunMode;
  input: string;
  config: DetDocConfig;
  cwd: string;
}

export interface AgentImplementationProgressEvent {
  action: "edit" | "write";
  path: string;
}

export type AgentImplementationProgressReporter = (event: AgentImplementationProgressEvent) => void;

export interface ImplementRequest {
  mode: RunMode;
  input: string;
  config: DetDocConfig;
  cwd: string;
  approvedPlan: ProposedPlan;
  approvedTargets: string[];
  progress?: AgentImplementationProgressReporter;
}

export interface AgentRunner {
  plan(request: PlanRequest): Promise<ProposedPlan>;
  implement(request: ImplementRequest): Promise<void>;
}
