# DetDoc — hidden doc↔code links

## Problem

After a run implements code from documentation, nothing records *which* code
implements *which* part of the docs. A future agent re-reading the docs has to
re-discover the mapping every time. We want the docs to carry that mapping
directly, hidden by default in the DetDoc viewer, so future agents (and curious
humans) can jump from a doc section to the files/symbols that implement it.

## Constraints (from the existing codebase)

- `PatchValidator` rejects any agent patch touching a doc path (`PATCH_DOC_PATH`).
  → The agent cannot write the links; **DetDoc itself** writes them.
- `DocDiff.normalized` diffs HEAD vs the working tree. → If the links live in the
  **apply commit**, they are committed and do **not** show up as a phantom doc
  change on the next run. (When a human later edits an annotated section, the
  surrounding link lines appear as unchanged *context* in the diff — harmless,
  even useful, to the agent.)
- `PlanChange` records `targetFiles` but no doc-section anchor and no symbols.
  → A correct section→symbol map cannot be derived mechanically; it comes from
  the agent. A guessed map would mislead the very agents this helps, so we pay
  for accuracy.
- The live-preview delegate `textContentStorage(_:textParagraphWith:)` styles and
  hides ranges **per paragraph**. → Single-line HTML comments are trivial to hide
  there; a multi-line block is not.

## Annotation format

One HTML comment per linked section, **single line**, all grouped in a block at
the **end of the doc**:

```
<!-- detdoc:link "## Plan approval" AppCoordinator.swift#approvePlan PlanGateView.swift#PlanGateView -->
<!-- detdoc:link "## Patch gate" AppCoordinator.swift#approveApply -->
```

- `detdoc:link` is the marker.
- The quoted token is the **section anchor**: the exact heading text (with its
  `#`s) the links belong to.
- The rest is a space-separated list of `RelativePath.ext#symbol` refs. Paths are
  repo-relative; `#symbol` is a function/type/method name (no line numbers).

Rationale: HTML comments are invisible to every standard Markdown renderer and to
git-as-prose; single-line means each is its own paragraph (cheap to hide);
grouped at EOF means the "blank line when hidden" artifact lands harmlessly at the
bottom and the prose is left untouched; trivially greppable for agents — the
actual goal. Granularity is file+symbol (line numbers drift and would rot the
links). The block carries only sections the run actually touched.

## Components

### Core (`DetDocCore`)

**`CodeLink` + `CodeLinkBlock`** (new, `Services/CodeLink.swift`)
- `struct CodeLink { var docPath: String; var heading: String; var refs: [String] }`
  — `docPath` is the repo-relative `.md` the link belongs to; `refs` are
  `Path#symbol` strings. (Inside a single `.md` the `docPath` is implicit — it's
  the file the comment lives in — so the in-file serialized line omits it.)
- `CodeLinkBlock.parse(_ markdown:) -> [CodeLink]` — read existing `detdoc:link`
  lines from one `.md` (returns links with `docPath == ""`; caller fills it).
- `CodeLinkBlock.serialize(_:) -> String` — render the comment lines (no docPath).
- `CodeLinkBlock.apply(to markdown:, links:) -> String` — **idempotent**: strip
  every existing `detdoc:link` line, then, if `links` is non-empty, append the
  fresh block (one trailing newline, separated from prose by one blank line).
  Empty `links` → just strips (so a re-run that links nothing cleans up).

**Agent result carries the map.**
- Add `var codeLinks: [CodeLink]` to `AgentRunResult` (default `[]`) — each
  carries its `docPath`, so a single result can span multiple docs.
- The `implement` (and `repair`) prompt asks pi to emit, at the end of its work,
  a fenced ` ```detdoc-links ` block: one `docs/foo.md ## Heading -> Path#symbol, …`
  line per touched section (doc path first). `PiAgentRunner` parses it (mirroring
  the existing structured plan-output parsing) into `[CodeLink]`. `FakeAgentRunner`
  returns `[]`.
- DetDoc uses the `codeLinks` from the last successful implement/repair result.

**Engine write-step** (`DetDocEngine`, in `runInsideWorktree`)
- After the final patch is applied to the **main** worktree and post-apply
  validation passes, **before commit**: group the result's `codeLinks` by
  `docPath`; for each doc that was part of the run's input diff, rewrite it via
  `CodeLinkBlock.apply(to:links:)` and stage it, so the links ride in the same
  `DetDoc apply <run-id>` commit.
- Only docs from the input diff are touched. Links whose `docPath` isn't in the
  input diff are dropped (defensive: keeps the agent from annotating unrelated
  files).

### App (`DetDocApp`)

**Preview hide/show** (`LivePreviewTextView.Coordinator`)
- New `CodeLinkScanner.scan(paragraph) -> [NSRange]` matching a full-line
  `<!-- detdoc:link … -->`.
- Add its result to the early-out check (currently a `detdoc:link`-only line is a
  "plain paragraph" and renders raw — it must go through the delegate).
- `showCodeLinks == false` (default): delete the comment range from the display
  (reuses the existing `modifications` delete path).
- `showCodeLinks == true`: keep it, styled dimmed (secondary color, smaller font).
- No `.link` attribute, no bubble — text only (no navigation).

**Toggle**
- `@AppStorage("showCodeLinks") var showCodeLinks = false`, threaded from the doc
  editor screen into `LivePreviewTextView` (a `Bool` var on the representable; its
  change triggers `updateNSView`, which refreshes paragraphs).
- A toolbar toggle in `DocEditorScreen` labeled "Show code links" with an
  accessibility ID (`toggle-show-code-links`).

## Data flow

```
run → plan → approve → implement (pi emits ```detdoc-links) → collectPatch
   → validate → approveApply → applyPatch(main) → postApplyValidation
   → [NEW] CodeLinkBlock.apply to input-diff docs in main, stage them
   → commit "DetDoc apply <run-id>"  (code + link block together)
```

Viewer: editor renders markdown live; `detdoc:link` lines hidden unless the
toolbar toggle is on.

## Edge cases

- **No links produced** (agent emits nothing / fake runner): write-step strips any
  stale block and otherwise no-ops.
- **Heading not found in doc** (renamed between plan and apply): the link line is
  still written (anchor is just text); next run regenerates from the current
  headings.
- **Repair ran**: use the codeLinks from the final (repaired) result.
- **Doc has a pre-existing block from an earlier run**: `apply` strips it first, so
  no duplication.
- **Non-`.md` docs / docs with no headings**: links keyed by a heading that
  doesn't exist still serialize; viewer shows them at EOF when toggled on. (We do
  not invent anchors.)

## Testing

- `CodeLink` round-trip: parse(serialize(x)) == x.
- `CodeLinkBlock.apply` idempotency: apply twice == apply once; empty links strip
  a prior block; prose above the block is byte-identical.
- Engine: after a fake run that returns links, the committed doc contains the
  block and `git status` is clean; a doc not in the input diff is untouched.
- Preview hide/show: a view-model/coordinator-level check that a `detdoc:link`
  paragraph is removed from the display when off and present when on. (Per
  CLAUDE.md, add SwiftUI Previews for the editor in both toggle states.)

## Out of scope (YAGNI)

- Clickable navigation from a link to the code (chosen: text only).
- A config flag for auto-write (chosen: always on at apply).
- Per-doc toggle (global only).
- Multi-line comment block / line-number granularity.
- A separate dedicated agent round-trip (folded into implement/repair instead).
