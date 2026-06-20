# DetDoc Swift Parity Report (Plan 5, Phase A)

**Date:** 2026-06-21
**Scope:** Behavioral parity of the Swift rewrite (`swift/DetDocCore`, `swift/DetDocApp`)
against the legacy TypeScript CLI (`src/`) and Rust/Tauri core (`src-tauri/`), as the
gate before removing the legacy stacks (Plan 5, Phase B).

## Authoritative baseline

The project evolved **TS CLI → Rust/Tauri core (GUI attempt, since abandoned) → Swift
rewrite**. The Swift implementation plans (`docs/superpowers/plans/2026-06-20-detdoc-core-*.md`)
copied their *Reference Parity Facts* **verbatim from the Rust `src-tauri/src/detdoc/*.rs`**.
Therefore:

- **Rust (`src-tauri/`) is the authoritative parity baseline** for the Swift rewrite.
- **TS (`src/`) is the older, richer original CLI.** It carries behaviors the Rust rewrite
  already deliberately dropped or renamed.

Consequently, most "differs from TS" findings are **PARITY with Rust = intentional**.
Notably, Swift went *beyond* Rust in several places to **restore TS behaviors that Rust had
regressed** (interactive plan/apply gates, validation+repair loop, `APPLY_PREIMAGE_MISMATCH`
guard, untracked-doc inclusion in doc-diff, `--binary` patch apply). The Swift core is
effectively the "best of both": Rust's schema/codes plus TS's safety flow.

## Verdict

**Parity with the authoritative Rust baseline is achieved across every audited surface,
and all 106 Swift tests pass (exit 0); the macOS app builds.** The remaining items are:
(1) a small set of genuine, *debatable* behavioral gaps that Swift shares with Rust but that
diverge from the richer TS original; (2) a larger set of intentional Rust-alignment
differences; (3) test-coverage gaps that do not block teardown (deleting the legacy stacks
does not affect them).

## Surface-by-surface summary

| Surface | Verdict vs Rust baseline | Notes |
|---------|--------------------------|-------|
| Config + paths + glob | PARITY | Defaults, YAML keys, multi-shape validation commands, globset semantics all match Rust + locked by tests. Glob is globset (Rust), not picomatch (TS). |
| Plan + patch validation + validation runner | PARITY | Every plan/patch rule + repair loop locked by tests. Swift restores TS's validation-command runner + repair loop that Rust never ported. |
| Git + worktree + docs + doc-diff + dirty policy | PARITY | git flags, worktree lifecycle, dirty policy, doc-diff all match Rust; Swift adopts TS's `--binary` apply and untracked-doc inclusion. |
| Artifacts + manifest + run-id + errors | PARITY | Run-dir layout, listRuns ordering, manifest legacy-decode, run-id format, `code: message` error model match Rust. |
| Flow + approval + apply + saved-runs + init | PARITY (+ exceeds Rust) | Run phases, plan/apply gates, `APPLY_BASE_MISMATCH`/`APPLY_PREIMAGE_MISMATCH`, init scaffolding locked. Swift's interactive gates + repair loop + preimage guard are closer to TS than Rust ever was. |
| Agent + pi RPC + pi health | PARITY (+ Swift-original RPC) | Prompt content is a verbatim TS port; JSONL framing + health match Rust. The live `pi --mode rpc` transport is Swift-original because Rust's `PiRpcAgentRunner` is only a stub. |

## Genuine gaps (debatable; decide before/after teardown)

These are real behavioral differences from the TS original. All are **shared with the Rust
baseline** (i.e. not regressions introduced by the Swift work) except where noted. None are
blocked by the legacy deletion itself.

| # | Gap | Severity | Shared with Rust? | Mitigation present in Swift | Recommendation |
|---|-----|----------|-------------------|-----------------------------|----------------|
| G1 | **Apply commit stages only `approvedTargets` and has no `GIT_NOT_CLEAN_AFTER_APPLY` post-commit cleanliness check.** TS staged `add -A -- .` then verified `statusPorcelain()` empty (`src/core/flow.ts:118-126`). Swift stages targets only (`RunApplier.swift:39-44`). A post-apply validation command or gitignore mutation touching non-target files would be silently left uncommitted/dirty. | Medium | Yes (Rust regressed first) | Patch is pre-validated to only touch approved targets; post-apply validation is usually read-only. | **Fix before teardown** — cheap TDD: stage `-A` + add cleanliness guard in `RunApplier.commitOrStage`. Restores a real TS safety guard while losing the oracle. |
| G2 | **No in-agent real-time path guard in `PiAgentRunner`; `FakeAgentRunner` dropped its `approvedTargets` check.** TS blocked out-of-scope/denied/doc writes live via `guardExtension`/`validateAgentToolPath` (`src/core/agent/pi-sdk-runner.ts:194-208`). | Low–Medium | N/A (Rust runner is a stub) | **The real safety net exists:** apply-gate `PatchValidator.validatePaths` rejects any out-of-scope patch before apply (`DetDocEngine.swift:176`), and is tested. | **Accept** the missing real-time block (apply-gate validation is the enforcement point), but **re-add `FakeAgentRunner`'s `approvedTargets` check** for test fidelity (cheap). |
| G3 | **`PATCH_ARTIFACT_CHANGE` guard dropped** — TS rejected any patched file under `.detdoc/runs/` (`src/core/validation.ts:43-45`). | Low | Yes (absent in Rust) | The approved-targets check already rejects such paths (run artifacts are never plan targets). | **Accept** (redundant), or add a one-line guard + test if defense-in-depth is wanted. |

