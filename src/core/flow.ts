import YAML from "yaml";
import { addTokenUsage, zeroTokenUsage, type AgentImplementationProgressEvent, type AgentRunner, type TokenUsage } from "./agent/agent-runner.js";
import type { ApplyApprovalContext, ApprovalUI } from "./approval.js";
import { ArtifactStore } from "./artifacts.js";
import { ensureManagedGitignoreEntries, loadConfig } from "./config.js";
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
  tokenUsage: FlowTokenUsage;
}

export interface FlowTokenUsage {
  plan: TokenUsage;
  implement: TokenUsage;
  repairValidation: TokenUsage;
  total: TokenUsage;
}

function zeroFlowTokenUsage(): FlowTokenUsage {
  return {
    plan: zeroTokenUsage(),
    implement: zeroTokenUsage(),
    repairValidation: zeroTokenUsage(),
    total: zeroTokenUsage(),
  };
}

export type FlowProgressPhase =
  | "load_config"
  | "collect_input"
  | "create_run"
  | "create_worktree"
  | "apply_input_to_worktree"
  | "plan"
  | "approve_plan"
  | "implement"
  | "collect_patch"
  | "validate_patch"
  | "repair_validation"
  | "approve_apply"
  | "merge_worktree"
  | "apply_patch"
  | "post_apply_validation"
  | "cleanup_run"
  | "commit"
  | "cleanup_worktree"
  | "done";

export interface FlowProgressEvent {
  phase: FlowProgressPhase;
  message: string;
  runId?: string;
}

export type FlowProgressReporter = (event: FlowProgressEvent) => void;

function progress(input: { progress?: FlowProgressReporter }, event: FlowProgressEvent): void {
  input.progress?.(event);
}

function shortenCommand(command: string): string {
  const singleLine = command.replace(/\s+/g, " ").trim();
  return singleLine.length > 120 ? `${singleLine.slice(0, 117)}...` : singleLine;
}

function agentActionMessage(event: AgentImplementationProgressEvent): string {
  if (event.action === "bash") return `Agent is running ${shortenCommand(event.command)}`;
  return `Agent is ${event.action === "write" ? "writing" : "editing"} ${event.path}`;
}

const maxValidationRepairAttempts = 2;

async function updateManifest(store: ArtifactStore, manifest: RunManifest): Promise<void> {
  await store.writeJson(manifest.runId, "manifest.json", manifest);
}

async function runPostApplyValidation(input: { cwd: string; progress?: FlowProgressReporter }, store: ArtifactStore, runId: string): Promise<void> {
  const appliedConfig = await loadConfig(input.cwd);
  if (appliedConfig.validation.commands.length === 0) return;
  progress(input, { phase: "post_apply_validation", message: "Running validation commands in main worktree", runId });
  const validationLog = await runValidationCommands({ cwd: input.cwd, config: appliedConfig });
  await store.writeText(runId, "post-apply-validation.log", validationLog);
}

async function approveApply(input: { approval: ApprovalUI; progress?: FlowProgressReporter }, context: ApplyApprovalContext): Promise<boolean> {
  progress(input, { phase: "approve_apply", message: "Waiting for apply approval", runId: context.runId });
  return input.approval.approveApply ? input.approval.approveApply(context) : true;
}

async function mergeValidatedWorktreePatch(input: { progress?: FlowProgressReporter }, repo: GitRepository, patch: string, runId: string): Promise<void> {
  progress(input, { phase: "merge_worktree", message: "Merging validated worktree changes into main", runId });
  await repo.applyPatch(patch);
}

async function applyPatchToMain(repo: GitRepository, patch: string): Promise<void> {
  await repo.applyPatch(patch);
}

async function deleteRunArtifacts(input: { progress?: FlowProgressReporter }, store: ArtifactStore, runId: string): Promise<void> {
  progress(input, { phase: "cleanup_run", message: "Removing run artifacts", runId });
  await store.deleteRun(runId);
}

async function commitAppliedChanges(input: { progress?: FlowProgressReporter }, repo: GitRepository, runId: string): Promise<void> {
  progress(input, { phase: "commit", message: "Committing applied changes", runId });
  await ensureManagedGitignoreEntries(repo.cwd);
  await repo.git(["add", "-A", "--", "."]);
  await repo.git(["commit", "-m", `DetDoc apply ${runId}`]);
  const dirty = await repo.statusPorcelain();
  if (dirty.length > 0) {
    throw new DetDocError(
      `Git working tree is not clean after DetDoc apply: ${dirty.map((file) => `${file.status} ${file.path}`).join(", ")}`,
      "GIT_NOT_CLEAN_AFTER_APPLY",
    );
  }
}

async function collectPatchForTargets(repo: GitRepository, approvedTargets: string[]): Promise<string> {
  if (approvedTargets.length === 0) {
    throw new DetDocError("Approved plan contains no target files.", "NO_APPROVED_TARGETS");
  }
  await repo.git(["add", "-N", "--", ...approvedTargets]).catch(() => undefined);
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

  const planResult = await input.agent.plan({ mode, input: taskInput, config, cwd });
  const plan = validateProposedPlan(planResult.plan, { config, mode });
  await store.writeJson(manifest.runId, "plan.proposed.json", plan);
  return { runId: manifest.runId };
}

