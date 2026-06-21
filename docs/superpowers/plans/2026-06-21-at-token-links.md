# @-Token Link Format Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the markdown `[name](path.md)` link storage format with a compact `@guides/setup` token (@ + docs-relative path without `.md`, terminated by whitespace), keeping all rendering/navigation/bubble/broken-link UX intact.

**Architecture:** Four surgical edits in `DetDocCore` (DocLink, new DocRef scanner, DocLinkResolver, MarkdownStyleScanner) plus two in the app layer (LivePreviewTextView delegate, DocLinkCompletionModel.commit). Tests updated in lockstep. Everything lands in one commit.

**Tech Stack:** Swift 6.4, SwiftUI + AppKit (TextKit 2), Swift Testing, SwiftPM (Core), Tuist (App).

## Global Constraints

- Swift tools 6.4; macOS deployment target 27.0.
- `DetDocCore` compiles with `.treatAllWarnings(as: .error)` — all touched files must be warning-clean.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`) — never XCTest.
- Core tests: `swift test --package-path swift/DetDocCore`.
- App tests: `tuist generate >/dev/null && xcodebuild test -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS'`.
- All changes land in ONE commit: `feat: store doc links as @-tokens instead of markdown links`.

---

## File Map

| Action | Path |
|--------|------|
| Modify | `swift/DetDocCore/Sources/DetDocCore/Services/DocLink.swift` |
| Modify | `swift/DetDocCore/Tests/DetDocCoreTests/DocLinkTests.swift` |
| **Create** | `swift/DetDocCore/Sources/DetDocCore/Services/DocRef.swift` |
| **Create** | `swift/DetDocCore/Tests/DetDocCoreTests/DocRefTests.swift` |
| Modify | `swift/DetDocCore/Sources/DetDocCore/Services/DocLinkResolver.swift` |
| Modify | `swift/DetDocCore/Tests/DetDocCoreTests/DocLinkResolverTests.swift` |
| Modify | `swift/DetDocCore/Sources/DetDocCore/Services/MarkdownStyleScanner.swift` |
| Modify | `swift/DetDocCore/Tests/DetDocCoreTests/MarkdownStyleScannerTests.swift` |
| Modify | `swift/DetDocApp/Sources/Workspace/Docs/LivePreviewTextView.swift` |
| Modify | `swift/DetDocApp/Sources/Workspace/Docs/DocLinkCompletionModel.swift` |
| Modify | `swift/DetDocApp/Tests/DocLinkCompletionModelTests.swift` |
| Create | `/Users/mxmtrshn/Workspace/DetDoc/.superpowers/sdd/task-16-report.md` |

---

### Task 1: Core — DocLink.swift + DocLinkTests.swift

**Files:**
- Modify: `swift/DetDocCore/Sources/DetDocCore/Services/DocLink.swift`
- Modify: `swift/DetDocCore/Tests/DetDocCoreTests/DocLinkTests.swift`

**Interfaces:**
- Produces: `DocLink.make(docsRelativePath: String) -> String` returning `"@guides/setup"` for input `"guides/setup.md"`.

- [ ] **Step 1: Rewrite DocLink.swift**

Replace the entire file content with:

```swift
import Foundation

public enum DocLink {
    /// Build the stored link token for a docs-relative path: "@" + path without ".md".
    /// e.g. "guides/setup.md" -> "@guides/setup"
    public static func make(docsRelativePath: String) -> String {
        let noExt = docsRelativePath.hasSuffix(".md") ? String(docsRelativePath.dropLast(3)) : docsRelativePath
        return "@\(noExt)"
    }
}
```

- [ ] **Step 2: Rewrite DocLinkTests.swift**

Replace the entire file content with:

```swift
import Testing
@testable import DetDocCore

@Test func makeBuildsAtToken() {
    #expect(DocLink.make(docsRelativePath: "guides/setup.md") == "@guides/setup")
}

@Test func makeWithoutExtensionIsIdempotent() {
    #expect(DocLink.make(docsRelativePath: "guides/setup") == "@guides/setup")
}
```

