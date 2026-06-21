# Drag Image Preview Between Lines — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user drag an inline image preview with the mouse to move the image's token line to another line (above or below), with a live insertion indicator; a plain click still opens Quick Look.

**Architecture:** A pure `ParagraphMover` (core) computes the new document text when a line moves to a paragraph boundary. A `DocImageDragController` (app) installs click (→ Quick Look) and pan (→ move) recognizers on the image preview's hosting view, draws an insertion indicator, and applies the move via the text view. The image token's source line is identified from the attachment's backing `location`.

**Tech Stack:** Swift 6, AppKit (`NSGestureRecognizer`, `NSTextView`, TextKit 2), SwiftUI (`NSHostingView`), Swift Testing. Core = SwiftPM (`swift/DetDocCore`); app = Tuist (`swift/DetDocApp`). Builds on the inline-images feature on branch `feat/inline-images`.

## Global Constraints

- `DetDocCore` builds warnings-as-errors — NO warnings; core tests use Swift Testing (`import Testing`, `@Test`, `#expect`).
- The moved image stays block-level: it always lands on its own line at a paragraph boundary (single trailing newline preserved).
- Source line is the `paragraphRange` of the token's backing index; identification is by backing `location`, NOT by token path (handles duplicate paths).
- A move that changes nothing (target inside the source line, or result == input) is a no-op (`ParagraphMover` returns nil).
- App target uses `buildableFolders: ["Sources"]` — new files are auto-picked up; no `tuist generate` needed unless the `.xcodeproj` is missing.

## Commands

- Core tests (filtered): `swift test --package-path swift/DetDocCore --filter <name>`
- Core tests (all): `swift test --package-path swift/DetDocCore`
- App build (from `swift/DetDocApp`): `xcodebuild build -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS'` (clean build takes minutes — allow a long timeout; trust `xcodebuild` over any stale SourceKit index)

---

### Task 1: ParagraphMover (core)

Pure line-move transform with unit tests.

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Services/ParagraphMover.swift`
- Test (create): `swift/DetDocCore/Tests/DetDocCoreTests/ParagraphMoverTests.swift`

**Interfaces:**
- Produces:
  - `enum ParagraphMover` with `struct Move: Equatable, Sendable { let text: String; let caret: Int }`
  - `static func move(in text: String, lineContaining sourceIndex: Int, toBoundary target: Int) -> Move?`

- [ ] **Step 1: Write the failing tests**

Create `swift/DetDocCore/Tests/DetDocCoreTests/ParagraphMoverTests.swift`:

```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func moveLineDownToBottom() {
    // "A\n@x.png\nB\n" — move the image line to the boundary after B (index 11)
    let m = ParagraphMover.move(in: "A\n@x.png\nB\n", lineContaining: 2, toBoundary: 11)
    #expect(m?.text == "A\nB\n@x.png")
    #expect(m?.caret == 4)
}

@Test func moveLineUpToTop() {
    let m = ParagraphMover.move(in: "A\n@x.png\nB\n", lineContaining: 2, toBoundary: 0)
    #expect(m?.text == "@x.png\nA\nB\n")
    #expect(m?.caret == 0)
}

@Test func targetInsideSourceLineIsNoOp() {
    #expect(ParagraphMover.move(in: "A\n@x.png\nB\n", lineContaining: 2, toBoundary: 2) == nil)
    #expect(ParagraphMover.move(in: "A\n@x.png\nB\n", lineContaining: 2, toBoundary: 5) == nil)
}

@Test func targetAtNextBoundaryIsNoOp() {
    // index 9 is the start of "B\n" — the image is already immediately before it
    #expect(ParagraphMover.move(in: "A\n@x.png\nB\n", lineContaining: 2, toBoundary: 9) == nil)
}

@Test func lastLineWithoutNewlineMovesUp() {
    // image is the last line with no trailing newline
    let m = ParagraphMover.move(in: "L1\n@x.png", lineContaining: 3, toBoundary: 0)
    #expect(m?.text == "@x.png\nL1\n")
    #expect(m?.caret == 0)
}

