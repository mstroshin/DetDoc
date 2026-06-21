# Design: Cross-document references via `@` (live-preview editor)

## Goal

Let a Markdown document reference another doc. Typing `@` in the editor opens an
interactive picker of `docs/` files; choosing one inserts a standard Markdown
link `[name](path.md)`. References render as styled, clickable links inline;
clicking opens the target document; links to missing files are visibly marked.

Reaching this requires replacing the current plain-`TextEditor` + separate
preview with a **single live-preview editing surface** built on TextKit 2 /
`NSTextView`. That surface is also the chosen foundation for two explicitly
planned future features — **inline images** (drag a picture into the doc, shown
in place) and an **embedded drawing canvas** — so the framework choice is made
with those in mind, even though they are out of scope here.

## Current state

`DocEditorScreen` renders an `HStack` of a plain SwiftUI `TextEditor`
(bound through `DocEditorViewModel.edit`) and a hand-rolled `MarkdownPreview`
that styles text line-by-line via `AttributedString(markdown:)`.
`DocEditorViewModel` owns `source` / `isDirty` / `selectedPath` and wraps
`DocsService` (`read`/`write`). `DocsService.list()` enumerates policy-allowed
`docs/**.md` files as `DocFile { path, title }` with `path` like
`docs/guides/setup.md`. `DocsTreeViewModel` drives the sidebar and the
`selectedDoc` binding in `WorkspaceView` opens a file in the editor.

Plain `TextEditor` cannot expose the caret rectangle, intercept keystrokes, or
locate the token under the cursor — all required for an `@` completion popover —
which is the technical reason for the editor replacement.

## Locked decisions

- **Trigger:** `@` opens the picker; stored form is standard Markdown
  `[name](path.md)`. `@` itself is never stored.
- **Link text:** the target's file name without `.md` → `[setup](guides/setup.md)`.
- **Path base:** relative to the `docs/` root (not relative to the current file).
- **Navigation:** clicking a reference opens the target in the editor and selects
  it in the tree; links to missing files are highlighted.
- **Editor model:** one live-preview surface (Obsidian "Live Preview" style) —
  edit Markdown, but links/images/canvas render inline. The separate preview
  pane is retired.
- **Picker visual:** compact inline popover with Liquid Glass; selection is a
  tinted-glass capsule; light and dark. (Mockups produced during design.)

## Framework stack

- **TextKit 2 over `NSTextView`**, wrapped in an `NSViewRepresentable`. Mature
  text editing (selection, undo, IME, find); exposes the caret rect
  (`NSTextLayoutManager` / `firstRect(forCharacterRange:)`) and key interception
  (`doCommand(by:)`) needed for the picker; and — via
  `NSTextAttachmentViewProvider` — can host live `NSView`s inline, which is how
  future images and the drawing canvas embed in the same surface.
- **`swift-markdown`** (Apple, cmark-gfm) added to `DetDocCore` for a real AST:
  extracting links/images, resolving targets, and source-range-driven inline
  styling. Replaces the current naive line renderer.
- **Future canvas:** a SwiftUI `Canvas` / custom `NSView` drawing view embedded as
  a TextKit attachment (PencilKit is UIKit/Catalyst-only and this is a pure
  AppKit app, so it is not used). Out of scope here; noted for foundation fit.
- **Liquid Glass** (`.glassEffect`) for the picker popover. Note: `.glassEffect`
  does not render under offscreen `ImageRenderer`; visual verification is by
  capturing a live window.

## Architecture

Follows the app convention: pure, filesystem-light logic in `DetDocCore` with
fast unit tests; `@MainActor @Observable` view models; thin views. The
`NSViewRepresentable` is kept thin — all decisions live in pure functions and the
view model so they are testable without UI.

### Core (`DetDocCore`, pure)

