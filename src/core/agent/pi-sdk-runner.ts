import { isAbsolute, relative, resolve } from "node:path";
import {
  AuthStorage,
  createAgentSession,
  DefaultResourceLoader,
  defineTool,
  getAgentDir,
  ModelRegistry,
  SessionManager,
  SettingsManager,
  type ExtensionFactory,
} from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import type { AgentRunner, ImplementRequest, PlanRequest, RepairValidationRequest } from "./agent-runner.js";
import type { DetDocConfig } from "../config.js";
import { isDeniedPath, isDocPath } from "../paths.js";
import { PlanSchema, type ProposedPlan, validateProposedPlan } from "../plan.js";

function extractLastAssistantText(messages: Array<{ role?: string; content?: unknown }>): string {
  for (const message of [...messages].reverse()) {
    if (message.role !== "assistant") continue;
    if (typeof message.content === "string") return message.content;
    if (Array.isArray(message.content)) {
      return message.content
        .map((part) => {
          if (typeof part === "object" && part && "text" in part) {
            return String((part as { text: unknown }).text);
          }
          return "";
        })
        .join("");
    }
  }
  return "";
}

export function buildPlanningPrompt(request: PlanRequest): string {
  const reasonRule =
    request.mode === "run"
      ? [
          "Every changes[].reason MUST start with `doc-diff:`.",
          "Example: `doc-diff:docs/spec.md:L1-L20`.",
          "Use the changed Markdown file path and approximate changed line range from the diff.",
        ].join("\n")
      : [
          "Every changes[].reason MUST be `intent:fix`.",
          "Fix mode MUST NOT target documentation files.",
        ].join("\n");

  return [
    "You are DetDoc planning phase.",
    "Inspect the repository using read-only tools only.",
    "Do not modify files.",
    "When ready, call submit_plan exactly once.",
    "Do not answer with free-form text instead of submit_plan.",
    "Plan schema constraints:",
    "- summary: short string.",
    "- changes: non-empty array.",
    "- changes[].targetFiles: exact repository-relative paths that implementation may edit/create/delete.",
    "- changes[].kind: one of create, modify, delete, rename.",
    "- changes[].rationale: explain why the target follows from the input.",
    `- ${reasonRule}`,
    "Do not use free-form prose in changes[].reason; it must follow the exact prefix/value rule above.",
    "If the documentation names validation or generation commands that DetDoc should run after applying changes, inspect `.detdoc/config.yml`; if those commands are missing, include `.detdoc/config.yml` in targetFiles and update validation.commands. Prefer validation.commands entries shaped as `{ name, run }`.",
    "Do not target documentation files such as `docs/**`; documentation is read-only input for implementation.",
    "Denied paths from config must never be targeted:",
    JSON.stringify(request.config.paths.deny),
    `Mode: ${request.mode}`,
    "Input:",
    request.input,
  ].join("\n\n");
}

type AgentToolName = "read" | "grep" | "find" | "ls" | "edit" | "write" | string;

function isWriteTool(toolName: AgentToolName): toolName is "edit" | "write" {
  return toolName === "edit" || toolName === "write";
}

function toolInputPath(input: unknown): string | undefined {
  if (!input || typeof input !== "object") return undefined;
  const path = (input as { path?: unknown }).path;
  return typeof path === "string" && path.length > 0 ? path.replace(/^@/, "") : undefined;
}

function projectRelativePath(cwd: string, rawPath: string): { inside: boolean; path: string } {
  const absolute = isAbsolute(rawPath) ? resolve(rawPath) : resolve(cwd, rawPath);
  const relativePath = relative(cwd, absolute).replaceAll("\\", "/");
  const inside = relativePath === "" || (!relativePath.startsWith("../") && relativePath !== ".." && !isAbsolute(relativePath));
  return { inside, path: relativePath };
}

export function validateAgentToolPath(input: {
  cwd: string;
  toolName: AgentToolName;
  rawPath?: string;
  approvedTargets: string[];
  config: DetDocConfig;
}): { allowed: true; path?: string } | { allowed: false; reason: string; path?: string } {
  if (!input.rawPath) return { allowed: true };
  const normalized = projectRelativePath(input.cwd, input.rawPath);
  if (!normalized.inside) {
    return { allowed: false, reason: `DetDoc blocked path outside project root: ${input.rawPath}`, path: normalized.path };
  }
  if (isDeniedPath(normalized.path, input.config)) {
    return { allowed: false, reason: `DetDoc blocked denied path: ${normalized.path}`, path: normalized.path };
  }
  if (isWriteTool(input.toolName) && isDocPath(normalized.path, input.config)) {
    return { allowed: false, reason: `DetDoc blocked write to ${normalized.path}: documentation files are read-only`, path: normalized.path };
  }
  if (isWriteTool(input.toolName) && !input.approvedTargets.includes(normalized.path)) {
    return { allowed: false, reason: `DetDoc blocked unapproved path: ${normalized.path}`, path: normalized.path };
  }
  return { allowed: true, path: normalized.path };
}