- [ ] **Step 3: Run core tests (should pass)**

```bash
swift test --package-path /Users/mxmtrshn/Workspace/DetDoc/swift/DetDocCore --filter DocLinkTests 2>&1 | tail -5
```

Expected: `Test Suite 'All tests' passed`

---

### Task 2: Core — NEW DocRef.swift + DocRefTests.swift

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Services/DocRef.swift`
- Create: `swift/DetDocCore/Tests/DetDocCoreTests/DocRefTests.swift`

**Interfaces:**
- Produces:
  - `struct DocRef: Equatable, Sendable { let range: NSRange; let path: String }`
  - `enum DocRefScanner { static func scan(_ text: String) -> [DocRef] }` — finds `@<path>` tokens where `@` is at word-boundary (start or preceded by whitespace).

- [ ] **Step 1: Create DocRef.swift**

```swift
import Foundation

public struct DocRef: Equatable, Sendable {
    public let range: NSRange   // covers "@guides/setup" (includes the @)
    public let path: String     // docs-relative path WITHOUT .md, e.g. "guides/setup"
    public init(range: NSRange, path: String) { self.range = range; self.path = path }
}

public enum DocRefScanner {
    /// Finds `@<path>` tokens where `@` is at a word boundary (start of text or
    /// preceded by whitespace) and is followed by >=1 path char
    /// (letters, digits, and / - _ .). The path excludes the leading `@`.
    public static func scan(_ text: String) -> [DocRef] {
        let ns = text as NSString
        let re = try! NSRegularExpression(pattern: #"(?<![^\s])@([\p{L}\p{N}/_.\-]+)"#)
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            DocRef(range: $0.range, path: ns.substring(with: $0.range(at: 1)))
        }
    }
}
```

- [ ] **Step 2: Create DocRefTests.swift**

```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func scanFindsTokenAtStart() {
    let refs = DocRefScanner.scan("@a")
    #expect(refs.count == 1)
    #expect(refs[0].path == "a")
    #expect(refs[0].range == NSRange(location: 0, length: 2))
}

@Test func scanFindsTokenAfterSpace() {
    let s = "see @guides/setup x"
    let refs = DocRefScanner.scan(s)
    #expect(refs.count == 1)
    #expect(refs[0].path == "guides/setup")
    // range covers "@guides/setup" = 13 chars starting at offset 4
    #expect(refs[0].range == NSRange(location: 4, length: 13))
}

@Test func scanIgnoresAtNotAtWordBoundary() {
    let refs = DocRefScanner.scan("a@b")
    #expect(refs.isEmpty)
}

@Test func scanFindsMultipleTokens() {
    let refs = DocRefScanner.scan("@foo and @bar/baz")
    #expect(refs.count == 2)
    #expect(refs[0].path == "foo")
    #expect(refs[1].path == "bar/baz")
}

@Test func scanHandlesPathChars() {
    let refs = DocRefScanner.scan("@a-b/c_d.e")
    #expect(refs.count == 1)
    #expect(refs[0].path == "a-b/c_d.e")
}

@Test func scanBareAtAloneProducesNoToken() {
    let refs = DocRefScanner.scan("@ foo")
    #expect(refs.isEmpty)
}

@Test func scanCyrillicAfterSpaceTriggersToken() {
    // Cyrillic letters match \p{L} so "@страница" at start should be found
    let refs = DocRefScanner.scan(" @страница")
    #expect(refs.count == 1)
    #expect(refs[0].path == "страница")
}
```

- [ ] **Step 3: Run DocRef tests**

```bash
swift test --package-path /Users/mxmtrshn/Workspace/DetDoc/swift/DetDocCore --filter DocRefTests 2>&1 | tail -5
```

Expected: all 7 tests pass.

---

### Task 3: Core — DocLinkResolver.swift + DocLinkResolverTests.swift

**Files:**
- Modify: `swift/DetDocCore/Sources/DetDocCore/Services/DocLinkResolver.swift`
- Modify: `swift/DetDocCore/Tests/DetDocCoreTests/DocLinkResolverTests.swift`

**Interfaces:**
- Consumes: `DocLink.internalTarget` is GONE — resolver now takes a raw token path (no `@`, no `.md`).
- Produces: `resolve(_ tokenPath: String) -> Resolution?` — appends `.md`, looks up in `existing`.

- [ ] **Step 1: Rewrite DocLinkResolver.swift**

```swift
import Foundation

