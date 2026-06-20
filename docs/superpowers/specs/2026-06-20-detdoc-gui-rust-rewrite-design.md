# DetDoc GUI Rust Rewrite Design

Date: 2026-06-20
Branch: `detdoc-gui-rust-rewrite`

## Summary

DetDoc v2 will become a macOS-first Tauri desktop application with a React frontend and Rust orchestration core. The current TypeScript CLI remains temporarily in the repository as a parity reference during the rewrite, but the product direction is GUI-only: users edit documentation, run DetDoc, review plans and patches, and apply saved runs from the desktop app.

The Rust core will replace DetDoc's current CLI orchestration for `init`, documentation diff collection, `run`, `fix`, validation, artifacts, worktrees, and `apply`. Agent execution will use an installed `pi` binary through `pi --mode rpc` over JSONL. DetDoc will not bundle pi in the MVP.

## Goals

- Provide a GUI-first DetDoc workflow for editing Markdown documentation and turning it into validated code changes.
- Replace product-facing TypeScript CLI orchestration with Rust core logic suitable for Tauri.
- Preserve existing DetDoc safety semantics and artifact formats.
- Support `run`, `fix`, and `apply` from the GUI.
- Support saved/pending runs from `.detdoc/runs/*`.
- Bootstrap new repositories through a GUI `init` onboarding flow.
- Keep the first supported platform focused on macOS.

## Non-goals

- Do not ship the current DetDoc CLI as a long-term product interface.
- Do not support Windows or Linux in the MVP.
- Do not bundle pi or Node in the MVP.
- Do not build a multi-project manager in the MVP.
- Do not make replay/debug a first-class GUI workflow in the MVP.
- Do not redesign DetDoc artifact formats for v2.

## Product Scope

The MVP opens one git repository at a time. The shell should not block a future multi-project project switcher, but multi-project management is out of scope.

The primary workspace is an IDE-style layout:

- left: Markdown documentation explorer;
- center: documentation editor;
- right: DetDoc run/review panel.

Users can:

- initialize a repository for DetDoc;
- create, rename, delete, and edit Markdown docs;
- edit docs through Tiptap rich-text mode;
- switch to Markdown source mode for exact `.md` control;
- review the current documentation diff;
- run a documentation-driven implementation;
- submit a bugfix intent without editing docs;
- approve or reject proposed plans;
- watch structured progress with expandable raw logs;
- review validated changed files and patches;
- apply the current run;
- apply saved runs from `.detdoc/runs/*`.

## Visual and Frontend Stack

Use:

- Tauri for desktop packaging and native integration;
- React for frontend UI;
- shadcn/ui, Radix, and Tailwind for the component system and visual language;
- Tiptap for rich Markdown editing;
- a Markdown source mode for exact `.md` editing;
- a diff viewer for patch review.

The visual direction is a dark-mode-friendly developer tool, closer to a lightweight IDE than a web admin dashboard.

## Architecture

### High-level components

```txt
React UI
  ↕ Tauri commands/events
Rust DetDoc Core
  ↕ git/filesystem/process
Repository, .detdoc artifacts, .worktrees
  ↕ JSONL stdin/stdout
pi --mode rpc
```

### React frontend

Frontend components:

- `ProjectShell`: top-level app shell with repo path, git status, pi health, and navigation.
- `DocsExplorer`: Markdown file tree using configured `docs.include` and `docs.exclude`.
- `DocEditor`: Tiptap rich editor with Markdown source mode and save/autosave state.
- `DetDocPanel`: run/fix controls, progress timeline, approvals, logs, and final apply controls.
- `PlanReview`: proposed plan summary, risk, questions, target files, and rationale.
- `PatchReview`: changed files, patch display, and inspectable worktree path.
- `RunsView`: saved/pending runs with status and apply actions.
- `SettingsView`: DetDoc config editing for validation commands, agent settings, worktree settings, pi health, and auto-commit behavior.

Frontend state should remain presentation-focused. Rust owns repository state, file IO, git operations, run state, pi process state, and artifact writes.

### Rust core

Rust modules should mirror the deterministic responsibilities of the current TypeScript core:

- `config`: read/write `.detdoc/config.yml`.
- `git`: status, diffs, apply patch, commits, file hashes, worktree commands.
- `docs`: documentation include/exclude matching and normalized doc diff collection.
- `manifest`: run id generation and manifest serialization.
- `artifacts`: `.detdoc/runs/<run-id>/` management.
- `plan`: proposed plan schema and validation.
- `validation`: patch safety checks and configured validation commands.
- `worktree`: `.worktrees/<run-id>` lifecycle on branch `<run-id>`.
- `agent`: `PiRpcAgentRunner` for planning, implementation, and validation repair.
- `flow`: orchestration for init, run, fix, apply, and saved-run listing.
- `events`: typed progress/log/error events emitted to Tauri.

The TypeScript implementation remains temporarily as reference behavior and test oracle during the rewrite.

## pi Integration

The MVP requires `pi` to be installed and available in `PATH`. On startup and in settings, the GUI runs a health check that verifies `pi --mode rpc` can start. If unavailable, the app shows setup instructions instead of failing during a run.

Rust will launch `pi --mode rpc` internally and communicate through strict LF-delimited JSONL. The Rust client must not use a parser that treats other Unicode separators as line delimiters.

Planning and implementation will preserve the current two-phase DetDoc protocol:

1. planning phase with read-only repository inspection and structured proposed plan output;
2. implementation phase inside the isolated worktree, constrained to approved target files.

If the RPC protocol cannot support the current custom `submit_plan` tool or write-guard behavior directly, the Rust agent layer must emulate the same safety boundary at DetDoc's orchestration layer: parse/validate plan output, inspect generated patches, reject unapproved paths, and never apply unvalidated changes to main.

## Artifact and Config Compatibility

The Rust rewrite must preserve compatibility with existing files:

```txt
.detdoc/config.yml
.detdoc/runs/<run-id>/manifest.json
.detdoc/runs/<run-id>/plan.proposed.json
.detdoc/runs/<run-id>/plan.approved.json
.detdoc/runs/<run-id>/changes.patch
.detdoc/runs/<run-id>/validation.log
.detdoc/runs/<run-id>/post-apply-validation.log
.worktrees/<run-id>/
```

The GUI should be able to list and apply pending runs produced by the current TypeScript DetDoc implementation when the artifact format is valid.

## Init / Onboarding

When a repository lacks `.detdoc/config.yml`, the GUI shows onboarding and can initialize DetDoc.

Initialization creates the same baseline assets as current `detdoc init`:

- `.detdoc/config.yml`;
- `.detdoc/runs/.gitkeep`;
- starter documentation under `docs/`;
- managed `.gitignore` entries for `.DS_Store`, `.detdoc/runs/*`, and `.worktrees/` as needed.

If the repository is clean, init may create an initial DetDoc metadata commit following current behavior. Starter docs remain editable for the user.

## Run and Fix Flow

### `run`

1. Load config and git status.
2. Reject dirty non-documentation changes.
3. Collect normalized documentation diff from dirty Markdown docs.
4. Create run manifest and artifact directory.
5. Create `.worktrees/<run-id>` on branch `<run-id>` from base commit.
6. Apply documentation diff into the run worktree.
7. Ask pi planning phase for a proposed plan.
8. Validate proposed plan against DetDoc rules.
9. Emit `plan-ready` event and pause for GUI approval.
10. On approval, write `plan.approved.json` and approved targets to manifest.
11. Ask pi implementation phase to edit inside the run worktree.
12. Collect patch for approved targets.
13. Validate patch against approved targets, denied paths, and documentation write rules.
14. Run configured validation commands inside the run worktree.
15. If validation fails and repair is supported, attempt bounded repair and save failure logs.
16. Emit final patch review event and pause for apply approval.
17. If approved, apply the saved validated patch to main.
18. Run post-apply validation in main.
19. Commit or stage according to auto-commit setting.
20. Clean up the run worktree and branch on normal completion.

### `fix`

`fix` uses the same pipeline, except the input is a user-authored intent message rather than a documentation diff. Dirty non-documentation changes are rejected. Fix plans must use `intent:fix` reasons and must not target documentation files in the MVP.

## Apply Behavior

The GUI supports applying:

- the current completed run/fix;
- saved pending runs from `.detdoc/runs/*`.

Apply always uses the saved validated `changes.patch`; it does not merge from the implementation branch.

Auto-commit behavior is configurable:

- default: apply patch, run post-apply validation, commit `DetDoc apply <run-id>`, and verify clean status;
- when disabled: apply patch, stage approved target files, run validation, and do not create a commit.

## Safety Model

The Rust rewrite preserves DetDoc's safety model:

- documentation is read-only input for implementation;
- plans targeting documentation are rejected;
- generated patches changing documentation are rejected;
- denied paths are blocked;
- agent work happens in an isolated worktree;
- main receives only the validated patch;
- apply requires explicit GUI approval unless the user has configured an auto path;
- failed runs preserve artifacts and may preserve worktrees when `worktree.keepOnFailure` is enabled.

The GUI must make safety state visible: current phase, target files, denied-path failures, validation failures, run id, worktree path, and next suggested action.

## Tauri Commands and Events

Representative commands:

- `project_open(path)`;
- `project_status()`;
- `detdoc_init(options)`;
- `docs_list()`;
- `docs_read(path)`;
- `docs_write(path, markdown)`;
- `docs_create(path, markdown)`;
- `docs_rename(from, to)`;
- `docs_delete(path)`;
- `runs_list()`;
- `run_start_from_docs(options)`;
- `run_start_fix(message, options)`;
- `run_approve_plan(run_id, approved)`;
- `run_approve_apply(run_id, approved)`;
- `apply_saved_run(run_id, options)`;
- `settings_read()`;
- `settings_write(config)`;
- `pi_health_check()`.

Representative events:

- `run:progress`;
- `run:log`;
- `run:plan-ready`;
- `run:approval-needed`;
- `run:patch-ready`;
- `run:error`;
- `run:complete`;
- `project:status-changed`.

Long-running flows must be cancellable where safe. Cancellation should not leave partial changes in main. Worktree cleanup follows the same keep-on-failure rules as normal failures.

## Error Handling

Errors should include:

- stable code;
- user-facing message;
- optional technical details;
- phase;
- run id when available;
- path or command when relevant;
- suggested next action.

Examples:

- missing `pi` in `PATH`: show setup screen and disable run/fix actions;
- dirty non-doc changes: list blocking files and explain that they must be committed or reverted;
- plan validation failure: show rejected target/reason;
- validation failure: show command, exit status, and expandable log;
- cleanup failure: report clearly without hiding the original run result.

## Testing Strategy

Testing should proceed in layers:

1. Rust unit tests for config parsing, plan validation, path policy, artifact serialization, and run id formatting.
2. Rust git fixture tests for status policy, doc diff collection, worktree creation/cleanup, patch apply, commit/stage behavior, and saved-run apply.
3. Rust integration tests that compare selected outputs with the current TypeScript implementation fixtures where practical.
4. Frontend component tests for editor shell, run panel state transitions, plan review, patch review, and runs list.
5. macOS Tauri smoke tests for app launch, pi health failure/success, init, and a fake-agent run path.

The existing TypeScript tests remain useful as parity documentation until Rust GUI reaches equivalent behavior for `init`, `run`, `fix`, `apply`, and saved runs.

## Migration Plan

The rewrite should be parallel and incremental:

1. Add Tauri/Rust/React app beside the current TypeScript project.
2. Implement Rust types for existing config and artifact formats.
3. Port deterministic core logic from TypeScript to Rust.
4. Add a fake agent runner for tests.
5. Add `PiRpcAgentRunner` using `pi --mode rpc`.
6. Add Tauri command/event API.
7. Build the React IDE-style workspace.
8. Add GUI init, run/fix, review, apply, and saved-runs flows.
9. Reach parity with current TypeScript CLI behavior.
10. In a later cleanup, remove or archive the TypeScript CLI once Rust GUI is validated.

## Open Decisions Deferred

- Whether to bundle pi as a sidecar after MVP.
- Whether to support Linux and Windows after macOS stabilizes.
- Whether to expose replay as a GUI action.
- Which exact diff viewer package to use.
- Whether Tiptap Markdown serialization needs project-specific extension rules.
