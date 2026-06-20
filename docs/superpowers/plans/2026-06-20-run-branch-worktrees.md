# Run Branch Worktrees Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make DetDoc run/fix implementation worktrees visible under `.worktrees/<run-id>` on a branch named `<run-id>` so users can inspect generated diffs before the final apply decision.

**Architecture:** Keep the existing patch-based safety model. Extend the worktree lifecycle to support caller-provided branch names and paths, then pass the run id from `runFlow`. Surface the inspect path in the apply prompt and document the workflow.

**Tech Stack:** TypeScript, Node.js `fs/promises` and `path`, Git CLI, Vitest.

## Global Constraints

- Worktree branch name must be exactly the DetDoc run id.
- Worktree path must be `.worktrees/<run-id>` relative to the main repository.
- Main still receives only the validated patch; do not merge the branch.
- On normal completion after final apply prompt, remove both worktree and branch for `y` and `n`.
- On failure before normal completion, preserve current `worktree.keepOnFailure` behavior.
- `detdoc apply <run-id>` behavior remains unchanged.

---

## File Structure

- `src/core/worktree.ts`: Owns creating and cleaning linked Git worktrees. Add branch/path options and branch cleanup.
- `src/core/flow.ts`: Passes `manifest.runId` and `.worktrees/<run-id>` into worktree creation; passes inspect path to approval UI.
- `src/core/approval.ts`: Adds optional `worktreePath` to apply approval context and renders it.
- `tests/worktree.test.ts`: Covers branch worktree creation and cleanup.
- `tests/flow-run.test.ts`: Covers run-flow integration and apply rejection cleanup.
- `tests/approval.test.ts`: Covers prompt rendering with inspect path.
- `README.md`: Documents inspection during apply prompt.

---

### Task 1: Branch-Aware Worktree Lifecycle

**Files:**
- Modify: `src/core/worktree.ts`
- Test: `tests/worktree.test.ts`

**Interfaces:**
- Consumes: `GitRepository.git(args: string[]): Promise<string>`, `GitRepository.headCommit(): Promise<string>`.
- Produces: `WorktreeManager.createFromHead(baseRepo, { path?: string; branchName?: string; prefix?: string }): Promise<TemporaryWorktree>` where `TemporaryWorktree` includes `path`, `repo`, optional `branchName`, and `cleanup()`.

- [ ] **Step 1: Write failing worktree tests**

Add tests to `tests/worktree.test.ts` that create a branch worktree at a provided path and verify cleanup removes the branch:

```ts
it("creates a visible branch worktree and cleans up its branch", async () => {
  const fixture = await createFixture();
  const baseRepo = new GitRepository(fixture.cwd);
  const manager = new WorktreeManager();
  const runId = "20260620T121500Z-run-abcdef12";
  const path = join(fixture.cwd, ".worktrees", runId);

  const worktree = await manager.createFromHead(baseRepo, { path, branchName: runId });
  try {
    expect(worktree.path).toBe(path);
    await expect(worktree.repo.git(["branch", "--show-current"])).resolves.toBe(`${runId}\n`);
    await expect(access(path)).resolves.toBeUndefined();
  } finally {
    await worktree.cleanup();
  }

  await expect(access(path)).rejects.toThrow();
  const branches = await baseRepo.git(["branch", "--list", runId]);
  expect(branches.trim()).toBe("");
});
```

- [ ] **Step 2: Run failing test**

Run:

```bash
npm test -- tests/worktree.test.ts
```

Expected: FAIL because `createFromHead` does not accept `path`/`branchName` and creates detached temp worktrees.

- [ ] **Step 3: Implement branch/path support**

Update `src/core/worktree.ts`:

```ts
import { mkdir, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { GitRepository } from "./git.js";

export interface TemporaryWorktree {
  path: string;
  repo: GitRepository;
  branchName?: string;
  cleanup(): Promise<void>;
}

export interface CreateWorktreeOptions {
  prefix?: string;
  path?: string;
  branchName?: string;
}

export class WorktreeManager {
  async createFromHead(baseRepo: GitRepository, options: CreateWorktreeOptions = {}): Promise<TemporaryWorktree> {
    const prefix = options.prefix ?? "detdoc-worktree-";
    const container = options.path ? undefined : await mkdtemp(join(tmpdir(), prefix));
    const path = options.path ?? join(container!, "worktree");
    const head = await baseRepo.headCommit();

    if (options.path) await mkdir(dirname(path), { recursive: true });

    if (options.branchName) {
      await baseRepo.git(["worktree", "add", "-b", options.branchName, path, head]);
    } else {
      await baseRepo.git(["worktree", "add", "--detach", path, head]);
    }

    const repo = new GitRepository(path);
    return {
      path,
      repo,
      branchName: options.branchName,
      cleanup: async () => {
        await baseRepo.git(["worktree", "remove", "--force", path]).catch(async () => {
          await rm(path, { recursive: true, force: true });
        });
        if (options.branchName) {
          await baseRepo.git(["branch", "-D", options.branchName]).catch(() => undefined);
        }
        if (container) await rm(container, { recursive: true, force: true });
      },
    };
  }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
npm test -- tests/worktree.test.ts
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/worktree.ts tests/worktree.test.ts
git commit -m "feat: create named branch worktrees"
```

---

### Task 2: Use Run IDs for Run/Fix Worktrees

**Files:**
- Modify: `src/core/flow.ts`
- Test: `tests/flow-run.test.ts`

**Interfaces:**
- Consumes: `WorktreeManager.createFromHead(baseRepo, { path, branchName })` from Task 1.
- Produces: `runFlow` creates `.worktrees/<run-id>` and keeps it present through `approveApply`.

- [ ] **Step 1: Write failing integration test**