public struct DocLinkResolver: Sendable {
    public struct Resolution: Equatable, Sendable {
        public let docsRelativePath: String
        public let docPath: String
        public let exists: Bool
        public init(docsRelativePath: String, docPath: String, exists: Bool) {
            self.docsRelativePath = docsRelativePath; self.docPath = docPath; self.exists = exists
        }
    }

    private let existing: Set<String>
    public init(candidates: Set<String>) { self.existing = candidates }

    public func resolve(_ tokenPath: String) -> Resolution? {
        let path = tokenPath.hasPrefix("/") ? String(tokenPath.dropFirst()) : tokenPath
        guard !path.isEmpty else { return nil }
        let docsRel = path + ".md"
        return Resolution(docsRelativePath: docsRel, docPath: "docs/\(docsRel)", exists: existing.contains(docsRel))
    }
}
```

- [ ] **Step 2: Rewrite DocLinkResolverTests.swift**

```swift
import Testing
@testable import DetDocCore

@Test func resolveMarksExistingAndMissing() {
    let r = DocLinkResolver(candidates: ["guides/setup.md"])
    #expect(r.resolve("guides/setup") == .init(docsRelativePath: "guides/setup.md", docPath: "docs/guides/setup.md", exists: true))
    #expect(r.resolve("guides/missing") == .init(docsRelativePath: "guides/missing.md", docPath: "docs/guides/missing.md", exists: false))
}

@Test func resolveEmptyPathReturnsNil() {
    let r = DocLinkResolver(candidates: [])
    #expect(r.resolve("") == nil)
}

@Test func resolveLeadingSlashIsNormalized() {
    let r = DocLinkResolver(candidates: ["guides/setup.md"])
    #expect(r.resolve("/guides/setup") == .init(docsRelativePath: "guides/setup.md", docPath: "docs/guides/setup.md", exists: true))
}
```

- [ ] **Step 3: Run resolver tests**

```bash
swift test --package-path /Users/mxmtrshn/Workspace/DetDoc/swift/DetDocCore --filter DocLinkResolverTests 2>&1 | tail -5
```

Expected: all 3 tests pass.

---

### Task 4: Core — MarkdownStyleScanner.swift + MarkdownStyleScannerTests.swift

**Files:**
- Modify: `swift/DetDocCore/Sources/DetDocCore/Services/MarkdownStyleScanner.swift`
- Modify: `swift/DetDocCore/Tests/DetDocCoreTests/MarkdownStyleScannerTests.swift`

**Interfaces:**
- `MarkdownSpanKind` loses the `.link` case; only `.heading`, `.bold`, `.italic` remain.
- `MarkdownStyleScanner.scan` no longer calls `links(_:)`.

- [ ] **Step 1: Rewrite MarkdownStyleScanner.swift**

```swift
import Foundation

public enum MarkdownSpanKind: Equatable, Sendable {
    case heading(level: Int)
    case bold
    case italic
}

public struct MarkdownSpan: Equatable, Sendable {
    public let range: NSRange
    public let kind: MarkdownSpanKind
    public init(range: NSRange, kind: MarkdownSpanKind) { self.range = range; self.kind = kind }
}

