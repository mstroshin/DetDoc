# Pre-Run Documentation Diff Review — Design

Date: 2026-06-23

## Summary

When the user clicks **Run docs**, DetDoc currently goes straight into the
planning phase. This feature inserts a review gate first: a modal that shows the
exact documentation diff that will drive the run, so the user can look it over
once more and explicitly confirm before any worktree or run artifacts are
created.

This is **Slice 1** of a larger feature. Slice 2 (an agent analysis of the diff
that proposes splitting the work across parallel sub-agents, with an on/off
toggle) is a separate spec. Slice 1 is designed so Slice 2 bolts onto the same
gate without rework.

## Goals

- Show the documentation diff in a modal after **Run docs**, before the run starts.
- Let the user confirm (proceed) or cancel (do nothing) from the modal.
- Create no worktree and no run artifacts until the user confirms.
- Reuse the existing diff renderer so the review looks like the patch review.
- Keep the gate in the engine so every `.run` entry point gets it for free and
  Slice 2 can enrich the same event.

## Non-goals

- The agent parallelization analysis, the parallel toggle, and parallel
  sub-agent execution — that is Slice 2.
- A review gate for `detdoc fix`. Fix has no documentation diff; its flow is
  unchanged.
- Editing the diff inside the modal. The modal is read-only; users edit docs in
  the editor.
- Changing what counts as a documentation change, the dirty-state policy, or the
  `NO_DOC_CHANGES` behavior.

## Flow

```
[Run docs]
  → engine: loadConfig
  → engine: collectInput  (DocDiff.normalized → the doc diff)
  → engine: emit inputReady(diff)  ── GATE (new) ──
       modal shows the diff
         Cancel → engine throws RUN_CANCELLED_BY_USER → VM returns to .idle
         Run    → proceed
  → engine: createRun → createWorktree → plan gate → implement → patch gate → apply
```

The gate sits between `collectInput` and `createRun`, so nothing is created if
the user cancels. For `mode == .fix` the gate is skipped entirely.

## Architecture

### Engine (`DetDocEngine`)

Mirror the existing plan/apply gate machinery:

- New event: `RunEvent.inputReady(String)` carrying the normalized doc diff.
- New continuation `pendingInput: CheckedContinuation<InputDecision, Error>?`
  with `submitInputDecision(_:)`, `awaitInputDecision()` (cancellation-aware,
  like `awaitPlanDecision`), and `failPendingInput()`.
- New decision enum `InputDecision { case confirm, cancel }`.
- In `runFlow`, after `collectInput` computes `taskInput` and **before**
  `createRun`: if `mode == .run`, `emit(.inputReady(taskInput))` then
  `awaitInputDecision()`. On `.cancel`, throw
  `DetDocError("RUN_CANCELLED_BY_USER", "Run cancelled before start.")`.

`taskInput` for `.run` is already `DocDiff.normalized(...)`, which is the raw git
diff of the documentation files (path-filtered, with `git add -N` for untracked
docs) — no transformation. So the modal shows exactly what the agent receives.

### View model (`RunPanelViewModel`)

- New `Stage.inputPending`.
- New `private(set) var inputDiff: String?`.
- `handle(.inputReady(diff))` → `inputDiff = diff`, `stage = .inputPending`.
- `confirmInput()` → `inputDiff = nil`, `stage = .running`,
  `engine.submitInputDecision(.confirm)`.
- `cancelInput()` → `engine.submitInputDecision(.cancel)`.
- In `fail(_:)`, map code `RUN_CANCELLED_BY_USER` to `stage = .idle` (a pre-run
  cancel is not a failure), leaving `error` unset.

### UI

- New `InputReviewView` (in `Sources/Workspace/Review/`): a header with the
  changed-file count, the per-file diff, and two buttons — **Run**
  (`.borderedProminent`) and **Cancel**. Read-only.
- Presented as a `.sheet` in `WorkspaceView`, bound to
  `panel.stage == .inputPending`, driven by `panel.inputDiff`.
- Accessibility IDs on the sheet, file rows, and both buttons
  (`input-review-sheet`, `input-review-run`, `input-review-cancel`).
- SwiftUI previews with multiple states: many files, a single file, and a large
  diff that scrolls.

### Reuse

Extract the per-file diff rendering currently inlined in `PatchReviewView` into a
shared `DiffFilesView` (input: `[DiffFile]`), and have both `PatchReviewView` and
`InputReviewView` use it. One source of truth for diff line colors/backgrounds;
removes ~25 duplicated lines.

## Edge cases

- **No documentation changes:** `DocDiff.normalized` throws `NO_DOC_CHANGES`
  during `collectInput`, before the gate — the modal never opens and the error
  surfaces as today. Unchanged.
- **Dirty non-doc changes:** `DirtyPolicy.assertClean` (inside
  `DocDiff.normalized`) throws before the gate — unchanged.
- **Cancel:** no worktree or artifacts exist yet; the engine just throws
  `RUN_CANCELLED_BY_USER` and the VM returns to `.idle`.

## Testing

- `DetDocEngineTests` (with the fake agent): the `.run` flow emits `inputReady`
  before any worktree is created; `.cancel` stops the flow with
  `RUN_CANCELLED_BY_USER` and creates no worktree/artifacts; `.confirm` proceeds
  to the plan gate. `.fix` emits no `inputReady`.
- `RunPanelViewModelTests`: `inputReady` → `.inputPending` with `inputDiff` set;
  `confirmInput()` → `.running`; cancel path maps `RUN_CANCELLED_BY_USER` to
  `.idle` with no error.
- `DiffFilesView` is exercised indirectly by existing `DiffModelTests` parsing;
  no new parser logic is introduced.

## Acceptance criteria

- Clicking **Run docs** with documentation changes opens a modal showing that
  diff before anything is created.
- **Cancel** leaves the workspace untouched (no worktree, no artifacts) and
  returns to idle.
- **Run** proceeds into the existing plan → implement → apply flow unchanged.
- `detdoc fix` behavior is unchanged.
- The review modal and the patch review share one diff renderer.