Add a custom approval UI in `tests/flow-run.test.ts` that rejects apply and checks the worktree exists during approval and is removed after completion:

```ts
it("keeps the named run worktree inspectable until apply approval, then cleans it up on reject", async () => {
  const fixture = await createFixture();
  const agent = new FakeAgentRunner({
    plan: {
      summary: "Update app",
      risk: "low",
      questions: [],
      changes: [{ kind: "modify", targetFiles: ["src/app.ts"], reason: "test", rationale: "test" }],
    },
    implementation: async (cwd) => {
      await writeFile(join(cwd, "src/app.ts"), "export const x = 2;\n", "utf8");
    },
  });

  let runId = "";
  let worktreePath = "";
  const approval = {
    async approvePlan() {
      return true;
    },
    async approveApply(context: ApplyApprovalContext) {
      runId = context.runId;
      worktreePath = join(fixture.cwd, ".worktrees", runId);
      expect(context.worktreePath).toBe(worktreePath);
      await expect(access(worktreePath)).resolves.toBeUndefined();
      const diff = await new GitRepository(worktreePath).diff();
      expect(diff).toContain("export const x = 2");
      return false;
    },
  };

  const result = await runDocFlow({ cwd: fixture.cwd, agent, approval });
  expect(result.applied).toBe(false);
  expect(result.runId).toBe(runId);
  await expect(access(worktreePath)).rejects.toThrow();
  const branches = await fixture.git(["branch", "--list", runId]);
  expect(branches.stdout.trim()).toBe("");
});
```

Ensure imports include `writeFile`, `GitRepository`, and `ApplyApprovalContext` if not already present.

- [ ] **Step 2: Run failing test**

Run:

```bash
npm test -- tests/flow-run.test.ts
```

Expected: FAIL because `context.worktreePath` is absent and DetDoc still creates temp detached worktrees.

- [ ] **Step 3: Implement run-flow worktree path**

Update `src/core/flow.ts` around worktree creation:

```ts
import { join } from "node:path";
```

Create the worktree with:

```ts
const worktreePath = join(cwd, ".worktrees", manifest.runId);
const worktree = await new WorktreeManager().createFromHead(mainRepo, {
  path: worktreePath,
  branchName: manifest.runId,
});
```

Pass path to apply approval:

```ts
if (!(await approveApply(input, { runId: manifest.runId, changedFiles: validation.changedFiles, worktreePath }))) {
```

- [ ] **Step 4: Run tests**

Run:

```bash
npm test -- tests/flow-run.test.ts tests/worktree.test.ts
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/flow.ts tests/flow-run.test.ts
git commit -m "feat: expose run worktrees by run id"
```

---

### Task 3: Show Inspect Path in Apply Prompt

**Files:**
- Modify: `src/core/approval.ts`
- Test: `tests/approval.test.ts`

**Interfaces:**
- Consumes: optional `worktreePath` passed from `runFlow`.
- Produces: `ApplyApprovalContext` includes `worktreePath?: string`; terminal UI renders it when present.

- [ ] **Step 1: Write failing approval test**

Update the apply approval rendering test in `tests/approval.test.ts` to pass `worktreePath` and assert it appears:

```ts
await approval.approveApply({
  runId: "20260620T001627Z-run-1ae174a1",
  changedFiles: ["src/app.ts", "src/api.ts"],
  worktreePath: ".worktrees/20260620T001627Z-run-1ae174a1",
});
expect(plain).toContain("Inspect worktree:");
expect(plain).toContain(".worktrees/20260620T001627Z-run-1ae174a1");
```

- [ ] **Step 2: Run failing approval test**

Run:

```bash
npm test -- tests/approval.test.ts
```

Expected: FAIL because `worktreePath` is not in `ApplyApprovalContext` or not rendered.

- [ ] **Step 3: Implement prompt rendering**

Update `src/core/approval.ts`:

```ts
export interface ApplyApprovalContext {
  runId: string;
  changedFiles: string[];
  worktreePath?: string;
}
```

In `approveApply`, add the inspect line before `Next:`:

```ts
...(context.worktreePath ? ["", `${colors.bold("Inspect worktree:")} ${colors.cyan(context.worktreePath)}`] : []),
"",
`${colors.bold("Next:")} Press y then Enter to apply these changes and create a git commit.`,
```

- [ ] **Step 4: Run tests**

Run:

```bash
npm test -- tests/approval.test.ts tests/flow-run.test.ts
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/approval.ts tests/approval.test.ts
git commit -m "feat: show worktree inspect path before apply"
```

---

### Task 4: Documentation and Full Verification

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: behavior from Tasks 1-3.
- Produces: README instructions for inspecting `.worktrees/<run-id>` during apply approval.

- [ ] **Step 1: Update README**

In the Quick start/apply section, add:

```md
At the final apply prompt, DetDoc leaves the implementation worktree available for inspection:

```bash
cd .worktrees/<run-id>
git status
git diff
```

After you answer `y` or `n`, DetDoc removes that worktree and its `<run-id>` branch. If the run fails before normal completion and `worktree.keepOnFailure` is true, the worktree is kept for debugging.
```

- [ ] **Step 2: Run full test suite**

Run:

```bash
npm test
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document inspectable run worktrees"
```

---

## Self-Review

- Spec coverage: Tasks 1 and 2 implement visible `.worktrees/<run-id>` branch worktrees; Task 2 preserves cleanup after `y`/`n`; Task 3 surfaces the path in the prompt; Task 4 documents user workflow.
- Placeholder scan: No TODO/TBD placeholders remain.
- Type consistency: `ApplyApprovalContext.worktreePath?: string` is added in Task 3 and consumed by Task 2; `CreateWorktreeOptions.path` and `branchName` are produced in Task 1 and consumed by Task 2.
