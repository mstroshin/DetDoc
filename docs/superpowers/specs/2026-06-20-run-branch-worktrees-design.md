# DetDoc Run Branch Worktrees Design

## Summary

DetDoc currently creates implementation worktrees as detached temporary directories under the OS temp directory. This keeps the main checkout clean, but makes generated changes hard to inspect at the final apply prompt. Change run/fix implementation worktrees to be visible, project-local Git worktrees with a branch named exactly like the DetDoc run id.

For a run id such as `20260620T121500Z-run-abcdef12`, DetDoc will create:

```txt
.worktrees/20260620T121500Z-run-abcdef12/
branch: 20260620T121500Z-run-abcdef12
```

This lets users inspect the generated code while DetDoc is waiting at `Apply these validated changes and create a commit? [y/N]:`:

```bash
cd .worktrees/20260620T121500Z-run-abcdef12
git status
git diff
```

## Goals

- Make generated worktree changes inspectable with normal Git commands before the final apply/reject decision.
- Name the branch exactly the same as the run id.
- Place the worktree under `.worktrees/<run-id>` so it is easy to find.
- Preserve the existing safety model: only the validated patch is applied to the main worktree.
- Clean up both the temporary worktree and its branch after the user answers the final apply prompt, whether the answer is yes or no.
- Preserve `worktree.keepOnFailure` for failures before normal completion.

## Non-goals

- Do not make DetDoc merge from the run branch into main. Main still receives only the validated patch.
- Do not keep successful or rejected run worktrees around after the final prompt.
- Do not change `detdoc apply <run-id>` saved-run behavior; saved apply still reads `.detdoc/runs/<run-id>/changes.patch` and does not recreate the implementation worktree.
- Do not introduce a new user-facing configuration option for worktree location in this change.

## Architecture

Extend `WorktreeManager.createFromHead` so callers can provide a branch name and project-local location. `runFlow` already creates the manifest before the worktree, so it can pass `manifest.runId` as the branch and directory name.

The worktree lifecycle will become:

1. Create `.worktrees` if needed.
2. Create a Git worktree from the base commit using a new branch named `<run-id>`:
   ```bash
   git worktree add -b <run-id> .worktrees/<run-id> <base-commit>
   ```
3. Run the existing DetDoc pipeline inside that worktree.
4. At the final apply prompt, the worktree remains available for inspection.
5. On normal completion:
   - remove the linked worktree;
   - delete branch `<run-id>`.
6. On failure:
   - if `worktree.keepOnFailure` is true, keep the worktree and branch for debugging;
   - otherwise remove the worktree and delete the branch.

## Data Flow

The main worktree remains the source of truth for the base commit and run artifacts. The branch worktree is only the isolated implementation environment.

`run` mode:

1. Collect documentation diff from main.
2. Create run manifest and artifacts.
3. Create `.worktrees/<run-id>` on branch `<run-id>` from `manifest.baseCommit`.
4. Apply the documentation diff to the run worktree.
5. Run planning, implementation, validation, and optional validation repair in the run worktree.
6. Collect the validated patch from the run worktree and save it to `.detdoc/runs/<run-id>/changes.patch`.
7. Ask for apply approval while the worktree is still present.
8. If approved, apply the saved validated patch to main and commit.
9. Always clean up the run worktree and branch on normal completion.

`fix` mode follows the same lifecycle but skips applying a documentation diff.

## Error Handling

- If `.worktrees/<run-id>` already exists, worktree creation should fail with a clear DetDoc error. Run ids include timestamp and hash, so collisions should be rare and usually indicate stale state.
- If branch `<run-id>` already exists, worktree creation should fail with a clear DetDoc error rather than reusing or overwriting the branch.
- Cleanup should first remove the worktree with `git worktree remove --force <path>`.
- After worktree removal, cleanup should delete the branch with `git branch -D <run-id>`.
- Cleanup should be best-effort in `finally`; a failure to delete the branch should not hide the original run failure, but should be visible when cleanup itself is the only failure.
- When `worktree.keepOnFailure` is true and the run fails before normal completion, DetDoc should leave both `.worktrees/<run-id>` and branch `<run-id>` intact for debugging.

## User Experience

Progress output remains mostly unchanged. The final apply box should include the worktree path so users know where to inspect changes, for example:

```txt
Inspect worktree: .worktrees/20260620T121500Z-run-abcdef12
```

The apply approval context therefore needs an optional `worktreePath` field. Terminal approval can display it when present. Tests should cover that the prompt includes the inspect path.

## Testing

Add and update tests to cover:

- `WorktreeManager` creates a branch worktree under a caller-provided path and branch name.
- The branch is named exactly like the run id.
- Cleanup removes both the worktree directory and the branch.
- `runFlow` creates the worktree under `.worktrees/<run-id>`.
- During apply approval, the worktree still exists and contains the generated diff.
- Rejecting apply saves run artifacts but cleans up `.worktrees/<run-id>` and deletes the branch.
- Existing apply/replay behavior remains unchanged.

## Documentation

Update the README safety/apply sections to explain that generated changes can be inspected before final apply with:

```bash
cd .worktrees/<run-id>
git diff
```

Also document that the worktree and branch are cleaned up after answering the apply prompt, and that failed runs may keep them when `worktree.keepOnFailure` is enabled.