```swift
// A doc that can be linked to.
public struct DocCandidate: Equatable, Sendable {
    public let name: String              // file name without ".md": "setup"
    public let docsRelativePath: String  // "guides/setup.md" (docs/ stripped)
    public let title: String?            // first H1, if any (for display/search)
}

public struct ActiveQuery: Equatable, Sendable {
    public let range: NSRange            // the "@query" span (incl. '@'), UTF-16
    public let query: String            // text after '@'
}

public enum DocLinkCompletion {
    /// The active "@query" token ending at `cursorUTF16Offset`, or nil.
    /// '@' triggers only at a word boundary (start of text or after whitespace).
    /// Query chars: letters, digits, and / - _ . ; whitespace/newline ends it.
    public static func activeQuery(in source: String, cursorUTF16Offset: Int) -> ActiveQuery?

    /// Filter + rank candidates for a query (case-insensitive substring over
    /// docsRelativePath and title; prefix matches rank first; empty query = all).
    public static func suggestions(query: String, candidates: [DocCandidate]) -> [DocCandidate]
}

public enum DocLink {
    public static func make(name: String, docsRelativePath: String) -> String  // "[setup](guides/setup.md)"
    /// docs-relative target if `destination` is an internal .md link, else nil.
    public static func internalTarget(ofDestination destination: String) -> String?
}

public struct DocLinkResolver: Sendable {
    public init(candidates: Set<String>)            // set of docs-relative paths that exist
    public func resolve(_ destination: String) -> Resolution?   // nil if not an internal .md link
    public struct Resolution: Equatable, Sendable {
        public let docsRelativePath: String          // "guides/setup.md"
        public let docPath: String                   // "docs/guides/setup.md" (for editor.open)
        public let exists: Bool
    }
}
```

`DocsService` gains a small helper to produce candidates (name/title/docs-relative
path) so the App layer does not re-derive path math:

```swift
// DocsService
public func candidates() -> [DocCandidate]   // from list(): strip "docs/", drop ".md", read H1 title
```

swift-markdown is used to extract link/image destinations with their source
ranges (for styling and broken-link detection). Title extraction reads the first
`# ` heading.

### App (`DetDocApp`)

- **`LivePreviewTextView`** — `NSViewRepresentable` + `Coordinator` over a
  TextKit 2 `NSTextView`:
  - Two-way binds `DocEditorViewModel.source`; preserves dirty/save.
  - Applies live inline styling from the parsed document: headings, bold/italic,
    bullets, and links rendered as styled runs. A link shows its rendered `name`
    unless the caret is inside it, where it reveals the raw `[name](path)` for
    editing (the live-preview behavior).
  - Internal links are resolved through `DocLinkResolver`: existing → accent
    styled; missing → "broken" styling (e.g. red, dotted underline).
  - **Cmd-click** on an internal link follows it (plain click places the caret);
    following calls back to open + select the target. Missing target → no-op.
  - Hosts `@` completion: on text change it calls `DocLinkCompletion.activeQuery`,
    drives `DocLinkCompletionModel`, positions the popover at the caret rect, and
    routes ↑/↓/↵/esc to the model while it is active.
  - Foundation hooks for future attachments (images/canvas) via
    `NSTextAttachmentViewProvider` — not implemented here.

- **`DocLinkCompletionModel`** (`@MainActor @Observable`):

  ```swift
  var isActive: Bool
  var query: String
  var items: [DocCandidate]
  var selectedIndex: Int
  var caretRect: CGRect          // in the text view's coordinate space
  func begin(_ q: ActiveQuery, caretRect: CGRect, candidates: [DocCandidate])
  func update(_ q: ActiveQuery, caretRect: CGRect, candidates: [DocCandidate])
  func moveUp(); func moveDown()
  func commit() -> Insertion?    // replacement text + target range, or nil if empty
  func cancel()
  ```

  `Insertion = { text: String, range: NSRange }` — the `[name](path)` and the
  `@query` span it replaces. The coordinator applies it to the text view.

- **`DocLinkSuggestionsView`** — the Liquid Glass popover (per the mockups):
  one row per candidate (doc icon + docs-relative path, matched prefix
  highlighted), selected row a tinted-glass capsule, empty state when no matches.
  Hosted in a child `NSWindow`/popover anchored at `caretRect`.

- **`DocEditorViewModel`** stays the source of truth (`source`/`isDirty`/`save`).
  Adds `openLinkedDoc(docsRelativePath:)` that maps to a `docs/…` path and reuses
  `open`, plus a callback so `WorkspaceView` syncs `selectedDoc` (and the tree
  selection) when a link is followed.

- `DocEditorScreen`'s `HStack` and `MarkdownPreview` are retired; the detail pane
  hosts `LivePreviewTextView` directly.

