# Drag Image Preview Between Lines — Design

Date: 2026-06-21

## Goal

Let the user grab an inline image preview with the mouse and drag it to a different
line (above or below) in the document. The image token relocates to the chosen line
boundary. Builds directly on the inline-images feature (same branch).

## Interaction

- The image preview (an `NSHostingView` attachment inside the editor's `NSTextView`)
  gets two AppKit gesture recognizers:
  - **Click** (no movement) → Quick Look (the existing behavior).
  - **Pan** (movement past a ~4 pt threshold) → enter move mode.
- The existing SwiftUI `.onTapGesture` on `DocImageView` is REMOVED — all input on the
  preview is handled in AppKit, so click vs. drag is distinguished by movement and
  the two gestures cannot conflict.
- During a pan:
  - The dragged preview stays in place, dimmed (`alphaValue ≈ 0.4`).
  - A thin horizontal insertion indicator (accent color, ~2 pt tall, spanning the
    text content width) is drawn at the target line boundary and follows the cursor.
  - On release, the image's token line moves to that boundary. Dropping on the
    image's own line (or inside its own paragraph) is a no-op.
- A cancelled pan restores alpha, removes the indicator, and leaves text untouched.

The image stays block-level: it always lands on its own line at a paragraph boundary.

## Components

### Core (`DetDocCore`) — pure move logic, unit-tested

**`ParagraphMover`** (`Services/ParagraphMover.swift`):
- `static func move(in text: String, lineContaining sourceIndex: Int, toBoundary target: Int) -> Move?`
- `struct Move { let text: String; let caret: Int }`
- Behavior:
  - The source line is `paragraphRange(for:)` of `sourceIndex` — for an image token
    on its own line this is `@token\n` (or `@token` if it is the last line).
  - Removes the source line and re-inserts it at `target` (a paragraph-start index in
    the ORIGINAL `text`), keeping the moved line on its own line (normalize newlines:
    ensure a single trailing newline; prepend one if landing at end-of-text without a
    preceding newline). Mirrors the own-line invariant used by `insertImageTokens`.
  - Index adjustment: when `target > sourceLine.location`, the post-removal insertion
    point shifts left by the removed length.
  - Returns `nil` when the move is a no-op: `target` falls within the source line
    range, or the resulting text equals the input.
  - `caret` is the character offset at the start of the moved line in the new text.

### App (`DetDocApp`)

**`DocImageDragController`** (`Workspace/Docs/DocImageDragController.swift`, `@MainActor`):
- Created per preview in `DocImageProvider.loadView`; retained by the provider.
- Inputs at creation: the hosting `NSView`, `onOpen: () -> Void`, the source token's
  backing character index, and the `DocEditorViewModel`.
- Installs an `NSClickGestureRecognizer` (→ `onOpen`) and an `NSPanGestureRecognizer`
  (→ move) on the hosting view.
- Resolves the enclosing `NSTextView` by walking the hosting view's ancestors at
  gesture time.
- Owns a thin `NSView` insertion-indicator overlay added to the text view.
- Pan handling:
  - `.began`: capture source line via `paragraphRange(for: sourceIndex)`; dim hosting
    view.
  - `.changed`: `target = textView.characterIndexForInsertion(at: panPoint)` snapped to
    its paragraph start; position the indicator using
    `textView.firstRect(forCharacterRange: NSRange(location: target, length: 0))`
    (converted screen → view coordinates).
  - `.ended`: call `ParagraphMover.move(...)`; if non-nil, apply via
    `textView.shouldChangeText` + `replaceCharacters(in: fullRange)` (one undo step) +
    `didChangeText`, set the caret to `move.caret`, then `editor.edit(textView.string)`.
    Remove indicator, restore alpha.
  - `.cancelled`/`.failed`: remove indicator, restore alpha, no text change.

**`DocImageBubble.swift`** (modified):
- Remove `.onTapGesture` from `DocImageView` (it becomes a passive view; tap handled by
  the controller).
- `DocImageProvider`: compute the source backing index from its `location`
  (`contentStorage.offset(from: documentRange.location, to: location)`); in `loadView`,
  build the `DocImageDragController` with `onOpen`, the source index, and `editor`, and
  retain it.
- The attachment (`DocImageAttachment`) carries `editor` (or the source index path) so
  the provider can construct the controller. Bridged through the same Swift 6 idiom as
  `onOpen` (`nonisolated(unsafe)` / `MainThreadOnly`).

**`LivePreviewTextView.swift`** (modified):
- When building a `DocImageAttachment` in the content-storage delegate, pass the
  `editor` (already on the Coordinator) so the preview can drive a move.

## Data flow

```
pan begins on preview
  → controller resolves enclosing NSTextView; captures source line from backing index; dims preview
  → .changed: panPoint → characterIndexForInsertion → snap to paragraph start → move indicator
  → .ended: ParagraphMover.move(in: tv.string, lineContaining: srcIndex, toBoundary: target)
       → replaceCharacters(fullRange) [one undo step] → set caret → editor.edit(tv.string)
       → content-storage re-renders → token now on the new line
  → indicator removed, alpha restored
click (no movement) → onOpen → Quick Look (unchanged)
```

## Edge cases

- Drop on the source's own line / inside its paragraph → no-op (`ParagraphMover` returns nil).
- Image is the last line (no trailing `\n`) → normalized so it stays its own line.
- Cancelled pan → indicator removed, alpha restored, text untouched.
- Click without movement → Quick Look, no move.
- Multiple tokens with the same path → source identified by backing `location`, not by
  path, so the correct instance moves.

## Testing

- **Core (unit):** `ParagraphMover` — move down, move up, move to top, move to bottom,
  last-line-without-newline, no-op when target inside source, no-op when unchanged,
  caret position correctness.
- **App:** gesture recognition, dim/indicator drawing, coordinate math, and the
  click-vs-drag distinction are verified manually (UI); the testable string transform
  lives in core.

## Out of scope (YAGNI)

- Dragging a ghost image that follows the cursor (chose in-place dim + indicator).
- Dropping an image inline within a text line (images stay block-level / own-line).
- Horizontal reordering or multi-image drag.
- Reordering arbitrary non-image paragraphs (the gesture is only on image previews,
  though `ParagraphMover` is generic).
