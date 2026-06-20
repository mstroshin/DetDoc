# DetDoc GUI Swift Rewrite Design

Date: 2026-06-20
Branch: `detdoc-gui-swift-rewrite`

## Summary

DetDoc's desktop GUI will be rewritten from the Tauri + React + Rust stack into a
native macOS application written in pure Swift and SwiftUI. The minimum deployment
target is macOS 27, and the app should prefer the newest macOS 27 SwiftUI APIs.
Tests use Swift Testing. The architecture is MVVM+C (Model–View–ViewModel +
Coordinators).

The product target for this rewrite is the **full DetDoc GUI vision** described in the
prior Rust-rewrite design doc — not only the minimal behavior currently wired into the
React MVP. That means: documentation editing, `init`/onboarding, documentation-driven
`run`, bugfix `fix`, interactive plan review, interactive patch review, saved-run apply,
a settings screen, and real agent execution by driving the installed `pi` binary.

All deterministic DetDoc logic is reimplemented natively in Swift in a UI-agnostic
core library, `DetDocCore`. The SwiftUI app is a thin layer on top. The existing
TypeScript CLI and Rust/Tauri code remain in the repository as a parity reference and
test oracle during the rewrite and are removed only in a later, separate cleanup step.

## Goals

- Deliver a native macOS 27 SwiftUI app that does everything the full DetDoc GUI design
  describes: edit docs, init, run, fix, review plans, review patches, apply runs, manage
  settings, and run the real agent.
- Reimplement all deterministic DetDoc orchestration in pure Swift (`DetDocCore`).
- Keep `DetDocCore` completely UI-agnostic so a future Swift TUI can reuse it unchanged.
- Preserve DetDoc safety semantics and on-disk artifact/config formats.
- Drive the real agent through the installed `pi` binary (subprocess + JSONL), with a
  deterministic fake agent for tests and offline use.
- Use MVVM+C with `@Observable` view models and coordinator-owned navigation.
- Test in layers with Swift Testing, reusing TS/Rust behavior as a parity oracle.

## Non-goals

- Do not ship the TypeScript CLI or the Tauri/React/Rust app as a long-term interface.
- Do not support iOS, Windows, or Linux. macOS 27 only.
- Do not bundle `pi` or Node; `pi` must be installed and on `PATH`.
- Do not build a multi-project manager (one repository open at a time).
- Do not make replay a first-class GUI workflow in this iteration (deferred, as in the
  prior design).
- Do not change DetDoc artifact or config formats.
- Do not build the future TUI in this iteration; only keep the core ready for it.

## Architecture Decision Record

Selected approach: **two-layer (Variant A)** — a pure-Swift, UI-agnostic `DetDocCore`
SwiftPM library plus a thin SwiftUI app (`DetDocApp`) built with XcodeGen. Rejected
alternatives:

- **Monolithic app target** (core + UI in one target): faster to start, but the core is
  not independently testable and MVVM+C boundaries blur. Rejected.
- **Swift UI over the retained Rust core via FFI (UniFFI/C-ABI)**: lowest reimplementation
  risk, but not pure Swift. Rejected per the pure-Swift directive.

Confirmed decisions:

- **Editor:** Markdown **source editor with a live preview pane**, not a WYSIWYG editor.
  Rationale: DetDoc builds its `doc-diff` from raw Markdown, and a WYSIWYG editor that
  re-serializes through `AttributedString` could silently alter markup and pollute the
  diffs the whole pipeline depends on. Source mode keeps exact `.md` control.
- **Build/packaging:** XcodeGen-generated `.xcodeproj` (reproducible, no noisy pbxproj
  merge conflicts, real `.app`, native Swift Testing test target). XcodeGen already
  appears in the repo's README/validation conventions.
- **Legacy code:** kept in-repo as a parity oracle and test fixtures; removed later in a
  separate cleanup.
- **YAML:** `DetDocCore` may depend on **Yams** (SwiftPM) for robust `.detdoc/config.yml`
  parsing, since the config is hand-edited. This is the only planned external runtime
  dependency of the core.
- **Agent transport:** drive the installed `pi` binary as a subprocess over JSONL. The
  exact `pi --mode rpc` wire schema is pinned during implementation behind the
  `PiAgentRunner` module.

## Module Layout

```txt
swift/
  DetDocCore/                      # SwiftPM package — UI-agnostic, Sendable, async
    Package.swift                  # library DetDocCore + DetDocCoreTests (Swift Testing)
    Sources/DetDocCore/...
    Tests/DetDocCoreTests/...
  DetDocApp/                       # macOS app (XcodeGen)
    project.yml                    # references ../DetDocCore as a local SwiftPM package
    Sources/                       # SwiftUI Views / @Observable ViewModels / Coordinators
    Tests/                         # Swift Testing for view models (xcodebuild test)
    Resources/                     # Info.plist, *.entitlements, Assets.xcassets
```