async function runFlow(input: {
  cwd: string;
  mode: "run" | "fix";
  message?: string;
  agent: AgentRunner;
  approval: ApprovalUI;
  progress?: FlowProgressReporter;
}): Promise<FlowResult> {
  const cwd = input.cwd;
  const tokenUsage = zeroFlowTokenUsage();
  const recordUsage = (phase: keyof Omit<FlowTokenUsage, "total">, usage: TokenUsage): void => {
    tokenUsage[phase] = addTokenUsage(tokenUsage[phase], usage);
    tokenUsage.total = addTokenUsage(tokenUsage.total, usage);
  };
  progress(input, { phase: "load_config", message: "Loading DetDoc config" });
  const config = await loadConfig(cwd);
  const mainRepo = new GitRepository(cwd);
  progress(input, { phase: "collect_input", message: input.mode === "run" ? "Collecting documentation changes" : "Collecting fix intent" });
  const taskInput = input.mode === "run" ? await getNormalizedDocDiff(mainRepo, config) : input.message ?? "";
  if (input.mode === "fix") await assertFixDirtyPolicy(mainRepo, config);
  if (input.mode === "fix" && taskInput.trim().length === 0) {
    throw new DetDocError("detdoc fix requires a non-empty message.", "EMPTY_FIX_MESSAGE");
  }

  progress(input, { phase: "create_run", message: "Creating run artifacts" });
  const manifest = await createInitialManifest({ mode: input.mode, repo: mainRepo, config, input: taskInput });
  const store = new ArtifactStore(cwd);
  await store.createRun(manifest);
  await store.writeText(manifest.runId, input.mode === "run" ? "input.diff.md" : "intent.md", taskInput);
  await store.writeText(manifest.runId, "config.snapshot.yml", YAML.stringify(config));
  await store.writeText(manifest.runId, "run.log", `mode=${input.mode}\n`);

  progress(input, { phase: "create_worktree", message: "Creating isolated worktree", runId: manifest.runId });
  const worktree = await new WorktreeManager().createFromHead(mainRepo);
  let keepWorktree = config.worktree.keepOnFailure;
  let completed = false;
  try {
    if (input.mode === "run") {
      progress(input, { phase: "apply_input_to_worktree", message: "Applying documentation changes to worktree", runId: manifest.runId });
      await worktree.repo.applyPatch(taskInput);
    }

    progress(input, { phase: "plan", message: "Agent is planning code changes", runId: manifest.runId });
    const planResult = await input.agent.plan({ mode: input.mode, input: taskInput, config, cwd: worktree.path });
    recordUsage("plan", planResult.usage);
    const proposedPlan = validateProposedPlan(planResult.plan, { config, mode: input.mode });
    await store.writeJson(manifest.runId, "plan.proposed.json", proposedPlan);

    progress(input, { phase: "approve_plan", message: "Waiting for plan approval", runId: manifest.runId });
    if (!(await input.approval.approvePlan(proposedPlan))) {
      throw new DetDocError("Plan was not approved.", "PLAN_NOT_APPROVED");
    }

    await store.writeJson(manifest.runId, "plan.approved.json", proposedPlan);
    const approvedTargets = approvedTargetsFromPlan(proposedPlan);
    manifest.approvedTargets = approvedTargets;
    await updateManifest(store, manifest);

    progress(input, { phase: "implement", message: "Agent is editing approved files", runId: manifest.runId });
    const implementResult = await input.agent.implement({
      mode: input.mode,
      input: taskInput,
      config,
      cwd: worktree.path,
      approvedPlan: proposedPlan,
      approvedTargets,
      progress: (event) => progress(input, { phase: "implement", message: agentActionMessage(event), runId: manifest.runId }),
    });
    recordUsage("implement", implementResult.usage);

    let patch = "";
    let validation: Awaited<ReturnType<typeof validatePatch>> | undefined;
    let validationLog = "";
    for (let repairAttempt = 0; ; repairAttempt++) {
      progress(input, { phase: "collect_patch", message: "Collecting generated patch", runId: manifest.runId });
      patch = await collectPatchForTargets(worktree.repo, approvedTargets);
      progress(input, { phase: "validate_patch", message: "Validating generated patch", runId: manifest.runId });
      validation = await validatePatch({ patch, repo: worktree.repo, config, mode: input.mode, approvedTargets });
      const worktreeConfig = await loadConfig(worktree.path);
      try {
        validationLog = await runValidationCommands({ cwd: worktree.path, config: worktreeConfig });
        break;
      } catch (error) {
        const repairValidation = input.agent.repairValidation;
        const canRepair = error instanceof DetDocError && error.code === "VALIDATION_FAILED" && repairValidation && repairAttempt < maxValidationRepairAttempts;
        if (!canRepair) throw error;
        const attempt = repairAttempt + 1;
        const validationFailureLog = error.message;
        await store.writeText(manifest.runId, `validation-failure-${attempt}.log`, validationFailureLog);
        progress(input, { phase: "repair_validation", message: `Agent is fixing validation failure (${attempt}/${maxValidationRepairAttempts})`, runId: manifest.runId });
        const repairResult = await repairValidation.call(input.agent, {
          mode: input.mode,
          input: taskInput,
          config: worktreeConfig,
          cwd: worktree.path,
          approvedPlan: proposedPlan,
          approvedTargets,
          validationLog: validationFailureLog,
          attempt,
          progress: (event) => progress(input, { phase: "repair_validation", message: agentActionMessage(event), runId: manifest.runId }),
        });
        recordUsage("repairValidation", repairResult.usage);
      }
    }

    if (!validation) throw new DetDocError("Validation did not produce a result.", "VALIDATION_INTERNAL_ERROR");
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

    if (!(await approveApply(input, { runId: manifest.runId, changedFiles: validation.changedFiles }))) {
      keepWorktree = false;
      completed = true;
      return { runId: manifest.runId, applied: false, patch, tokenUsage };
    }

    await mergeValidatedWorktreePatch(input, mainRepo, patch, manifest.runId);
    keepWorktree = false;
    await runPostApplyValidation(input, store, manifest.runId);
    await deleteRunArtifacts(input, store, manifest.runId);
    await commitAppliedChanges(input, mainRepo, manifest.runId);
    completed = true;
    return { runId: manifest.runId, applied: true, patch, tokenUsage };
  } finally {
    if (!keepWorktree) {
      progress(input, { phase: "cleanup_worktree", message: "Cleaning up isolated worktree", runId: manifest.runId });
      await worktree.cleanup();
    }
    if (completed) progress(input, { phase: "done", message: "Run complete", runId: manifest.runId });
  }
}

