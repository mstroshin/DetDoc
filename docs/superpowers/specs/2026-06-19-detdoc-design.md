# DetDoc MVP Design

Date: 2026-06-19

## Summary

DetDoc is a standalone TypeScript/Node.js CLI that turns project intent into a controlled, reproducible code-change workflow. Its primary source of intent is uncommitted Markdown documentation diffs. Its secondary source is an explicit bugfix message passed to `detdoc fix`.

DetDoc embeds `pi` through the pi SDK. It uses pi as a constrained agent runtime, not as an unconstrained chat interface. DetDoc owns git state checks, worktree isolation, plan approval, patch validation, final approval, artifact storage, and patch replay.

The MVP optimizes for practical reproducibility: it does not promise that a repeated LLM call will generate the same code diff. Instead, every accepted run stores the approved plan and final patch so the same patch can be checked and replayed without calling an LLM again.

## Goals

- Use free-form Markdown documentation as the primary product/spec source.
- Convert an uncommitted Markdown diff into a deterministic task packet for an embedded pi agent.
- Require user approval before implementation and before applying the final patch.
- Run implementation in an isolated temporary git worktree.
- Reject dirty non-documentation code changes before starting.
- Store all run artifacts needed to audit and replay an approved patch.
- Provide a `detdoc fix "message"` path for bug fixes that should not require documentation edits.
- Validate generated patches with structural checks and configured project commands.

## Non-goals

- Define a custom Markdown DSL or strict documentation format.
- Support Claude Code, Codex, or other agent backends in the MVP.
- Guarantee that rerunning the same LLM prompt produces the same patch.
- Work on top of dirty non-documentation changes.
- Automatically apply generated code without explicit approval.
- Update documentation during `detdoc fix` in the MVP.

## Product Scope and Happy Path

### `detdoc run`

1. The user edits Markdown documentation in a git repository.
2. The user runs `detdoc run`.
3. DetDoc checks that the working tree has dirty changes only in configured documentation files.
4. DetDoc normalizes the Markdown diff and creates a run manifest.
5. DetDoc creates a temporary git worktree from `HEAD`.
6. DetDoc applies only the Markdown diff into that worktree.
7. DetDoc starts embedded pi via the SDK in a read-only planning phase.
8. DetDoc asks pi for a structured implementation plan tied to the Markdown diff.
9. DetDoc shows the plan to the user.
10. After approval, DetDoc starts pi in implementation phase inside the temporary worktree.
11. DetDoc collects the resulting patch from the temporary worktree.
12. DetDoc validates the patch against the approved plan, deny paths, and configured validation commands.
13. DetDoc shows the final patch to the user.
14. After final approval, DetDoc applies the patch to the main working tree.
15. DetDoc stores artifacts under `.detdoc/runs/<run-id>/` for audit and replay.

### `detdoc fix "message"`

`detdoc fix` is a second intent source for bug fixes that should not require documentation changes.

Rules:

- Dirty documentation files are allowed but ignored.
- Dirty non-documentation changes are rejected.
- The temporary worktree starts from `HEAD`; dirty docs are not copied into it.
- The input intent is the user-provided message, stored as `.detdoc/runs/<run-id>/intent.md`.
- The resulting patch must not change documentation files in the MVP.

The rest of the flow mirrors `detdoc run`: planning approval, isolated implementation, validation, final approval, apply, and replay artifacts.

## CLI Commands

MVP commands:

```bash
detdoc init
detdoc diff
detdoc plan
detdoc run
detdoc fix "message to fix"
detdoc apply <run-id>
detdoc replay <run-id>
```

Command behavior:

- `detdoc init` creates `.detdoc/config.yml` and `.detdoc/runs/.gitkeep`.
- `detdoc diff` prints the normalized Markdown diff that would be used by `detdoc run`.
- `detdoc plan` runs only the planning phase for the current Markdown diff, writes `plan.proposed.json`, and stops before implementation.
- `detdoc run` executes the full documentation-diff workflow.
- `detdoc fix "..."` executes the full bugfix-intent workflow.
- `detdoc apply <run-id>` applies a saved `changes.patch` to the current working tree after precondition checks.
- `detdoc replay <run-id>` verifies recorded preconditions, applies the saved patch without an LLM call, and reruns validation commands.

