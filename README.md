# DetDoc

DetDoc is a macOS desktop app that turns Markdown documentation changes (or an explicit
bugfix intent) into approved, validated code changes using the embedded `pi` coding agent.
Documentation is the source of truth; the agent may only edit code you approve, inside an
isolated git worktree, and every change is validated before it touches your main worktree.

The core flow is:

1. read project docs (or a fix intent);
2. ask `pi` for a structured implementation plan;
3. approve the plan;
4. let `pi` implement only the approved target files inside an isolated git worktree;
5. validate the generated patch;
6. optionally apply it to the main worktree;
7. create a git commit and leave the repository clean.

## Architecture

The product is a SwiftUI macOS application backed by a UI-agnostic Swift core. Everything
lives under `swift/`:

- **`swift/DetDocCore`** — pure-Swift SwiftPM package exposing the `DetDocCore` product:
  domain models, config (Yams), path policy + glob matcher, plan/patch validators,
  git/worktree/docs services, doc-diff + dirty policy, artifact store, run-id, the
  `DetDocEngine` orchestrator, and the agent layer (`AgentRunner`, `FakeAgentRunner`,
  and `PiAgentRunner` driving `pi --mode rpc` over strict LF-delimited JSONL).
- **`swift/DetDocApp`** — the macOS SwiftUI shell plus the `@MainActor @Observable` MVVM+C
  view models (coordinator/routing, per-screen view models, diff model). Includes the
  `@main` App, `NSOpenPanel` folder picker, workspace with `NavigationSplitView` + inspector,
  docs explorer, source/preview editor, run/fix panel with plan & patch approval gates, runs,
  settings, onboarding. Views are thin; all logic lives in the view models, tested headless
  via the `DetDocAppTests` target.

## Requirements

- macOS 27+
- Swift 6 toolchain (Xcode 27+)
- [`pi`](https://github.com/earendil-works/pi) on `PATH` for real agent runs (a built-in
  `FakeAgentRunner` is used by tests and works offline)
- [Tuist](https://tuist.dev) to (re)generate the app project

## Build and test

Core (headless, no Xcode required):

```bash
swift test --package-path swift/DetDocCore
```

The macOS app and its view-model tests (`DetDocApp.xcodeproj` is generated and git-ignored):

```bash
cd swift/DetDocApp
tuist generate
xcodebuild build -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS'
xcodebuild test  -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS'
# or: open DetDocApp.xcodeproj   # then build/run in Xcode
```

## Using the app

Point DetDoc at a git repository, then drive the documentation-driven workflow from the UI:

1. **Onboarding / init** scaffolds DetDoc metadata in the project:
   - `.detdoc/config.yml`
   - `.detdoc/runs/.gitkeep`
   - starter documentation under `docs/`
   - managed `.gitignore` entries for `.DS_Store`, `.detdoc/runs/*`, and `.worktrees/`
2. **Edit Markdown docs** (e.g. `docs/technical-spec.md`), then start a **run**. DetDoc asks
   `pi` for a plan inside an isolated worktree.
3. **Approve or reject the plan** at the plan gate.
4. DetDoc lets `pi` implement only the approved targets, then **validates** the generated
   patch against the approved target list.
5. **Apply or discard** at the patch gate. Apply merges the validated patch into the main
   worktree, runs post-apply validation, commits `DetDoc apply <run-id>`, and leaves git
   clean. Discard keeps the run saved under `.detdoc/runs/<run-id>/`.

**Fix mode** uses the same plan → implement → validate → apply pipeline, but the input is a
free-text bugfix message instead of a documentation diff.

While a run is in progress its worktree is visible under `.worktrees/<run-id>` (on a branch
named `<run-id>`) so you can inspect generated changes before deciding to apply.

## Safety model

DetDoc intentionally narrows what the embedded agent can change.

- Documentation is read-only input; plans targeting docs and patches modifying docs are
  rejected.
- The agent may only write approved target paths; config-denied paths are blocked.
- Agent work happens in an isolated git worktree before apply.
- Before apply, the patch is validated against the approved target list, and run-artifact
  paths (`.detdoc/runs/`) are rejected.
- Saved runs verify the recorded base commit (`APPLY_BASE_MISMATCH`) and per-file preimage
  hashes (`APPLY_PREIMAGE_MISMATCH`) before re-applying.
- After apply, DetDoc verifies the working tree is clean (`GIT_NOT_CLEAN_AFTER_APPLY`).

Successful apply merges only the validated patch into the main worktree; unapproved files
created in the isolated worktree are not copied into main.

## Configuration

Project config lives at `.detdoc/config.yml`:

```yaml
docs:
  include:
    - "**/*.md"
  exclude:
    - ".detdoc/**"
    - "node_modules/**"

paths:
  deny:
    - ".env"
    - ".env.*"
    - "node_modules/**"
    - ".git/**"

validation:
  commands: []

agent:
  provider: pi-rpc
  model: null
  thinking: high

worktree:
  keepOnFailure: true

apply:
  autoCommit: true
```

### Validation and repair

Validation commands run in the isolated worktree before apply, and again in the main
worktree after apply. Supported command shapes:

```yaml
validation:
  commands:
    - name: Generate
      run: xcodegen generate
    - name: Test
      command: swift test
    - swift test            # bare string: name == command
```

If validation fails and the agent supports repair, DetDoc sends the failure back to `pi` and
retries (up to two attempts). Validation failure logs are saved under the run directory.

## Saved runs

Pending, discarded, or failed runs are stored under `.detdoc/runs/<run-id>/`, including
`manifest.json`, `plan.proposed.json`, `plan.approved.json`, `changes.patch`, and
`validation-failure-<n>.log` (when repair was attempted). A saved run can be re-applied from
the runs view; apply re-checks the base commit and preimage hashes first.

## Project-local pi skills

The embedded `pi` can use project skills committed under `.pi/skills/` or `.agents/skills/`.
Because runs happen in a worktree created from `HEAD`, skills must be committed before a run
for the agent to see them. `pi` initially sees only each skill's `name` and `description`, so
write descriptions that clearly state when the skill applies.

## History

DetDoc began as a TypeScript CLI and a Rust/Tauri GUI prototype; both were used as parity
oracles for this Swift rewrite and have since been removed. The parity audit performed before
their removal is recorded in
`docs/superpowers/specs/2026-06-21-detdoc-swift-parity-report.md`, and the implementation
plans live under `docs/superpowers/plans/`.
