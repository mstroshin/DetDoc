# DetDoc

DetDoc turns Markdown documentation changes (or an explicit bugfix intent) into approved, validated, replayable code changes using embedded pi.

The core flow is:

1. read project docs or fix intent;
2. ask pi for a structured implementation plan;
3. approve the plan;
4. let pi implement only approved target files inside an isolated git worktree;
5. validate the generated patch;
6. optionally apply it to the main worktree;
7. create a git commit and leave the repository clean.

## Commands

```bash
detdoc init
detdoc diff
detdoc plan
detdoc run [--auto-approve] [--auto-apply] [--show-token-usage]
detdoc fix "message to fix"
detdoc apply <run-id>
detdoc replay <run-id>
```

For local development without installing the package globally:

```bash
node /path/to/DetDoc/dist/src/index.js run
```

## Quick start

```bash
npm install
npm run build
```

In a target project:

```bash
node /path/to/DetDoc/dist/src/index.js init
```

`detdoc init` creates:

- `.detdoc/config.yml`
- `.detdoc/runs/.gitkeep`
- starter documentation under `docs/`
- `.gitignore` entries for `.DS_Store` and DetDoc run artifacts

In a clean git repository, DetDoc creates an initial setup commit for DetDoc metadata only. Starter docs remain untracked so you can edit them before committing your product docs.

## Documentation-driven workflow

1. Edit Markdown docs, for example `docs/technical-spec.md` or `docs/features/my-feature/plan.md`.
2. Run:

   ```bash
   detdoc run
   ```

3. Review and approve the structured plan with `y`.
4. DetDoc runs pi inside an isolated worktree and validates the generated patch.
5. Review the validated file list.
6. Choose whether to apply:
   - `y` applies the validated changes, creates `DetDoc apply <run-id>`, and leaves git clean.
   - `n` keeps the run saved under `.detdoc/runs/<run-id>/` without applying.

Non-interactive shortcuts:

```bash
detdoc run --auto-approve              # approve the plan, then stop at apply approval
detdoc run --auto-approve --auto-apply # approve, apply, commit, and leave git clean
```

`--auto-approve` and `--auto-apply` are separate on purpose. Approving a plan does not automatically apply code unless `--auto-apply` is also present.

To inspect pi token usage for a run, add:

```bash
detdoc run --show-token-usage
```

The token usage summary is printed after the run result. `detdoc apply` does not expose this flag because applying a saved patch does not call pi.

## Bugfix workflow

For fixes that should not require a documentation edit:

```bash
detdoc fix "describe the bug and expected behavior"
```

Fix mode uses the same plan/implementation/validation/apply pipeline, but the input is your message instead of a documentation diff.

## Saved runs, apply, and replay

DetDoc stores pending or failed runs under:

```txt
.detdoc/runs/<run-id>/
```

Important files include:

- `manifest.json`
- `plan.proposed.json`
- `plan.approved.json`
- `changes.patch`
- `validation.log`
- `validation-failure-<n>.log` when repair was attempted

Apply a saved run:

```bash
detdoc apply <run-id>
```

`apply` shows progress, applies the saved patch, runs post-apply validation, removes that run's artifacts, commits `DetDoc apply <run-id>`, and verifies `git status --short` is clean.

Replay a saved run:

```bash
detdoc replay <run-id>
```

Replay checks the recorded base commit and preimage file hashes before applying the patch. Replay is for reproducibility/debugging; it keeps run artifacts and does not create the DetDoc apply commit.

## Safety model

DetDoc intentionally narrows what the embedded agent can change.

- Documentation is read-only input. Agent writes to `docs/**` are blocked.
- Plans targeting docs are rejected.
- Generated patches changing docs are rejected.
- Agent write tools are allowed only for approved target paths.
- Paths denied by config are blocked.
- Agent work happens in an isolated git worktree before apply.
- `bash` is allowed in that worktree for diagnostics, generation, builds, and tests.
- Before apply, the patch is validated against the approved target list.

Successful apply merges only the validated patch into the main worktree; unapproved files created in the isolated worktree are not copied into main.

## Validation and repair

Validation commands live in `.detdoc/config.yml`:

```yaml
validation:
  commands:
    - name: xcodegen-generate
      run: xcodegen generate
    - swift test
```

Supported command shapes:

```yaml
validation:
  commands:
    - name: Build
      run: npm run build
    - name: Test
      command: npm test
    - name: Typecheck
      cmd: npm run typecheck
    - npm test
```

DetDoc runs validation in the isolated worktree before apply. After applying to main, it runs validation again so generated artifacts are produced in the main worktree too.

If validation fails and the agent supports repair, DetDoc sends the validation failure back to pi and retries validation. Validation failure logs are saved under the run directory.

## Project-local pi skills

Embedded pi can use project skills from:

```txt
.pi/skills/
.agents/skills/
```

Example:

```txt
.pi/skills/ios-swiftui/SKILL.md
```

```md
---
name: ios-swiftui
description: Use when implementing SwiftUI iOS apps, XcodeGen projects, XCTest, coordinators, or view models.
---

# iOS SwiftUI

Follow the project's SwiftUI architecture and testing conventions.
```

Because DetDoc runs pi inside a temporary git worktree created from `HEAD`, project-local skills must be committed before `detdoc run` if you want the agent to see them.

Pi initially sees only each skill's `name` and `description`; write descriptions that clearly state when the skill should be used.

## Configuration

Project config lives at `.detdoc/config.yml`.

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
  provider: pi-sdk
  model: null
  thinking: high

worktree:
  keepOnFailure: true
```

## Development

```bash
npm install
npm test
npm run typecheck
npm run build
```

The built CLI entrypoint is:

```bash
dist/src/index.js
```