## Configuration

Project configuration lives at `.detdoc/config.yml`.

Example:

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
  commands:
    - name: test
      run: npm test
    - name: typecheck
      run: npm run typecheck

agent:
  provider: pi-sdk
  model: null
  thinking: high

worktree:
  keepOnFailure: true
```

MVP config fields:

- `docs.include`: glob patterns for documentation files.
- `docs.exclude`: glob patterns excluded from documentation input.
- `paths.deny`: paths agents and patches must not modify.
- `validation.commands`: deterministic commands to run after patch generation.
- `agent`: pi SDK model and thinking settings.
- `worktree.keepOnFailure`: whether failed temporary worktrees should remain for debugging.

## Architecture

### Modules

- `CLI`: Parses commands and coordinates user flows.
- `ConfigLoader`: Reads and validates `.detdoc/config.yml`.
- `GitRepository`: Wraps git operations: status, `HEAD`, diffs, patch apply, file hashes.
- `InputBuilder`: Builds either `docs-diff` input for `run` or `fix-intent` input for `fix`.
- `WorktreeManager`: Creates and cleans temporary git worktrees from `HEAD`.
- `TaskPacketBuilder`: Builds deterministic task packets and manifests.
- `PiSdkRunner`: Embeds pi through the SDK and executes planning/implementation phases.
- `ApprovalUI`: Shows proposed plans and final patches, then asks for approval.
- `PatchCollector`: Extracts the final patch from the temporary worktree.
- `Validator`: Runs structural checks and configured validation commands.
- `ArtifactStore`: Writes run artifacts under `.detdoc/runs/<run-id>/`.
- `Replayer`: Applies saved patches without calling an LLM.

### Agent boundary

The system should keep an `AgentRunner` interface even though the MVP implementation is `PiSdkRunner`. This boundary exists to isolate DetDoc's deterministic orchestration from pi-specific SDK details. It is not a commitment to implement other agents in the MVP.

## Pi SDK Protocol

DetDoc embeds pi with `createAgentSession()` and custom configuration. It runs two separate phases.

### Planning phase

Purpose: inspect the repository and propose a structured plan without modifying files.

Tools:

- `read`
- `grep`
- `find`
- `ls`
- optionally a constrained inspect-only `bash` in a later iteration

The MVP should start without general `bash` during planning unless a concrete safe-command allowlist is implemented.

Planning input includes:

- mode: `run` or `fix`;
- normalized Markdown diff or bugfix intent;
- manifest metadata;
- config snapshot;
- DetDoc rules;
- optional search hints generated by DetDoc.

Expected planning output is structured JSON:

```json
{
  "summary": "Short description of intended implementation",
  "changes": [
    {
      "reason": "doc-diff:docs/api.md:L20-L35",
      "targetFiles": ["src/api.ts"],
      "kind": "modify",
      "rationale": "Why this file must change"
    }
  ],
  "questions": [],
  "risk": "low"
}
```

Validation rules:

- Output must parse as JSON.
- Each proposed target must avoid denied paths.
- Each target must have a reason tied to either the doc diff or fix intent.
- `fix` plans must not target documentation files in the MVP.
- High-risk plans and plans with questions require explicit user attention before approval.

The approved plan is frozen as `plan.approved.json`.

### Implementation phase

Purpose: implement exactly the approved plan in the temporary worktree.

Implementation input includes:

- approved plan;
- original task packet;
- DetDoc rules;
- allowed target paths;
- instruction to stop and request plan expansion if a new target is needed.

Tools:

- `read`, `grep`, `find`, `ls`;
- `edit`/`write` guarded by approved target paths and deny paths;
- `bash` for configured or necessary local commands, subject to path and command policy.

The MVP should guard write-capable tools at the DetDoc/pi boundary. Even if pi attempts an unauthorized write, the tool call should be blocked. Post-validation still checks the final patch independently.

## Reproducibility Model

DetDoc's reproducibility guarantee is patch replay, not LLM rerun determinism.

For each accepted run, DetDoc stores:

```text
.detdoc/runs/<run-id>/
  manifest.json
  input.diff.md          # for detdoc run
  intent.md              # for detdoc fix
  config.snapshot.yml
  plan.proposed.json
  plan.approved.json
  changes.patch
  validation.log
  run.log