@Test func emptyTextIsNoOp() {
    #expect(ParagraphMover.move(in: "", lineContaining: 0, toBoundary: 0) == nil)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path swift/DetDocCore --filter moveLine`
Expected: FAIL — `cannot find 'ParagraphMover' in scope`.

- [ ] **Step 3: Implement ParagraphMover**

Create `swift/DetDocCore/Sources/DetDocCore/Services/ParagraphMover.swift`:

```swift
import Foundation

/// Moves a whole line (paragraph) to another paragraph boundary, preserving the
/// moved line's own-line invariant. Pure string transform — no UI dependencies.
public enum ParagraphMover {
    public struct Move: Equatable, Sendable {
        public let text: String
        public let caret: Int
        public init(text: String, caret: Int) { self.text = text; self.caret = caret }
    }

    /// Moves the line containing `sourceIndex` to `target` (a character index in
    /// `text`, snapped by the caller to a paragraph boundary). Returns nil when the
    /// move changes nothing (target within the source line, or result == input).
    public static func move(in text: String, lineContaining sourceIndex: Int, toBoundary target: Int) -> Move? {
        let ns = text as NSString
        guard ns.length > 0 else { return nil }

        let srcIdx = max(0, min(sourceIndex, ns.length - 1))
        let srcLine = ns.paragraphRange(for: NSRange(location: srcIdx, length: 0))

        // No-op if the target lands inside the source line (or at its own boundaries).
        if target >= srcLine.location && target <= srcLine.location + srcLine.length {
            return nil
        }
        let clampedTarget = max(0, min(target, ns.length))

        // The moved content: one line, no trailing newline.
        var line = ns.substring(with: srcLine)
        while line.hasSuffix("\n") { line.removeLast() }
        guard !line.isEmpty else { return nil }

        // Remove the source line, then translate the target into post-removal coords.
        let remaining = ns.replacingCharacters(in: srcLine, with: "") as NSString
        var insert = clampedTarget
        if clampedTarget > srcLine.location { insert -= srcLine.length }
        insert = max(0, min(insert, remaining.length))

        // Keep the line on its own line at the insertion point.
        let newline: unichar = 10
        let needsLeading = insert > 0 && remaining.character(at: insert - 1) != newline
        let needsTrailing = insert < remaining.length && remaining.character(at: insert) != newline
        var chunk = line
        if needsLeading { chunk = "\n" + chunk }
        if needsTrailing { chunk += "\n" }

        let result = remaining.replacingCharacters(in: NSRange(location: insert, length: 0), with: chunk)
        if result == text { return nil }

        let caret = insert + (needsLeading ? 1 : 0)
        return Move(text: result, caret: caret)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path swift/DetDocCore`
Expected: PASS — all `ParagraphMover` tests pass, no regressions.

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Services/ParagraphMover.swift \
        swift/DetDocCore/Tests/DetDocCoreTests/ParagraphMoverTests.swift
git commit -m "feat(core): ParagraphMover — move a line to a paragraph boundary"
```

---

### Task 2: Drag-to-reorder the image preview (app)

Install click/pan recognizers on the preview, draw the insertion indicator, and apply the move. Move tap handling from SwiftUI into AppKit.

**Files:**
- Create: `swift/DetDocApp/Sources/Workspace/Docs/DocImageDragController.swift`
- Modify: `swift/DetDocApp/Sources/Workspace/Docs/DocImageBubble.swift`
- Modify: `swift/DetDocApp/Sources/Workspace/Docs/LivePreviewTextView.swift`

**Interfaces:**
- Consumes: `ParagraphMover` (Task 1); `DocEditorViewModel` (has `edit(_:)`); `DocImageAttachment` (gains `editor`).
- Produces: `final class DocImageDragController: NSObject` (`@MainActor`).

- [ ] **Step 1: Create the drag controller**

Create `swift/DetDocApp/Sources/Workspace/Docs/DocImageDragController.swift`:

```swift
import AppKit
import DetDocCore

/// Drives drag-to-reorder for one inline image preview. A click opens Quick Look; a
/// pan moves the image's token line to another paragraph boundary, with a live
/// insertion indicator. Created per preview by DocImageProvider and retained by it.
@MainActor
final class DocImageDragController: NSObject {
    private let onOpen: () -> Void
    private let sourceIndex: Int            // backing char index inside the token's line
    private weak var editor: DocEditorViewModel?
    private weak var hostingView: NSView?
    private var indicator: NSView?

    init(hostingView: NSView, onOpen: @escaping () -> Void, sourceIndex: Int, editor: DocEditorViewModel) {
        self.hostingView = hostingView
        self.onOpen = onOpen
        self.sourceIndex = sourceIndex
        self.editor = editor
        super.init()

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        hostingView.addGestureRecognizer(click)
        hostingView.addGestureRecognizer(pan)
    }

    @objc private func handleClick() { onOpen() }

    private func enclosingTextView() -> NSTextView? {
        var v: NSView? = hostingView?.superview
        while let cur = v {
            if let tv = cur as? NSTextView { return tv }
            v = cur.superview
        }
        return nil
    }

    @objc private func handlePan(_ g: NSPanGestureRecognizer) {
        guard let tv = enclosingTextView() else { return }
        switch g.state {
        case .began:
            hostingView?.alphaValue = 0.4
        case .changed:
            if let target = targetBoundary(in: tv, at: g.location(in: tv)) {
                positionIndicator(in: tv, atBoundary: target)
            }
        case .ended:
            defer { endDrag() }
            if let target = targetBoundary(in: tv, at: g.location(in: tv)) {
                commitMove(in: tv, toBoundary: target)
            }
        default:
            endDrag()
        }
    }

    private func targetBoundary(in tv: NSTextView, at point: NSPoint) -> Int? {
        let ns = tv.string as NSString
        guard ns.length > 0 else { return nil }
        let idx = max(0, min(tv.characterIndexForInsertion(at: point), ns.length))
        let para = ns.paragraphRange(for: NSRange(location: min(idx, ns.length - 1), length: 0))
        return para.location
    }

    private func positionIndicator(in tv: NSTextView, atBoundary boundary: Int) {
        var rect = tv.firstRect(forCharacterRange: NSRange(location: boundary, length: 0), actualRange: nil)
        if let win = tv.window {
            rect = win.convertFromScreen(rect)
            rect = tv.convert(rect, from: nil)
        }
        let inset = tv.textContainerInset.width
        let bar = indicator ?? makeIndicator(in: tv)
        bar.frame = NSRect(x: inset, y: rect.minY - 1, width: max(0, tv.bounds.width - inset * 2), height: 2)
    }

    private func makeIndicator(in tv: NSTextView) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        tv.addSubview(v)
        indicator = v
        return v
    }

    private func commitMove(in tv: NSTextView, toBoundary target: Int) {
        guard let editor,
              let move = ParagraphMover.move(in: tv.string, lineContaining: sourceIndex, toBoundary: target)
        else { return }
        let full = NSRange(location: 0, length: (tv.string as NSString).length)
        if tv.shouldChangeText(in: full, replacementString: move.text) {
            tv.textStorage?.replaceCharacters(in: full, with: move.text)
            tv.didChangeText()
            let caret = max(0, min(move.caret, (move.text as NSString).length))
            tv.setSelectedRange(NSRange(location: caret, length: 0))
        }
        editor.edit(tv.string)
    }

    private func endDrag() {
        indicator?.removeFromSuperview()
        indicator = nil
        hostingView?.alphaValue = 1.0
    }
}
```

- [ ] **Step 2: Make DocImageView passive and wire the controller in the provider**

In `swift/DetDocApp/Sources/Workspace/Docs/DocImageBubble.swift`:

(a) Replace `DocImageView` (remove `onOpen` and the tap — the controller handles clicks):

```swift
struct DocImageView: View {
    let image: NSImage
    let size: CGSize

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
            .help("Drag to move • click to open full size")
    }
}
```

(b) Add `editor` to `DocImageAttachment` so the provider can build the controller. Change the stored properties + init:

```swift
final class DocImageAttachment: NSTextAttachment {
    let url: URL
    nonisolated(unsafe) let onOpen: () -> Void
    nonisolated(unsafe) let editor: DocEditorViewModel

