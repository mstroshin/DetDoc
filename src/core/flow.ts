import YAML from "yaml";
import type { AgentRunner } from "./agent/agent-runner.js";
import type { ApprovalUI } from "./approval.js";
import { ArtifactStore } from "./artifacts.js";
import { loadConfig } from "./config.js";
import { getNormalizedDocDiff } from "./diff.js";
import { DetDocError } from "./errors.js";
import { GitRepository } from "./git.js";
import { createInitialManifest, type RunManifest } from "./manifest.js";
import { assertFixDirtyPolicy } from "./paths.js";
import { approvedTargetsFromPlan, validateProposedPlan } from "./plan.js";
import { runValidationCommands, validatePatch } from "./validation.js";
import { WorktreeManager } from "./worktree.js";

export interface FlowResult {
  runId: string;
  applied: boolean;
  patch: string;
}

async function updateManifest(store: ArtifactStore, manifest: RunManifest): Promise<void> {
  await store.writeJson(manifest.runId, "manifest.json", manifest);
}

async function applyPatchToMain(repo: GitRepository, patch: string): Promise<void> {
  await repo.applyPatch(patch);
}

async function collectPatchForTargets(repo: GitRepository, approvedTargets: string[]): Promise<string> {
  if (approvedTargets.length === 0) {
    throw new DetDocError("Approved plan contains no target files.", "NO_APPROVED_TARGETS");
  }
  const patch = await repo.git(["diff", "--no-color", "--no-ext-diff", "--binary", "--", ...approvedTargets]);
  if (patch.trim().length === 0) {
    throw new DetDocError("Agent produced no code changes for approved target files.", "EMPTY_PATCH");
  }
  return patch.endsWith("\n") ? patch : `${patch}\n`;
}

export async function createPlanFlow(input: {
  cwd: string;
  agent: AgentRunner;
  mode?: "run" | "fix";
  message?: string;
}): Promise<{ runId: string }> {
  const cwd = input.cwd;
  const config = await loadConfig(cwd);
  const repo = new GitRepository(cwd);
  const mode = input.mode ?? "run";
  const taskInput = mode === "run" ? await getNormalizedDocDiff(repo, config) : input.message ?? "";
  if (mode === "fix") await assertFixDirtyPolicy(repo, config);
  if (mode === "fix" && taskInput.trim().length === 0) {
    throw new DetDocError("detdoc fix requires a non-empty message.", "EMPTY_FIX_MESSAGE");
  }

  const manifest = await createInitialManifest({ mode, repo, config, input: taskInput });
  const store = new ArtifactStore(cwd);
  await store.createRun(manifest);
  await store.writeText(manifest.runId, mode === "run" ? "input.diff.md" : "intent.md", taskInput);
  await store.writeText(manifest.runId, "config.snapshot.yml", YAML.stringify(config));

  const plan = validateProposedPlan(await input.agent.plan({ mode, input: taskInput, config, cwd }), { config, mode });
  await store.writeJson(manifest.runId, "plan.proposed.json", plan);
  return { runId: manifest.runId };
}

async function runFlow(input: {
  cwd: string;
  mode: "run" | "fix";
  message?: string;
  agent: AgentRunner;
  approval: ApprovalUI;
}): Promise<FlowResult> {
  const cwd = input.cwd;
  const config = await loadConfig(cwd);
  const mainRepo = new GitRepository(cwd);
  const taskInput = input.mode === "run" ? await getNormalizedDocDiff(mainRepo, config) : input.message ?? "";
  if (input.mode === "fix") await assertFixDirtyPolicy(mainRepo, config);
  if (input.mode === "fix" && taskInput.trim().length === 0) {
    throw new DetDocError("detdoc fix requires a non-empty message.", "EMPTY_FIX_MESSAGE");
  }

  const manifest = await createInitialManifest({ mode: input.mode, repo: mainRepo, config, input: taskInput });
  const store = new ArtifactStore(cwd);
  await store.createRun(manifest);
  await store.writeText(manifest.runId, input.mode === "run" ? "input.diff.md" : "intent.md", taskInput);
  await store.writeText(manifest.runId, "config.snapshot.yml", YAML.stringify(config));
  await store.writeText(manifest.runId, "run.log", `mode=${input.mode}\n`);

  const worktree = await new WorktreeManager().createFromHead(mainRepo);
  let keepWorktree = config.worktree.keepOnFailure;
  try {
    if (input.mode === "run") await worktree.repo.applyPatch(taskInput);

    const proposedPlan = validateProposedPlan(
      await input.agent.plan({ mode: input.mode, input: taskInput, config, cwd: worktree.path }),
      { config, mode: input.mode },
    );
    await store.writeJson(manifest.runId, "plan.proposed.json", proposedPlan);

    if (!(await input.approval.approvePlan(proposedPlan))) {
      throw new DetDocError("Plan was not approved.", "PLAN_NOT_APPROVED");
    }

    await store.writeJson(manifest.runId, "plan.approved.json", proposedPlan);
    const approvedTargets = approvedTargetsFromPlan(proposedPlan);
    manifest.approvedTargets = approvedTargets;
    await updateManifest(store, manifest);

    await input.agent.implement({
      mode: input.mode,
      input: taskInput,
      config,
      cwd: worktree.path,
      approvedPlan: proposedPlan,
      approvedTargets,
    });

    const patch = await collectPatchForTargets(worktree.repo, approvedTargets);
    const validation = await validatePatch({ patch, repo: worktree.repo, config, mode: input.mode, approvedTargets });
    const validationLog = await runValidationCommands({ cwd: worktree.path, config });

    manifest.touchedFiles = await Promise.all(
      validation.changedFiles.map(async (path) => ({
        path,
        before: await mainRepo.fileSha256(path),
        after: await worktree.repo.fileSha256(path),
      })),
    );
    await store.writeText(manifest.runId, "changes.patch", patch);
    await store.writeText(manifest.runId, "validation.log", validationLog);
    await updateManifest(store, manifest);

    if (!(await input.approval.approvePatch(patch))) {
      return { runId: manifest.runId, applied: false, patch };
    }

    await applyPatchToMain(mainRepo, patch);
    keepWorktree = false;
    return { runId: manifest.runId, applied: true, patch };
  } finally {
    if (!keepWorktree) await worktree.cleanup();
  }
}

export async function runDocFlow(input: { cwd: string; agent: AgentRunner; approval: ApprovalUI }): Promise<FlowResult> {
  return runFlow({ ...input, mode: "run" });
}

export async function runFixFlow(input: { cwd: string; message: string; agent: AgentRunner; approval: ApprovalUI }): Promise<FlowResult> {
  return runFlow({ ...input, mode: "fix" });
}