public enum MarkdownStyleScanner {
    public static func scan(_ source: String) -> [MarkdownSpan] {
        let ns = source as NSString
        var spans: [MarkdownSpan] = []
        spans.append(contentsOf: headings(ns))
        spans.append(contentsOf: matches(ns, #"\*\*(?:[^*]|\*(?!\*))+\*\*"#, kind: .bold))
        spans.append(contentsOf: matches(ns, #"(?<!\*)\*(?!\*)[^*\n]+\*(?!\*)"#, kind: .italic))
        return spans
    }

    private static func headings(_ ns: NSString) -> [MarkdownSpan] {
        regex(#"(?m)^(#{1,6})[ \t].*$"#).matches(in: ns as String, range: NSRange(location: 0, length: ns.length)).map {
            let hashes = ns.substring(with: $0.range(at: 1)).count
            return MarkdownSpan(range: $0.range, kind: .heading(level: hashes))
        }
    }

    private static func matches(_ ns: NSString, _ pattern: String, kind: MarkdownSpanKind) -> [MarkdownSpan] {
        regex(pattern).matches(in: ns as String, range: NSRange(location: 0, length: ns.length))
            .map { MarkdownSpan(range: $0.range, kind: kind) }
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are static and known-valid; force-try is acceptable here.
        try! NSRegularExpression(pattern: pattern)
    }
}
```

- [ ] **Step 2: Rewrite MarkdownStyleScannerTests.swift** (keep heading/bold/italic; remove the two link tests)

```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func scanFindsAtxHeadingLevel() {
    let spans = MarkdownStyleScanner.scan("## Title\n")
    #expect(spans.contains(MarkdownSpan(range: NSRange(location: 0, length: 8), kind: .heading(level: 2))))
}

@Test func scanFindsBoldAndItalic() {
    let spans = MarkdownStyleScanner.scan("a **b** c *d* e")
    #expect(spans.contains { $0.kind == .bold && ($0.range as NSRange).location == 2 && $0.range.length == 5 })
    #expect(spans.contains { $0.kind == .italic && $0.range.location == 10 && $0.range.length == 3 })
}
```

- [ ] **Step 3: Run all core tests to confirm nothing broke**

```bash
swift test --package-path /Users/mxmtrshn/Workspace/DetDoc/swift/DetDocCore 2>&1 | tail -10
```

Expected: all tests pass, zero warnings.

---

### Task 5: App — LivePreviewTextView.swift

**Files:**
- Modify: `swift/DetDocApp/Sources/Workspace/Docs/LivePreviewTextView.swift`

**Interfaces:**
- Consumes: `DocRefScanner.scan(_ text: String) -> [DocRef]` (from Task 2); `DocLinkResolver.resolve(_ tokenPath: String) -> Resolution?` (from Task 3); `MarkdownSpanKind` no longer has `.link`.
- The `DocLinkBubbleAttachment(title:onFollow:)` API is unchanged.

**Key design decisions for the delegate rework:**
1. The `for span in spans` switch drops the `.link` branch (it's gone from the enum).
2. After the heading/bold/italic loop, a new block scans `raw.string` with `DocRefScanner.scan` and processes each `DocRef`.
3. For existing links: style blue + `.link` attribute on `display`; if caret not in link → add a bubble modification. For broken links: style red + dotted underline + tooltip. No syntax deletion needed (the `@token` IS the text — no `[` `]` `(` `)` wrappers to strip).
4. `linkRange(atCaret:)` switches from `MarkdownStyleScanner.scan` to `DocRefScanner.scan`.
5. The `modifications` collection-and-sort logic is reused unchanged — bubble mods are appended to it.

- [ ] **Step 1: Rewrite LivePreviewTextView.swift**

Replace the entire file with:

```swift
import SwiftUI
import AppKit
import DetDocCore

struct LivePreviewTextView: NSViewRepresentable {
    @Bindable var editor: DocEditorViewModel
    var resolver: DocLinkResolver
    var candidatesProvider: () -> [DocCandidate]
    var onFollowLink: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(editor: editor, resolver: resolver,
                    candidatesProvider: candidatesProvider,
                    onFollowLink: onFollowLink)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.textContainerInset = NSSize(width: 12, height: 12)
        tv.string = editor.source
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        context.coordinator.textView = tv
        if let tcs = tv.textLayoutManager?.textContentManager as? NSTextContentStorage {
            tcs.delegate = context.coordinator
        }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.editor = editor
        context.coordinator.resolver = resolver
        context.coordinator.candidatesProvider = candidatesProvider
        context.coordinator.onFollowLink = onFollowLink
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != editor.source {           // external change (open/clear)
            tv.string = editor.source
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSTextContentStorageDelegate {
        var editor: DocEditorViewModel
        var resolver: DocLinkResolver
        var candidatesProvider: () -> [DocCandidate]
        var onFollowLink: (String) -> Void
        weak var textView: NSTextView?

        let completion = DocLinkCompletionModel()
        private var panel: NSPanel?
        private var cachedCandidates: [DocCandidate] = []
        private var lastCaret = 0

        init(editor: DocEditorViewModel, resolver: DocLinkResolver,
             candidatesProvider: @escaping () -> [DocCandidate],
             onFollowLink: @escaping (String) -> Void) {
            self.editor = editor
            self.resolver = resolver
            self.candidatesProvider = candidatesProvider
            self.onFollowLink = onFollowLink
        }

        // MARK: - NSTextContentStorageDelegate

        func textContentStorage(_ tcs: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
            guard let storage = tcs.textStorage, range.location >= 0,
                  range.location + range.length <= storage.length else { return nil }
            let raw = storage.attributedSubstring(from: range)
            let spans = MarkdownStyleScanner.scan(raw.string)
            let refs = DocRefScanner.scan(raw.string)
            if spans.isEmpty && refs.isEmpty { return nil }   // plain paragraph -> default rendering

            let display = NSMutableAttributedString(attributedString: raw)
            let full = NSRange(location: 0, length: (raw.string as NSString).length)
            display.setAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.textColor,
            ], range: full)

            let caret = textView?.selectedRange().location ?? -1
            let paraStart = range.location

            // Pending modifications to apply highest-offset-first after styling.
            // nil replacement = delete; non-nil = replace with attachment.
            var modifications: [(range: NSRange, replacement: NSAttributedString?)] = []

            // --- Heading / bold / italic ---
            for span in spans {
                switch span.kind {
                case let .heading(level):
                    let size: CGFloat = [1: 22, 2: 19, 3: 16].first { $0.key == level }?.value ?? 14
                    display.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: size, weight: .bold), range: span.range)
                case .bold:
                    display.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold), range: span.range)
                case .italic:
                    if let it = NSFontManager.shared.convert(.monospacedSystemFont(ofSize: 13, weight: .regular), toHaveTrait: .italicFontMask) as NSFont? {
                        display.addAttribute(.font, value: it, range: span.range)
                    }
                }
            }

            // --- @-token links ---
            for ref in refs {
                let absStart = paraStart + ref.range.location
                let absEnd = absStart + ref.range.length
                let caretInLink = caret >= absStart && caret < absEnd

                if let res = resolver.resolve(ref.path) {
                    if res.exists {
                        // Always apply link color + .link attribute (so cmd-click works on revealed tokens too).
                        display.addAttribute(.foregroundColor, value: NSColor.linkColor, range: ref.range)
                        display.addAttribute(.link, value: "detdoc://\(res.docPath)", range: ref.range)

                        if !caretInLink {
                            // Collapse to a Liquid Glass bubble.
                            let docName = String(ref.path.split(separator: "/").last ?? Substring(ref.path))
                            let docPath = res.docPath
                            let bubble = DocLinkBubbleAttachment(title: docName) { [weak self] in
                                self?.onFollowLink(docPath)
                            }
                            modifications.append((range: ref.range, replacement: NSAttributedString(attachment: bubble)))
                        }
                    } else {
                        // Broken token: red dotted — no bubble, regardless of caret.
                        display.addAttribute(.foregroundColor, value: NSColor.systemRed, range: ref.range)
                        display.addAttribute(.underlineStyle, value: NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.single.rawValue, range: ref.range)
                        display.addAttribute(.toolTip, value: "Missing: \(res.docsRelativePath)", range: ref.range)
                    }
                }
                // If resolver returns nil (empty path), nothing is styled — token stays as-is.
            }

            // Apply highest-offset-first so earlier paragraph-local offsets stay valid.
            for mod in modifications.sorted(by: { $0.range.location > $1.range.location }) {
                if let replacement = mod.replacement {
                    display.replaceCharacters(in: mod.range, with: replacement)
                } else {
                    display.deleteCharacters(in: mod.range)
                }
            }
            return NSTextParagraph(attributedString: display)
        }