function guardExtension(request: ImplementRequest): ExtensionFactory {
  return (pi) => {
    pi.on("tool_call", async (event) => {
      const rawPath = toolInputPath(event.input);
      const result = validateAgentToolPath({ cwd: request.cwd, toolName: event.toolName, rawPath, approvedTargets: request.approvedTargets, config: request.config });
      if (!result.allowed) return { block: true, reason: result.reason };
      if (isWriteTool(event.toolName) && result.path) request.progress?.({ action: event.toolName, path: result.path });
      return undefined;
    });
  };
}

export class PiSdkRunner implements AgentRunner {
  async plan(request: PlanRequest): Promise<ProposedPlan> {
    let capturedPlan: ProposedPlan | undefined;
    const submitPlan = defineTool({
      name: "submit_plan",
      label: "Submit Plan",
      description: "Submit the final DetDoc implementation plan as structured JSON.",
      parameters: Type.Object({
        summary: Type.String(),
        changes: Type.Array(
          Type.Object({
            reason: Type.String(),
            targetFiles: Type.Array(Type.String()),
            kind: Type.Union([Type.Literal("create"), Type.Literal("modify"), Type.Literal("delete"), Type.Literal("rename")]),
            rationale: Type.String(),
          }),
        ),
        questions: Type.Array(Type.String()),
        risk: Type.Union([Type.Literal("low"), Type.Literal("medium"), Type.Literal("high")]),
      }),
      async execute(_toolCallId, params) {
        capturedPlan = PlanSchema.parse(params);
        return {
          content: [{ type: "text", text: "DetDoc plan captured." }],
          details: { plan: capturedPlan },
          terminate: true,
        };
      },
    });

    const loader = new DefaultResourceLoader({ cwd: request.cwd, agentDir: getAgentDir() });
    await loader.reload();
    const authStorage = AuthStorage.create();
    const modelRegistry = ModelRegistry.create(authStorage);
    const settingsManager = SettingsManager.inMemory({ compaction: { enabled: false } });
    const { session } = await createAgentSession({
      cwd: request.cwd,
      authStorage,
      modelRegistry,
      settingsManager,
      resourceLoader: loader,
      sessionManager: SessionManager.inMemory(request.cwd),
      tools: ["read", "grep", "find", "ls", "submit_plan"],
      customTools: [submitPlan],
      thinkingLevel: request.config.agent.thinking,
    });

    try {
      await session.prompt(buildPlanningPrompt(request));
      if (capturedPlan) return validateProposedPlan(capturedPlan, { config: request.config, mode: request.mode });

      const text = extractLastAssistantText(session.messages as Array<{ role?: string; content?: unknown }>);
      return validateProposedPlan(JSON.parse(text), { config: request.config, mode: request.mode });
    } finally {
      session.dispose();
    }
  }

  private async runImplementationPrompt(request: ImplementRequest, prompt: string): Promise<void> {
    const loader = new DefaultResourceLoader({
      cwd: request.cwd,
      agentDir: getAgentDir(),
      extensionFactories: [guardExtension(request)],
    });
    await loader.reload();
    const authStorage = AuthStorage.create();
    const modelRegistry = ModelRegistry.create(authStorage);
    const settingsManager = SettingsManager.inMemory({ compaction: { enabled: false } });
    const { session } = await createAgentSession({
      cwd: request.cwd,
      authStorage,
      modelRegistry,
      settingsManager,
      resourceLoader: loader,
      sessionManager: SessionManager.inMemory(request.cwd),
      tools: ["read", "grep", "find", "ls", "edit", "write"],
      thinkingLevel: request.config.agent.thinking,
    });

    try {
      await session.prompt(prompt);
    } finally {
      session.dispose();
    }
  }

  async implement(request: ImplementRequest): Promise<void> {
    const prompt = [
      "You are DetDoc implementation phase.",
      "Implement only the approved plan.",
      "Use edit/write only for approved target paths.",
      "Documentation files are read-only; never edit files under docs/.",
      "If another file is required, stop and explain instead of editing it.",
      `Mode: ${request.mode}`,
      "Approved plan:",
      JSON.stringify(request.approvedPlan, null, 2),
      "Original input:",
      request.input,
    ].join("\n\n");
    await this.runImplementationPrompt(request, prompt);
  }

  async repairValidation(request: RepairValidationRequest): Promise<void> {
    const prompt = [
      "You are DetDoc validation repair phase.",
      `Validation failed on attempt ${request.attempt}.`,
      "Fix the failure by editing only approved target paths.",
      "Do not edit documentation files under docs/.",
      "Do not broaden scope or add unapproved files.",
      `Mode: ${request.mode}`,
      "Approved plan:",
      JSON.stringify(request.approvedPlan, null, 2),
      "Validation log:",
      request.validationLog,
      "Original input:",
      request.input,
    ].join("\n\n");
    await this.runImplementationPrompt(request, prompt);
  }
}

export function createDefaultAgentRunner(): AgentRunner {
  return new PiSdkRunner();
}
