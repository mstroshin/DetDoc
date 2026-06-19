import type { DetDocConfig } from "../config.js";
import type { RunMode } from "../manifest.js";
import type { ProposedPlan } from "../plan.js";

export interface PlanRequest {
  mode: RunMode;
  input: string;
  config: DetDocConfig;
  cwd: string;
}

export type AgentImplementationProgressEvent =
  | {
      action: "edit" | "write";
      path: string;
    }
  | {
      action: "bash";
      command: string;
    };

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

export interface RepairValidationRequest extends ImplementRequest {
  validationLog: string;
  attempt: number;
}

export interface AgentRunner {
  plan(request: PlanRequest): Promise<ProposedPlan>;
  implement(request: ImplementRequest): Promise<void>;
  repairValidation?(request: RepairValidationRequest): Promise<void>;
}