        // MARK: - Panel management

        private func showPanel() {
            let host = NSHostingController(rootView: DocLinkSuggestionsView(model: completion) { [weak self] i in
                self?.completion.selectByTap(i)
                self?.commitCompletion()
            })
            let p = NSPanel(contentViewController: host)
            p.styleMask = [.nonactivatingPanel, .borderless]
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .popUpMenu
            panel = p
        }

        private func positionPanel() {
            guard let tv = textView, let win = tv.window, let panel else { return }
            let caret = tv.selectedRange()
            var rect = tv.firstRect(forCharacterRange: NSRange(location: caret.location, length: 0), actualRange: nil)
            if rect == .zero {
                let fallbackLoc = max(0, caret.location - 1)
                rect = tv.firstRect(forCharacterRange: NSRange(location: fallbackLoc, length: 1), actualRange: nil)
            }
            panel.setFrameTopLeftPoint(NSPoint(x: rect.minX, y: rect.minY - 6))
            if panel.parent == nil { win.addChildWindow(panel, ordered: .above) }
        }

        private func hidePanel() {
            if let p = panel { p.parent?.removeChildWindow(p); p.orderOut(nil) }
            panel = nil
        }

        // MARK: - Completion logic

        private func updateCompletion() {
            guard let tv = textView else { return }
            let cursor = tv.selectedRange().location
            guard let q = DocLinkCompletion.activeQuery(in: tv.string, cursorUTF16Offset: cursor) else {
                if completion.isActive { completion.cancel(); hidePanel() }
                return
            }
            if !completion.isActive { cachedCandidates = candidatesProvider() }
            if completion.isActive {
                completion.update(query: q, caretRect: .zero, candidates: cachedCandidates)
            } else {
                completion.begin(query: q, caretRect: .zero, candidates: cachedCandidates)
            }
            if panel == nil { showPanel() }
            positionPanel()
        }