export async function runDocFlow(input: { cwd: string; agent: AgentRunner; approval: ApprovalUI; progress?: FlowProgressReporter }): Promise<FlowResult> {
  return runFlow({ ...input, mode: "run" });
}

export async function runFixFlow(input: { cwd: string; message: string; agent: AgentRunner; approval: ApprovalUI; progress?: FlowProgressReporter }): Promise<FlowResult> {
  return runFlow({ ...input, mode: "fix" });
}

export async function applyRun(input: { cwd: string; runId: string; progress?: FlowProgressReporter }): Promise<FlowResult> {
  const repo = new GitRepository(input.cwd);
  const store = new ArtifactStore(input.cwd);
  const manifest = await store.readJson<RunManifest>(input.runId, "manifest.json");
  const patch = await store.readText(input.runId, "changes.patch");

  const head = await repo.headCommit();
  if (head !== manifest.baseCommit) {
    throw new DetDocError(`Cannot apply ${input.runId}: current HEAD ${head} does not match base ${manifest.baseCommit}.`, "APPLY_BASE_MISMATCH");
  }

  for (const file of manifest.touchedFiles) {
    const current = await repo.fileSha256(file.path);
    if (current !== file.before) {
      throw new DetDocError(`Cannot apply ${input.runId}: preimage hash mismatch for ${file.path}.`, "APPLY_PREIMAGE_MISMATCH");
    }
  }

  progress(input, { phase: "apply_patch", message: "Applying saved patch", runId: input.runId });
  await repo.applyPatch(patch);
  await runPostApplyValidation(input, store, input.runId);
  await deleteRunArtifacts(input, store, input.runId);
  await commitAppliedChanges(input, repo, input.runId);
  progress(input, { phase: "done", message: "Apply complete", runId: input.runId });
  return { runId: input.runId, applied: true, patch, tokenUsage: zeroFlowTokenUsage() };
}

export async function replayRun(input: { cwd: string; runId: string }): Promise<FlowResult> {
  const repo = new GitRepository(input.cwd);
  const store = new ArtifactStore(input.cwd);
  const manifest = await store.readJson<RunManifest>(input.runId, "manifest.json");
  const patch = await store.readText(input.runId, "changes.patch");
  const config = await loadConfig(input.cwd);

  const head = await repo.headCommit();
  if (head !== manifest.baseCommit) {
    throw new DetDocError(`Cannot replay ${input.runId}: current HEAD ${head} does not match base ${manifest.baseCommit}.`, "REPLAY_BASE_MISMATCH");
  }

  for (const file of manifest.touchedFiles) {
    const current = await repo.fileSha256(file.path);
    if (current !== file.before) {
      throw new DetDocError(`Cannot replay ${input.runId}: preimage hash mismatch for ${file.path}.`, "REPLAY_PREIMAGE_MISMATCH");
    }
  }

  await repo.applyPatch(patch);
  const validationLog = await runValidationCommands({ cwd: input.cwd, config });
  await store.writeText(input.runId, "replay.log", validationLog);
  return { runId: input.runId, applied: true, patch, tokenUsage: zeroFlowTokenUsage() };
}
