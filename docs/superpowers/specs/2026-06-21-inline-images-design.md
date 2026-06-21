# Inline Images in Documentation — Design

Date: 2026-06-21

## Goal

Let the user drag (or paste) an image into the Markdown editor and have it render
inline as a compact preview. Images are stored on disk next to their document and
referenced from Markdown via an `@`-token, consistent with the existing doc-link
tokens.

## On-disk format

### Token

Images are referenced with the same `@`-token syntax as doc links, distinguished
**by file extension**:

```
@guides/assets/window.png
```

- A token whose path ends in a known image extension is an **image ref**.
- Recognized extensions: `png`, `jpg`, `jpeg`, `gif`, `heic`, `webp` (case-insensitive).
- The path is **docs-root-relative**, exactly like doc links — it resolves against
  `<root>/docs/`. So `@guides/assets/window.png` → `<root>/docs/guides/assets/window.png`.

### File location

Dragged/pasted image files are copied into an `assets/` folder **next to the
document** being edited:

| Document | Assets folder | Example token |
| --- | --- | --- |
| `docs/guides/setup.md` | `docs/guides/assets/` | `@guides/assets/window.png` |
| `docs/idea.md` (docs root) | `docs/assets/` | `@assets/window.png` |
| `docs/features/auth/brief.md` | `docs/features/auth/assets/` | `@features/auth/assets/flow.png` |

### File naming

- **File drag from Finder:** keep the original filename. On collision in the target
  `assets/` folder, append `-1`, `-2`, … before the extension.
- **Paste / data drag (no filename):** generate `image-<yyyyMMdd-HHmmss>.png`; on
  collision append `-1`, `-2`. Raster pasteboard data (TIFF/PNG) is encoded to PNG.

## Components

### Core (`DetDocCore`) — filesystem + parsing, unit-tested

1. **`ImageRef` + `ImageRefScanner`** (`Services/ImageRef.swift`)
   - `ImageRef { range: NSRange; path: String }` — `range` covers `@<path>`
     (including the `@`); `path` is the docs-relative path **with** extension.
   - `ImageRefScanner.scan(_:) -> [ImageRef]` — finds `@<path>` tokens at a word
     boundary (same boundary rule as `DocRefScanner`) whose path ends in an image
     extension. Trailing punctuation is trimmed like `DocRefScanner` does.
   - `ImageRef.imageExtensions: Set<String>` — the shared extension list.

2. **`DocRefScanner` change** (`Services/DocRef.swift`)
   - After matching a token, if its path ends in an image extension, **skip it** so
     image tokens are not mis-treated as broken doc links. (Image tokens are owned by
     `ImageRefScanner`.)

3. **`DocImageImporter`** (`Services/DocImageImporter.swift`, `Sendable`)
   - `init(root: URL)`.
   - `importFile(at sourceURL: URL, forDoc docPath: String) throws -> String`
     — copies the file into the doc's `assets/` folder (deduping the name) and
       returns the docs-relative token path (e.g. `guides/assets/window.png`).
   - `importData(_ data: Data, basename: String, ext: String, forDoc docPath: String) throws -> String`
     — writes the bytes into the doc's `assets/` folder and returns the token path.
       The caller supplies `basename` (e.g. `image-20260621-143000`) — keeping the
       clock out of core makes this deterministically testable; the importer owns
       only collision deduping. `ext` defaults to `png`.
   - `resolve(_ tokenPath: String) -> URL?` — returns the absolute file URL for a
     token path **iff** the file exists on disk (used for rendering + existence check).
   - Errors surface as `DetDocError` (`IMAGE_IMPORT_FAILED`).
   - Helper: `assetsTokenPrefix(forDoc:)` computes the doc-relative `…/assets`
     segment from a `docs/...md` path.

### App (`DetDocApp`)

4. **`DocImageBubble.swift`** (`Workspace/Docs/`)
   - `DocImageAttachment: NSTextAttachment` — holds the resolved image `URL` and an
     `onOpen: () -> Void` closure. Mirrors `DocLinkBubbleAttachment`'s Swift 6
     isolation pattern (`nonisolated(unsafe)` closure, `@MainActor init`).
   - `DocImageProvider: NSTextAttachmentViewProvider` — loads the image from the URL,
     renders a **compact preview ~120 px tall** (width by aspect, capped to the line
     fragment width), wrapped in `NSHostingView`. Tap → `onOpen()` (Quick Look).
     Reuses the `MainThreadOnly` bridging pattern from `DocLinkBubble`.
   - A broken/missing file renders a red placeholder capsule ("missing image").