        private func commitCompletion() {
            guard let tv = textView, let ins = completion.commit() else { return }
            if tv.shouldChangeText(in: ins.range, replacementString: ins.text) {
                tv.textStorage?.replaceCharacters(in: ins.range, with: ins.text)
                tv.didChangeText()
                tv.setSelectedRange(NSRange(location: ins.range.location + (ins.text as NSString).length, length: 0))
            }
            editor.edit(tv.string)
            hidePanel()
            // Force refresh of the paragraph containing the inserted token so it collapses immediately.
            let insertEnd = ins.range.location + (ins.text as NSString).length
            refreshCaretParagraphs(old: insertEnd, new: insertEnd)
        }

        // MARK: - Refresh helper

        /// Returns the document-absolute NSRange of the @-token span (if any) that
        /// contains `caret`, or nil if the caret is not inside a token.
        private func linkRange(atCaret caret: Int) -> NSRange? {
            guard let storage = textView?.textStorage, caret >= 0, caret <= storage.length else { return nil }
            let ns = storage.string as NSString
            let para = ns.paragraphRange(for: NSRange(location: min(caret, max(0, ns.length - 1)), length: 0))
            let paraStr = ns.substring(with: para)
            for ref in DocRefScanner.scan(paraStr) {
                let absStart = para.location + ref.range.location
                let absEnd = absStart + ref.range.length
                if caret >= absStart && caret < absEnd { return NSRange(location: absStart, length: absEnd - absStart) }
            }
            return nil
        }