    @MainActor
    init(url: URL, editor: DocEditorViewModel, onOpen: @escaping @MainActor () -> Void) {
        self.url = url
        self.editor = editor
        self.onOpen = onOpen
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func viewProvider(
        for parentView: NSView?,
        location: any NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        let p = DocImageProvider(
            textAttachment: self,
            parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager,
            location: location
        )
        p.tracksTextAttachmentViewBounds = true
        return p
    }
}
```

No new import is needed: `DocEditorViewModel` is an app-module type already in scope within the app target, and `DocImageBubble.swift` keeps its existing `import AppKit` / `import SwiftUI`. (`ParagraphMover` is used only from `DocImageDragController.swift`, which imports `DetDocCore` itself.)

(c) In `DocImageProvider`, capture `editor` + the source backing index, retain the controller, and build the hosting view without `onOpen` on the view. Update the stored properties and `init`:

```swift
final class DocImageProvider: NSTextAttachmentViewProvider {
    private let image: NSImage?
    private let onOpen: MainThreadOnly<() -> Void>
    private let editor: MainThreadOnly<DocEditorViewModel?>
    private let sourceIndex: Int
    private let containerWidth: CGFloat
    private var dragController: DocImageDragController?

    override init(
        textAttachment: NSTextAttachment,
        parentView: NSView?,
        textLayoutManager: NSTextLayoutManager?,
        location: any NSTextLocation
    ) {
        let a = textAttachment as? DocImageAttachment
        self.image = a.flatMap { NSImage(contentsOf: $0.url) }
        self.onOpen = MainThreadOnly(value: a?.onOpen ?? {})
        self.editor = MainThreadOnly(value: a?.editor)
        if let cm = textLayoutManager?.textContentManager {
            self.sourceIndex = cm.offset(from: cm.documentRange.location, to: location)
        } else {
            self.sourceIndex = 0
        }
        let cw = textLayoutManager?.textContainer?.size.width ?? 480
        self.containerWidth = (cw.isFinite && cw > 0) ? cw : 480
        super.init(textAttachment: textAttachment, parentView: parentView,
                   textLayoutManager: textLayoutManager, location: location)
    }
```

Keep `displaySize()` exactly as-is. Replace `loadView()` with:

```swift
    override func loadView() {
        let size = displaySize()
        let providerBox = MainThreadOnly(value: self)
        if let image {
            let imageBox = MainThreadOnly(value: image)
            let follow = onOpen
            let ed = editor
            let idx = sourceIndex
            MainActor.assumeIsolated {
                let host = NSHostingView(rootView: DocImageView(image: imageBox.value, size: size))
                providerBox.value.view = host
                if let editor = ed.value {
                    providerBox.value.dragController = DocImageDragController(
                        hostingView: host, onOpen: follow.value, sourceIndex: idx, editor: editor
                    )
                }
            }
        } else {
            MainActor.assumeIsolated { providerBox.value.view = NSView() }
        }
    }
```

Keep `attachmentBounds(...)` exactly as-is.

- [ ] **Step 3: Pass `editor` when constructing the image attachment**

In `swift/DetDocApp/Sources/Workspace/Docs/LivePreviewTextView.swift`, find the image render loop's attachment construction (Task-4 code):

```swift
                        let attachment = DocImageAttachment(url: url) { [weak self] in
                            self?.openQuickLook(url)
                        }
```

Replace with (pass the Coordinator's `editor`):

```swift
                        let attachment = DocImageAttachment(url: url, editor: editor) { [weak self] in
                            self?.openQuickLook(url)
                        }
```

- [ ] **Step 4: Build to verify it compiles**

Run (from `swift/DetDocApp`): `xcodebuild build -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED, no new warnings.

- [ ] **Step 5: Manual verification**

1. Launch the app; open a doc with an image token that renders as a preview (per the inline-images feature).
2. **Click** the preview (no drag) → Quick Look opens. (Regression of existing behavior.)
3. **Drag** the preview slowly upward → the preview dims, a thin accent-colored insertion indicator appears at line boundaries and follows the cursor. Release over a boundary above → the image's line moves there; the document updates and the preview re-renders on the new line.
4. **Drag** downward past several lines and release → image moves down to that boundary.
5. Drag and release on the image's own line → no change (no-op).
6. Drag, then press Esc / release outside (cancelled) → indicator disappears, preview un-dims, text unchanged.
7. Cmd-Z after a move → the move is undone in one step.
8. Regression: typing, link bubbles, other previews, and text selection in the editor still work.

Expected: all behaviors as described.

- [ ] **Step 6: Commit**

```bash
git add swift/DetDocApp/Sources/Workspace/Docs/DocImageDragController.swift \
        swift/DetDocApp/Sources/Workspace/Docs/DocImageBubble.swift \
        swift/DetDocApp/Sources/Workspace/Docs/LivePreviewTextView.swift
git commit -m "feat(app): drag an image preview to move it between lines"
```

---

## Self-Review

**Spec coverage:**
- Click→Quick Look, pan→move distinction → Task 2 (click/pan recognizers). ✓
- In-place dim + insertion indicator → Task 2 (`alphaValue`, indicator overlay). ✓
- Move to any paragraph boundary, own-line invariant → Task 1 (`ParagraphMover`). ✓
- Source identified by backing `location` → Task 2 (`cm.offset(from:to:)`). ✓
- No-op cases, last-line handling, caret → Task 1 + tests. ✓
- Remove SwiftUI tap → Task 2 Step 2a. ✓
- One-undo-step move → Task 2 (`replaceCharacters` on full range). ✓
- Core unit tests; app manual → Tasks 1–2. ✓

**Placeholder scan:** No TBD/TODO; complete code in every code step. The Step 2b `import DetDocCore` note is a conditional with an explicit resolution (remove if `DocEditorViewModel` resolves without it), not a placeholder. ✓

**Type consistency:** `ParagraphMover.move(in:lineContaining:toBoundary:) -> Move?` and `Move{text,caret}` used identically in Task 1 tests, Task 1 impl, and Task 2 `commitMove`. `DocImageAttachment(url:editor:onOpen:)` updated at its single construction site (Task 2 Step 3). `DocImageView(image:size:)` (onOpen removed) matches its only constructor in `loadView`. ✓
