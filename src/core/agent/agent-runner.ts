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

export interface TokenUsage {
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
  total: number;
}

export interface AgentPlanResult {
  plan: ProposedPlan;
  usage: TokenUsage;
}

export interface AgentRunResult {
  usage: TokenUsage;
}

export function zeroTokenUsage(): TokenUsage {
  return { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 };
}

export function addTokenUsage(left: TokenUsage, right: TokenUsage): TokenUsage {
  return {
    input: left.input + right.input,
    output: left.output + right.output,
    cacheRead: left.cacheRead + right.cacheRead,
    cacheWrite: left.cacheWrite + right.cacheWrite,
    total: left.total + right.total,
  };
}

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
  plan(request: PlanRequest): Promise<AgentPlanResult>;
  implement(request: ImplementRequest): Promise<AgentRunResult>;
  repairValidation?(request: RepairValidationRequest): Promise<AgentRunResult>;
}