        func refreshCaretParagraphs(old: Int, new: Int) {
            guard let storage = textView?.textStorage else { return }
            let ns = storage.string as NSString
            func paraRange(_ loc: Int) -> NSRange {
                let l = max(0, min(loc, ns.length))
                return ns.paragraphRange(for: NSRange(location: l, length: 0))
            }
            let union = NSUnionRange(paraRange(old), paraRange(new))
            storage.beginEditing()
            storage.edited(.editedAttributes, range: union, changeInLength: 0)
            storage.endEditing()
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            editor.edit(tv.string)
            // Editing already makes the content storage re-run the delegate for changed
            // paragraphs, so no manual refresh needed here.
            updateCompletion()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            let new = textView?.selectedRange().location ?? 0
            let oldLink = linkRange(atCaret: lastCaret)
            let newLink = linkRange(atCaret: new)
            if oldLink != newLink {
                refreshCaretParagraphs(old: lastCaret, new: new)
            }
            lastCaret = new
            updateCompletion()
        }

        // Dismiss the picker when the text view loses focus.
        func textDidEndEditing(_ notification: Notification) {
            if completion.isActive { completion.cancel(); hidePanel() }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard completion.isActive else { return false }
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                completion.moveUp(); return true
            case #selector(NSResponder.moveDown(_:)):
                completion.moveDown(); return true
            case #selector(NSResponder.insertNewline(_:)):
                commitCompletion(); return true
            case #selector(NSResponder.cancelOperation(_:)):
                completion.cancel(); hidePanel(); return true
            default:
                return false
            }
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard NSApp.currentEvent?.modifierFlags.contains(.command) == true else { return false }
            let raw: String?
            if let s = link as? String { raw = s }
            else if let url = link as? URL { raw = url.absoluteString.removingPercentEncoding ?? url.absoluteString }
            else { raw = nil }
            guard let s = raw, s.hasPrefix("detdoc://") else { return false }
            onFollowLink(String(s.dropFirst("detdoc://".count)))
            return true
        }
    }
}
```

---

### Task 6: App — DocLinkCompletionModel.swift + DocLinkCompletionModelTests.swift

**Files:**
- Modify: `swift/DetDocApp/Sources/Workspace/Docs/DocLinkCompletionModel.swift`
- Modify: `swift/DetDocApp/Tests/DocLinkCompletionModelTests.swift`

**Interfaces:**
- Consumes: `DocLink.make(docsRelativePath: String) -> String` (Task 1 new API — no `name` param).
- `commit()` now inserts `"@guides/setup"` instead of `"[setup](guides/setup.md)"`.

**Note on expected insertion in test:** candidates are `[setup (guides/setup.md), glossary (guides/glossary.md)]`. `begin` with query `"gu"` → `suggestions(query: "gu", ...)`. Both paths contain "gu" (guides/...). Both are prefix matches at offset 0 of "guides/..." → score 0. Tie broken by `docsRelativePath`: `"guides/glossary.md" < "guides/setup.md"` alphabetically → sorted order: `[glossary, setup]`. `moveDown()` from index 0 → index 1 (setup). `commit()` → `DocLink.make(docsRelativePath: "guides/setup.md")` = `"@guides/setup"`.

- [ ] **Step 1: Update DocLinkCompletionModel.swift — only the commit() method changes**

Change line 47 from:
```swift
return Insertion(text: DocLink.make(name: c.name, docsRelativePath: c.docsRelativePath), range: replaceRange)
```
to:
```swift
return Insertion(text: DocLink.make(docsRelativePath: c.docsRelativePath), range: replaceRange)
```

- [ ] **Step 2: Update DocLinkCompletionModelTests.swift**

Change the `beginPopulatesAndCommitsSelectedLink` expectation from:
```swift
#expect(ins == DocLinkCompletionModel.Insertion(text: "[setup](guides/setup.md)", range: NSRange(location: 0, length: 3)))
```
to:
```swift
#expect(ins == DocLinkCompletionModel.Insertion(text: "@guides/setup", range: NSRange(location: 0, length: 3)))
```

- [ ] **Step 3: Run full core test suite**

```bash
swift test --package-path /Users/mxmtrshn/Workspace/DetDoc/swift/DetDocCore 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **` (all tests pass).

---

### Task 7: App test suite + Commit

**Files:**
- Create: `/Users/mxmtrshn/Workspace/DetDoc/.superpowers/sdd/task-16-report.md`

- [ ] **Step 1: Run app test suite**

```bash
cd /Users/mxmtrshn/Workspace/DetDoc/swift/DetDocApp && tuist generate >/dev/null && xcodebuild test -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS' 2>&1 | tee /tmp/t16.log | tail -5
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 2: Verify no new warnings in touched files**