- `DetDocCore` is the single owner of deterministic logic. Both the SwiftUI GUI and any
  future TUI depend on it. `swift test` runs core tests headlessly (CI/validation).
- `DetDocApp` is a thin MVVM+C layer depending on `DetDocCore` via a local SwiftPM
  reference in `project.yml`.
- The legacy `src/`, `src-tauri/`, `src-ui/` trees stay in place; Swift work lives under
  `swift/`.

## DetDocCore: Domain Model

All models are `Codable` and `Sendable`. JSON artifacts preserve the existing on-disk
field names and shapes (matching the Rust/TS serializers).

- `DetDocConfig`: `docs.include`/`docs.exclude`, `paths.deny`, `validation.commands`,
  `agent.provider`/`model`/`thinking`, `worktree.keepOnFailure`.
- `ProposedPlan`: `summary`, `changes: [PlanChange]`, `questions: [String]`, `risk`.
- `PlanChange`: `reason`, `targetFiles: [String]`, `kind` (`create`/`modify`/`delete`/
  `rename`), `rationale`.
- `RunManifest`: `runId`, `mode` (`run`/`fix`), `baseCommit`, `approvedTargets`, and
  per-file **preimage hashes** (closes the prior Rust MVP's deferred replay gap).
- `RunMode`: `run` | `fix`.
- `ProjectStatus`: `root`, `initialized`, `piAvailable`, `dirtyFiles: [DirtyFile]`.
- `DirtyFile`: `status`, `path`.
- `DocFile`: `path`, `title`.
- `RunSummary`: `runId`, `hasPatch`, `approvedTargets`.
- `RunFlowResult`: `runId`, `applied`, `patch`.
- `TokenUsage`: `input`, `output`, `cacheRead`, `cacheWrite`, `total`.
- `DetDocError`: `code` (stable), `message` (user-facing), `details?`, `phase?`,
  `runId?`, `path?`, `command?`, `suggestedAction?`.
- `RunEvent`: `progress` | `log` | `planReady` | `approvalNeeded` | `patchReady` |
  `error` | `complete` — emitted while a run/fix executes.

## DetDocCore: Services

Protocol-first; many are actors for safe concurrent access. Each maps to a current
Rust/TS module so behavior parity is easy to verify.

- `GitRepository`: wraps `Process` → `git` (shell-out, as the Rust core does). Preserves
  TS git semantics (`core.quotepath=false`, `whitespace=nowarn`, raw status). Methods:
  porcelain status, head, `applyPatch`, diff, `add -N`/`--`, commit, file hashes, worktree
  add/remove.
- `ConfigStore`: read/write `.detdoc/config.yml` via Yams.
- `DocsService`: `list` (walk `docs/**.md` honoring `include`/`exclude` globs), `read`,
  `write`, `create`, `rename`, `delete`. Glob matching uses a small Swift matcher (or
  POSIX `fnmatch`).
- `ArtifactStore`: `.detdoc/runs/<run-id>/` create/read/write JSON+text, delete run.
- `WorktreeManager`: `.worktrees/<run-id>` on branch `<run-id>` from a base commit;
  create-from-head; cleanup honoring `worktree.keepOnFailure`.
- `ValidationRunner`: run configured `validation.commands` in a cwd; capture logs.
- `PlanValidator`: enforce plan rules — non-empty `changes`; `reason` prefixes
  (`doc-diff:` for run, `intent:fix` for fix); no documentation targets; no denied paths;
  valid `kind`. Provides `approvedTargets(from:)`.
- `PatchValidator`: verify a patch touches only approved targets, writes no docs, and hits
  no denied paths.
- `PathPolicy`: `isDeniedPath`, `isDocPath` (glob-based).
- `DocDiff`: `normalizedDocDiff` — collect the normalized diff of dirty Markdown docs.
- `PiHealth`: `pi --version` availability probe.

## Agent Layer and pi Integration

`AgentRunner` protocol:

- `plan(mode:input:config:cwd:) async throws -> ProposedPlan`
- `implement(approvedTargets:cwd:) async throws`
- `repairValidation(...) async throws`

Implementations:

- `FakeAgentRunner`: deterministic; for Swift Testing and offline use. Ports the current
  fake agent (single-target plan + write).
- `PiAgentRunner`: drives the installed `pi` binary as a subprocess via `Process` + strict
  LF-delimited JSONL using `pi --mode rpc` (fallback: `pi -p --mode json` with a custom
  `submit_plan` tool loaded via `-e`). The exact wire schema is pinned during
  implementation; this is the single uncertain module and is isolated behind the protocol.

The two-phase DetDoc protocol is preserved: a read-only planning phase that produces a
structured plan, then an implementation phase constrained to the run worktree.

## Safety Model

The in-process tool-call guard used by the TypeScript pi SDK cannot be reproduced across a
subprocess boundary. DetDoc safety is therefore enforced by **worktree isolation plus
final patch validation**, exactly the orchestration-layer emulation the prior design
anticipated:

- Documentation is read-only input; plans targeting docs are rejected (`PlanValidator`).
- Generated patches that change docs or denied paths are rejected (`PatchValidator`).
- The agent writes only inside `.worktrees/<run-id>`.
- Only a validated patch (approved targets only) reaches main; apply uses the saved
  `changes.patch`, never a branch merge.
- Launching `pi` with `--tools`/`--exclude-tools` narrows the toolset (read-only planning,
  scoped implementation) as defense in depth.
- Failed runs preserve artifacts and may preserve worktrees when
  `worktree.keepOnFailure` is enabled.

The GUI must surface safety state: current phase, target files, denied-path failures,
validation failures, run id, worktree path, and the next suggested action.

## App Layer (MVVM+C)

### Coordinators (own navigation; `@Observable`, `@MainActor`)

- `AppCoordinator`: root route `noProject` → `onboarding/init` → `workspace`. Holds the
  selected `root` and injects `DetDocCore` services into the environment via `@Entry`.
- Modal routes via an enum-driven `sheet`/`inspector`: `planReview`, `patchReview`,
  `settings`, `fixPrompt`, `piSetup`. The coordinator presents screens and binds their
  view models to the engine and core services.

### View Models (`@Observable`, `@MainActor`; presentation-only)

Repository state, file IO, and processes live in the core; view models hold presentation
state and call into the core.

- `WorkspaceViewModel`: `root`, `ProjectStatus`, docs, runs, refresh.
- `DocEditorViewModel`: source text, dirty flag, save, debounced preview.
- `RunPanelViewModel`: start run/fix, subscribe to `RunEvent`, current phase, logs,
  token usage.
- `PlanReviewViewModel`, `PatchReviewViewModel`, `RunsViewModel`, `SettingsViewModel`,
  `OnboardingViewModel`.

### Views (parity with the full design; newest macOS 27 SwiftUI APIs)

- `ProjectShellView`: shell built on `NavigationSplitView` — sidebar `DocsExplorerView`,
  content `DocEditorView`, right-hand run/review panel via the `.inspector` modifier
  (native IDE layout instead of the React grid).
- `DocsExplorerView`: `.md` tree from `docs.include`/`exclude`; create/rename/delete via
  context menu + `confirmationDialog`.
- `DocEditorView`: split **source + live preview**. Left: Markdown source editor with
  highlighting (`AttributedString`-backed `TextEditor`). Right: preview via
  `AttributedString(markdown:)` (upgrade to swift-markdown is a deferred minor decision).
  Save is always available (exact `.md`).
- `DetDocPanelView` (inspector): **Run docs** / **Fix…** controls, a structured progress
  timeline with phases, expandable raw logs, and final apply controls.
- `PlanReviewView`: summary, risk, questions, target files, rationale → **Approve/Reject**
  gate.
- `PatchReviewView`: changed files + an in-app **diff viewer** (own unified-diff parser
  with per-line coloring) + inspectable worktree path → **Apply/Discard** gate.
- `RunsView`: saved/pending runs from `.detdoc/runs/*` with status and Apply.
- `SettingsView`: edit `.detdoc/config.yml` — `validation.commands`, agent
  (provider/model/thinking), `worktree.keepOnFailure`, auto-commit, pi health.
- `OnboardingView` / `PiSetupView`: init flow and a "pi not found" screen with setup
  instructions (run/fix disabled).
- Errors: typed `DetDocError` surfaced via native `alert`/inline banners with `code` and
  `suggestedAction`.

## Run / Fix Flow

`DetDocEngine` (a core actor) runs run/fix and emits an
`AsyncThrowingStream<RunEvent>`; the GUI (and a future TUI) are subscribers, keeping the
engine UI-agnostic. At gates the engine emits `planReady` / `patchReady`
(`approvalNeeded`) and **waits** for a decision: the consumer calls
`engine.submitPlanDecision(.approve/.reject)` and
`engine.submitApplyDecision(.apply/.discard)` (via a continuation inside the actor).

Pipeline (matching the prior design):

1. Load config and git status.
2. Reject dirty non-documentation changes.
3. Collect the normalized documentation diff (run) or take the intent message (fix).
4. Create the run manifest and artifact directory.
5. Create `.worktrees/<run-id>` on branch `<run-id>` from the base commit.
6. Apply the documentation diff into the run worktree (run mode).
7. Planning phase via pi → `PlanValidator`.
8. Emit `planReady` and pause for approval.
9. On approval, write `plan.approved.json` and approved targets to the manifest.
10. Implementation phase inside the run worktree.
11. Collect the patch for approved targets (`add -N`, `diff --binary`).
12. Guard against an empty patch (`EMPTY_PATCH`).
13. `PatchValidator` against approved targets, denied paths, and doc-write rules.
14. Run `validation.commands` in the run worktree.
15. On failure with repair support, attempt bounded repair, saving
    `validation-failure-<n>.log`.
16. Emit `patchReady` and pause for apply approval.
17. On approval, apply the saved validated patch to main (not a branch merge).
18. Run post-apply validation in main.
19. Commit `DetDoc apply <run-id>` or stage approved files (per auto-commit).
20. Clean up the worktree and branch on normal completion (honoring `keepOnFailure`).

Cancellation: long phases are cooperatively cancellable (Swift `Task` cancellation);
cancellation never leaves partial changes in main; cleanup follows the same
keep-on-failure rules.

`applySavedRun` parity: guard `APPLY_BASE_MISMATCH` (HEAD must equal
`manifest.baseCommit`), then apply + commit/stage. Replay (deferred, as in the prior
design) checks base commit and preimage hashes.

## Artifact and Config Compatibility

The Swift rewrite preserves compatibility with existing files:

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

The GUI can list and apply pending runs produced by prior DetDoc implementations when the
artifact format is valid.

## Init / Onboarding

When a repository lacks `.detdoc/config.yml`, the GUI shows onboarding and can initialize
DetDoc. Initialization creates the same baseline assets as the current `detdoc init`:
`.detdoc/config.yml`, `.detdoc/runs/.gitkeep`, starter documentation under `docs/`, and
managed `.gitignore` entries for `.DS_Store`, `.detdoc/runs/*`, and `.worktrees/` as
needed. In a clean repository, init may create an initial DetDoc metadata commit
following current behavior; starter docs remain editable.

## Error Handling

Errors carry: stable `code`, user-facing `message`, optional technical `details`, `phase`,
`runId` when available, `path`/`command` when relevant, and a `suggestedAction`. Examples:
missing `pi` → setup screen, run/fix disabled; dirty non-doc changes → list blocking files;
plan validation failure → rejected target/reason; validation failure → command, exit
status, expandable log; cleanup failure → reported without hiding the original result.

## Testing Strategy

All tests use Swift Testing, in layers:

1. `DetDocCore` unit: config parsing, plan/patch validation, path policy, artifact
   serialization, run-id format, doc-diff normalization.
2. `DetDocCore` git fixtures: status policy, doc diff, worktree create/cleanup, patch
   apply, commit/stage, saved-run apply, base-commit mismatch.
3. Flow tests with `FakeAgentRunner`: full run/fix/apply offline (parity with the Rust
   `flow_fake_agent_tests`).
4. App layer: view-model state transitions (plan/patch gates, errors, runs list).
5. Optional smoke: app launch, pi health success/failure, init, fake-agent run.

The existing TS/Rust tests serve as parity documentation until Swift reaches equivalent
behavior for init/run/fix/apply/saved-runs.

## Migration / Phasing

1. Scaffold `swift/` + XcodeGen + an empty `DetDocCore` + `swift test` in CI.
2. Models + config/artifacts + path policy (with tests).
3. git/worktree/docs/doc-diff (with git fixtures).
4. plan/patch validation + `FakeAgentRunner` + `DetDocEngine` (with flow tests).
5. MVVM+C scaffold: workspace, onboarding/init, docs CRUD, editor.
6. Run/fix panel + plan/patch review + runs + settings.
7. `PiAgentRunner` (pin the RPC schema) + pi health.
8. Parity check against TS/Rust, then a separate step to archive/remove the legacy stacks.

## Open Decisions (deferred, minor)

- Preview renderer: Foundation `AttributedString(markdown:)` vs swift-markdown for full
  block fidelity.
- Exact pi RPC wire schema.
- Whether to expose replay as a GUI action (prior design says no for MVP).
- App icon and branding assets.