```

`manifest.json` contains:

- `runId`
- `mode`: `run` or `fix`
- `baseCommit`
- `baseTreeHash`
- `inputHash`
- `configHash`
- `createdAt`
- `docGlobs`
- `ignoredPaths`
- `validationCommands`
- `agent`: `pi-sdk`
- pi model and thinking settings when configured
- `approvedTargets`
- touched file hashes before and after the patch

### `detdoc replay <run-id>`

Replay flow:

1. Read `manifest.json` and `changes.patch`.
2. Verify current `HEAD` equals `baseCommit`, unless an explicit future override is added.
3. Verify preimage hashes for touched files.
4. Apply the patch.
5. Run configured validation commands.
6. Write replay logs.

### `detdoc apply <run-id>`

Apply is for runs where a patch exists but has not been applied to the main working tree. It reads `changes.patch`, checks preconditions, asks for confirmation, and applies the patch.

## Validation

Validation has two layers.

### Structural checks

- Patch must apply cleanly to the expected base.
- Patch must not touch denied paths.
- Patch must touch only approved target files, unless the user approved an expanded plan.
- `detdoc fix` patches must not modify documentation files in the MVP.
- Generated artifacts under `.detdoc/runs/` must not be included in the code patch.
- Touched file hashes must match manifest expectations.

### Configured commands

DetDoc runs commands from `.detdoc/config.yml` in the temporary worktree after implementation and before final approval.

Examples:

- `npm test`
- `npm run typecheck`
- `cargo test`
- `ruff check .`

Validation output is saved to `validation.log`.

## Error Handling and Rollback

- If not in a git repository, every command except `init` fails with a clear error.
- If `run` sees dirty non-doc changes, it fails before creating a worktree.
- If `fix` sees dirty non-doc changes, it fails before creating a worktree.
- If a temporary worktree cannot be created, the run is marked failed and logs are saved.
- If the documentation patch cannot be applied to the temporary worktree, the run is marked failed.
- If pi returns invalid structured output, DetDoc saves raw output and stops before implementation.
- If implementation attempts unauthorized paths, the tool call is blocked and the run fails unless the user approves an expanded plan in a future version.
- If validation commands fail, DetDoc shows logs and preserves the worktree when `keepOnFailure` is true.
- If the final patch cannot be applied to the main working tree, DetDoc leaves the patch in artifacts and suggests `detdoc apply <run-id>` after cleanup.

## Testing Strategy

Most tests should use fixture git repositories and a fake `AgentRunner`.

Test areas:

- Config parsing and defaults.
- Documentation glob matching.
- Normalized Markdown diff generation.
- Dirty-state policy for `run` and `fix`.
- Temporary worktree creation and cleanup.
- Applying doc diffs into temporary worktrees.
- Task manifest generation and stable hashing.
- Planning output validation.
- Approved-target path guards.
- Patch collection.
- Structural validation.
- Configured validation command execution.
- Artifact writing.
- `apply` and `replay` precondition checks.

A smoke test can cover `PiSdkRunner` with a real model, but it should not be part of the default deterministic test suite because it depends on credentials, network, and model behavior.

## Acceptance Criteria

- `detdoc init` creates usable default configuration.
- `detdoc diff` prints a stable normalized Markdown diff.
- `detdoc plan` creates a structured proposed plan without changing files.
- `detdoc run` turns a Markdown diff into an approved, validated patch and applies it only after final approval.
- `detdoc fix "..."` creates an approved, validated bugfix patch without requiring documentation changes.
- Dirty non-documentation changes block both `run` and `fix`.
- `run` allows dirty documentation changes and uses them as input.
- `fix` allows dirty documentation changes but ignores them.
- Every successful run stores artifacts under `.detdoc/runs/<run-id>/`.
- `detdoc replay <run-id>` can apply a saved patch without calling pi when preconditions match.
- Unauthorized paths are blocked both during implementation and during post-validation.
- Configured validation commands run before final patch approval.