```bash
grep -iE "\.swift.*warning:|error:" /tmp/t16.log | grep -v "^Build " || echo "CLEAN"
```

Expected: `CLEAN` or only warnings/errors in files not touched by this change.

- [ ] **Step 3: Write report to .superpowers/sdd/task-16-report.md**

- [ ] **Step 4: Commit everything**

```bash
git -C /Users/mxmtrshn/Workspace/DetDoc add \
  swift/DetDocCore/Sources/DetDocCore/Services/DocLink.swift \
  swift/DetDocCore/Sources/DetDocCore/Services/DocRef.swift \
  swift/DetDocCore/Sources/DetDocCore/Services/DocLinkResolver.swift \
  swift/DetDocCore/Sources/DetDocCore/Services/MarkdownStyleScanner.swift \
  swift/DetDocCore/Tests/DetDocCoreTests/DocLinkTests.swift \
  swift/DetDocCore/Tests/DetDocCoreTests/DocRefTests.swift \
  swift/DetDocCore/Tests/DetDocCoreTests/DocLinkResolverTests.swift \
  swift/DetDocCore/Tests/DetDocCoreTests/MarkdownStyleScannerTests.swift \
  swift/DetDocApp/Sources/Workspace/Docs/LivePreviewTextView.swift \
  swift/DetDocApp/Sources/Workspace/Docs/DocLinkCompletionModel.swift \
  swift/DetDocApp/Tests/DocLinkCompletionModelTests.swift

git -C /Users/mxmtrshn/Workspace/DetDoc commit -m "feat: store doc links as @-tokens instead of markdown links"
```

---

## Self-Review

### Spec coverage

| Spec item | Covered by |
|-----------|-----------|
| A1: DocLink.make → @token, remove internalTarget | Task 1 |
| A1: DocLinkTests updated | Task 1 |
| A2: new DocRef.swift + DocRefScanner | Task 2 |
| A2: DocRefTests.swift | Task 2 |
| A3: DocLinkResolver.resolve takes token path | Task 3 |
| A3: DocLinkResolverTests updated | Task 3 |
| A4: Remove .link case from MarkdownSpanKind | Task 4 |
| A4: Remove link detection + call | Task 4 |
| A4: MarkdownStyleScannerTests remove link tests | Task 4 |
| B1: Delegate uses DocRefScanner | Task 5 |
| B1: Existing → blue + .link + bubble (not in caret) | Task 5 |
| B1: Broken → red dotted no bubble | Task 5 |
| B1: linkRange uses DocRefScanner | Task 5 |
| B1: Drop .link branch from span switch | Task 5 |
| B2: commit() inserts @token | Task 6 |
| B2: DocLinkCompletionModelTests updated | Task 6 |
| B3: DocLinkBubble takes title + closure (unchanged) | Already satisfied |
| Verification: both suites green | Task 7 |
| Commit message exact | Task 7 |
| Report at .superpowers/sdd/task-16-report.md | Task 7 |

### Placeholder scan
No TBD, TODO, or "similar to" placeholders found.

### Type consistency check
- `DocLink.make(docsRelativePath:)` — used in Task 1, Task 6. Signature matches.
- `DocRefScanner.scan(_ text: String) -> [DocRef]` — defined Task 2, used Task 5 (x2).
- `DocLinkResolver.resolve(_ tokenPath: String) -> Resolution?` — defined Task 3, used Task 5.
- `MarkdownSpanKind` has `.heading`, `.bold`, `.italic` — defined Task 4, exhaustive switch in Task 5 (no default needed since all cases handled).
- `DocLinkBubbleAttachment(title: docName, onFollow: ...)` — matches existing `DocLinkBubble.swift` API (Task 5 uses it).

All consistent.