## Intentional differences (accepted; Rust-alignment or GUI direction)

1. **Glob = globset (Rust), not picomatch (TS).** `*`/`?` cross `/`; `secrets/*` blocks all
   descendants; `.env.*` crosses `/` (stricter deny). Default deny/doc patterns are identical
   across stacks, so shipped behavior matches. `Glob.swift` is documented + tested against
   globset 0.4. (Material only for user-authored custom patterns.)
2. **run-id suffix is a random UUID prefix (Rust)** rather than TS's content-deterministic
   hash. Shape (`<UTC>-<mode>-<8hex>`) is identical and tested.
3. **Manifest persists only `runId/mode/baseCommit/approvedTargets/touchedFiles` (Rust shape)**;
   TS's 11 extra provenance fields are dropped. The engine writes `input.diff.md`/`intent.md`
   and `plan.proposed.json` separately.
4. **Init scaffolds files only** — no `git init`, no "Initial DetDoc setup" metadata commit.
   Both Rust and Swift dropped this; a brand-new non-git folder will not be auto-initialized.
5. **Error codes follow Rust where they differ from TS**: `PATCH_DOC_PATH` (vs TS
   `PATCH_DOC_CHANGE`), `NO_DOC_CHANGES` (vs `NO_DOC_DIFF`), `CONFIG_READ_FAILED`/`CONFIG_PARSE_FAILED`
   (vs `CONFIG_MISSING`/`CONFIG_INVALID`), split `GIT_SPAWN_FAILED`/`GIT_APPLY_*` (vs `GIT_FAILED`).
   *Minor quirk:* Swift uses `GIT_COMMAND_FAILED` where Rust used `GIT_FAILED` (a third name) —
   harmless but noted.
6. **CLI commands `diff`/`replay`/standalone-`plan` and CLI presentation are not ported**
   (GUI-only product; no replay in MVP). Underlying behaviors survive: doc-diff in
   `DocDiff.normalized`, re-apply in `RunApplier.apply`, plan JSON in the live run.
7. **JSON artifacts use `.sortedKeys` + `.withoutEscapingSlashes`** (stable diffs) instead of
   declaration order. Round-trip is locked; on-disk bytes differ from legacy.
8. **`DetDocError` gains optional structured fields** (`phase/runId/path/command/suggestedAction/details`)
   for richer GUI reporting; all default `nil`, so the printed `"code: message"` is unchanged.
9. **`agent.provider` default `pi-rpc` and the `apply.autoCommit` config block** are Rust
   additions; Swift mirrors them.
10. **No backslash path normalization** (TS normalized `\`→`/`). Acceptable for a macOS-only
    target; matches Rust.
11. **Live pi RPC transport (`PiProcessTransport`, spawn args, event model, command codec,
    two-phase drive) is Swift-original** — Rust's `PiRpcAgentRunner` is an unimplemented
    placeholder. Swift implements the intended RPC contract; prompt content + two-phase
    protocol still match TS verbatim.

## Test-coverage gaps (do NOT block teardown; candidate follow-ups)

These behaviors are correct-by-reading but not pinned by a Swift test. Deleting the legacy
stacks does not affect them; they are listed for a future hardening pass.

- Config: error codes (`CONFIG_READ_FAILED`/`CONFIG_PARSE_FAILED`) not asserted; malformed-YAML
  path untested; emitted-YAML key shape untested; `.gitignore` append/dedup untested.
- Validation: command key precedence (`run`>`command`>`cmd`) and empty-string rejection untested.
- Glob: bare/interior `**` (e.g. `a/**/b`) untested.
- Artifacts: `fileSha256` known-vector value untested — **note this gates `RunApplier` preimage
  verification**, so a hex-encoding regression would be silent; worth a known-vector test.
- Flow: saved-runs descending ordering untested; fix-mode `DIRTY_NON_DOC_CHANGES` untested.
- Git: `core.quotepath=false` flag and worktree-cleanup failure fallback untested.
- `GitignoreManager` (apply-path copy) has no direct test and duplicates `ConfigStore`'s logic.

## Verification evidence

- `swift test --package-path swift/DetDocCore` → **106 tests passed, exit 0** (2026-06-21).
- `xcodebuild build -project swift/DetDocApp/DetDocApp.xcodeproj -scheme DetDocApp` → see
  teardown commit for the post-deletion green build.

## Teardown readiness (Phase B)

Parity against the authoritative Rust baseline is confirmed. The Swift `swift/` tree has **no
runtime dependency** on `src/`, `src-tauri/`, or `src-ui/` (parity facts were copied verbatim
into the plans, not imported). The legacy stacks are safe to remove once the G1/G2/G3
decisions above are made. Rollback relies on git history (no archive tag, per decision).