## `@` completion flow

1. User types `@` at a word boundary; the coordinator's text-change handler calls
   `DocLinkCompletion.activeQuery`. A non-nil result starts the picker:
   `DocLinkCompletionModel.begin` with candidates from `DocsService.candidates()`
   and the caret rect.
2. Each subsequent keystroke updates `query`/`items`; the popover follows the
   caret. ↑/↓ move the selection; the row preview matches the mockups.
3. **↵** commits: `commit()` returns the `[name](path)` insertion and its target
   range; the coordinator replaces the `@query` span, registers one undo group,
   and dismisses.
4. **esc**, a space/newline, deleting past `@`, or losing focus cancels.
5. Empty result set → popover shows an empty state; ↵ does nothing.

## Navigation & broken links

- On parse, every internal `.md` link destination is resolved via
  `DocLinkResolver` against the current `DocsService.candidates()` set.
- Existing → accent link styling; Cmd-click opens the target (`editor.openLinkedDoc`
  → `WorkspaceView` updates `selectedDoc`, tree reveals/selects it).
- Missing → broken styling; Cmd-click is a no-op (no crash). A help tooltip names
  the missing path.

## Conventions

- **Path base:** `docs/`-relative throughout. Candidate paths strip the `docs/`
  prefix; resolution re-adds it for `editor.open`.
- **Assets (future):** dropped images / canvas exports live under `docs/assets/`,
  referenced docs-relative. Reserved now; not created here.

## Error handling / edge cases

- `@` inside a word or address (`a@b`) does not trigger (word-boundary rule).
- Query terminates on whitespace/newline; allowed chars are letters/digits and
  `/ - _ .`.
- Programmatic insertion is a single undoable edit and keeps `isDirty` correct.
- Broken/stale links never crash; following a missing target is a no-op.
- Large documents: restyle only changed/visible ranges to avoid full re-layout
  on each keystroke.
- Opening a link to the already-open doc is a no-op (or re-selects in the tree).

## Testing

- **Core (fast `DetDocCoreTests`):**
  - `DocLinkCompletion.activeQuery`: trigger at start/after whitespace; no trigger
    mid-word/in email; query stops at whitespace; allowed punctuation; cursor at
    token end; multibyte/Cyrillic offsets.
  - `DocLinkCompletion.suggestions`: substring + prefix ranking, empty query,
    no-match.
  - `DocLink.make` / `internalTarget`: link text/format; internal vs external
    (`http(s)://`, anchors) detection.
  - `DocLinkResolver.resolve`: existing vs missing; non-`.md` ignored; docs/ path
    mapping.
  - `DocsService.candidates`: docs/ stripping, `.md` dropping, H1 title, policy.
- **App (`DetDocAppTests`):** `DocLinkCompletionModel` transitions
  (begin→update→move→commit/cancel), `commit()` insertion text/range, empty-set
  behavior; `DocEditorViewModel.openLinkedDoc` selection sync.
- **`LivePreviewTextView`** stays thin; styling/popover verified manually and by
  live-window screenshot (Liquid Glass cannot be snapshot offscreen).

## Implementation phases (for the plan)

1. **Live-preview surface.** Replace the split editor with `LivePreviewTextView`
   (TextKit 2). Adopt `swift-markdown`. Inline styling of existing Markdown;
   links styled + resolved; Cmd-click navigation; broken-link styling. No `@`.
2. **`@` picker.** `DocLinkCompletion` + `DocLinkCompletionModel` +
   `DocLinkSuggestionsView` (Liquid Glass); caret anchoring, key handling,
   insertion; light/dark.
3. **Polish.** Word-boundary/dismissal rules, empty state, broken-link tooltip,
   test hardening, performance (incremental restyle).

## Out of scope (YAGNI) — foundation-ready

- **Inline images** (drag-drop → `![alt](assets/…)`, attachment rendering).
  Next feature; the TextKit surface and `docs/assets/` convention are chosen for it.
- **Drawing canvas** (embedded interactive attachment; persisted asset +
  `detdoc-drawing` fenced block).
- Full WYSIWYG (hiding Markdown syntax), tables and other rich blocks,
  file-relative link paths, drag-to-reorder.