5. **`LivePreviewTextView` change** (`Workspace/Docs/LivePreviewTextView.swift`)
   - In `textContentStorage(_:textParagraphWith:)`, after doc refs, scan the
     paragraph with `ImageRefScanner`:
     - If the caret is **inside** the image token → leave the raw `@…png` text
       (so the user can select/delete it), styled subtly (link color).
     - If the caret is **outside** and the file resolves → replace the token range
       with a `DocImageAttachment` preview.
     - If the file does not resolve → red dotted styling + tooltip (mirrors broken
       doc-link handling); no attachment.
   - Image-token boundary crossings extend the existing caret-paragraph refresh in
     `linkRange(atCaret:)`/`textViewDidChangeSelection` so previews collapse/reveal
     on caret movement just like link bubbles. (Generalize `linkRange` to also match
     image tokens, or add a parallel `imageRange`.)
   - The view needs a way to resolve a token → URL: the SwiftUI screen passes a
     `resolveImageURL: (String) -> URL?` closure (backed by `DocImageImporter.resolve`),
     alongside the existing `resolver`/`candidatesProvider`.

6. **`ImageDropTextView: NSTextView`** (`Workspace/Docs/`)
   - `NSTextView.scrollableTextView()` is replaced by a scroll view hosting this
     subclass (or the subclass is installed in `makeNSView`).
   - Registers dragged pasteboard types: file URLs, TIFF, PNG.
   - `performDragOperation(_:)` — if the drag carries image file URL(s) or raster
     data, import via `DocImageImporter` (using the editor's current doc path),
     insert the token(s) at the drop character index, consume the drop. Otherwise
     fall through to `super` (default text behavior).
   - `paste(_:)` — if the pasteboard holds image data (and no useful text), import
     and insert at the caret; otherwise `super.paste`.
   - Insertion places each token on **its own line** (prepend `\n` if not at line
     start, append `\n` if not at line end), then routes the edit through the
     coordinator so `editor.edit()` runs and the paragraph re-renders.

7. **Quick Look** — `QLPreviewPanel.shared()` driven by a small data source (the
   coordinator or a dedicated controller) that returns the tapped image URL.
   Triggered from the attachment's `onOpen` closure.

## Data flow

```
drag / paste image
  → ImageDropTextView intercepts (image UTType present)
  → DocImageImporter.importFile/importData → writes <root>/docs/<dir>/assets/<name>
  → returns token path "<dir>/assets/<name>"
  → insert "\n@<token>\n" at drop point / caret
  → coordinator → editor.edit(newText)  (marks dirty)
  → NSTextContentStorage re-renders the changed paragraph
  → ImageRefScanner finds the token → DocImageProvider shows ~120px preview
tap preview → onOpen → QLPreviewPanel shows full-size
save → existing DocsService.write (unchanged)
```

## Edge cases

- **Missing/broken file:** red dotted token text + tooltip; no preview attachment.
- **Caret inside token:** raw text revealed for editing/deletion.
- **Non-image drag/paste:** default `NSTextView` behavior (fall through to `super`).
- **Multiple images in one drop:** import each; insert tokens separated by newlines.
- **Name collision:** dedupe with `-1`, `-2` suffix before the extension.
- **Unsupported image extension:** not recognized as an image token (stays plain
  text / treated by doc-ref rules); only the listed extensions render.

## Testing

**Core (unit, `TempDir` fixtures):**
- `ImageRefScanner`: recognizes each image extension; word-boundary rule; trailing
  punctuation trimming; ignores non-image `@`-tokens; case-insensitive extensions.
- `DocRefScanner`: now **excludes** image-extension tokens (regression: a `.png`
  token is not reported as a doc ref).
- `DocImageImporter`: `importFile` copies + dedupes; `importData` writes PNG with a
  generated name; token-path computation for docs at root vs nested; `resolve`
  returns URL when present and `nil` when missing; error on unwritable target.

**App:** drag/paste interception, attachment rendering, and Quick Look are verified
manually — the testable logic lives in core, and the app layer stays thin.

## Out of scope (YAGNI)

- Resizing/cropping images in-editor.
- Captions / alt text UI (the token carries only the path).
- Remote (http) image URLs.
- Standard Markdown `![]()` interop (deliberately using `@`-tokens for consistency
  with doc links).
