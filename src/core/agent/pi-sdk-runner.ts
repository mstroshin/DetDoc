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
import type { AgentRunner, ImplementRequest, PlanRequest } from "./agent-runner.js";
import { isDeniedPath } from "../paths.js";
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
    "Denied paths from config must never be targeted:",
    JSON.stringify(request.config.paths.deny),
    `Mode: ${request.mode}`,
    "Input:",
    request.input,
  ].join("\n\n");
}

function guardExtension(request: ImplementRequest): ExtensionFactory {
  const allowed = new Set(request.approvedTargets);
  return (pi) => {
    pi.on("tool_call", async (event) => {
      if (event.toolName !== "edit" && event.toolName !== "write") return undefined;
      const input = event.input as { path?: unknown };
      const rawPath = typeof input.path === "string" ? input.path.replace(/^@/, "") : "";
      if (isDeniedPath(rawPath, request.config)) {
        return { block: true, reason: `DetDoc blocked denied path: ${rawPath}` };
      }
      if (!allowed.has(rawPath)) {
        return { block: true, reason: `DetDoc blocked unapproved path: ${rawPath}` };
      }
      request.progress?.({ action: event.toolName, path: rawPath });
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

  async implement(request: ImplementRequest): Promise<void> {
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
      const prompt = [
        "You are DetDoc implementation phase.",
        "Implement only the approved plan.",
        "Use edit/write only for approved target paths.",
        "If another file is required, stop and explain instead of editing it.",
        `Mode: ${request.mode}`,
        "Approved plan:",
        JSON.stringify(request.approvedPlan, null, 2),
        "Original input:",
        request.input,
      ].join("\n\n");
      await session.prompt(prompt);
    } finally {
      session.dispose();
    }
  }
}

export function createDefaultAgentRunner(): AgentRunner {
  return new PiSdkRunner();
}
