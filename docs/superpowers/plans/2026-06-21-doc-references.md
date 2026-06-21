# Cross-Document References (`@`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a Markdown doc reference another: typing `@` opens an interactive Liquid-Glass picker of `docs/` files and inserts a standard `[name](path.md)` link, rendered inline and clickable to open the target, on a new TextKit 2 live-preview editing surface.

**Architecture:** Pure, filesystem-light logic lives in `DetDocCore` (a Markdown span scanner, link helpers, a resolver, and the `@`-completion tokenizer) with fast Swift Testing unit tests. The editor becomes a thin `NSViewRepresentable` over a TextKit 2 `NSTextView` (`LivePreviewTextView`) that applies styling from the core scanner and hosts the picker; an `@MainActor @Observable DocLinkCompletionModel` holds picker state; `DocLinkSuggestionsView` is the glass popover. The split source/preview editor is retired.

**Tech Stack:** Swift 6.4, SwiftUI + AppKit (TextKit 2 / `NSTextView`), Swift Testing, Tuist (app project), SwiftPM (`DetDocCore`).

## Global Constraints

- Swift tools 6.4; macOS deployment target 27.0 (`DetDocCore` `platforms: [.macOS(.v27)]`, app `deploymentTargets: .macOS("27.0")`).
- `DetDocCore` target compiles with `.treatAllWarnings(as: .error)` — core code must be warning-clean.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`) — never XCTest. Core tests use the existing `TempDir` helper; app tests use `@testable import DetDoc` + `@testable import DetDocCore` and the `VMGitFixture` helper.
- App module name is `DetDoc` (product name), target is `DetDocApp`; view models live in `DetDocApp/Sources/...`, app tests in `DetDocApp/Tests/...` (file-system-synchronized folders — no project edits needed to add files).
- Link path base is the `docs/` root (paths stored docs-relative, e.g. `guides/setup.md`). Inserted link text is the file name without `.md`.
- Commit after every task. Branch: `feat/doc-references` (already created; the design spec is committed there).
- Run core tests: `swift test --package-path swift/DetDocCore --filter <Name>`.
- Run app tests (from `swift/DetDocApp`): `tuist generate >/dev/null && xcodebuild test -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS'` (append `-only-testing:DetDocAppTests/<func>` to narrow).

## Notes / deliberate deviation from the spec

The spec named `swift-markdown` for parsing. For **in-editor live styling we need `NSRange`s in the editable text**; `swift-markdown` reports `SourceRange` as line/column and would require a fiddly, separately-tested line→UTF-16-offset mapper, while a focused in-house scanner returns `NSRange`s directly and stays in the testable core. This plan therefore implements `MarkdownStyleScanner` in-house and does **not** add `swift-markdown` yet. Behavior and the user-facing design are unchanged; `swift-markdown` remains the right tool to adopt later for richer parsing (images, tables, export). This deviation is called out for the reviewer.

---

## Phase 1 — Core logic (pure, TDD)

### Task 1: `MarkdownStyleScanner` — spans for headings, emphasis, links

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Services/MarkdownStyleScanner.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/MarkdownStyleScannerTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum MarkdownSpanKind: Equatable, Sendable { case heading(level: Int); case bold; case italic; case link(destination: String, textRange: NSRange) }`
  - `struct MarkdownSpan: Equatable, Sendable { let range: NSRange; let kind: MarkdownSpanKind }`
  - `enum MarkdownStyleScanner { static func scan(_ source: String) -> [MarkdownSpan] }`
  - `range` for a `.link` is the full `[text](dest)` span; `textRange` is the `text` portion (used later for reveal-under-caret).

- [ ] **Step 1: Write the failing tests**

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

@Test func scanFindsLinkWithTextAndDestination() {
    let source = "see [setup](guides/setup.md) now"
    let spans = MarkdownStyleScanner.scan(source)
    let link = spans.first { if case .link = $0.kind { return true } else { return false } }
    #expect(link?.range == NSRange(location: 4, length: 24))   // "[setup](guides/setup.md)"
    if case let .link(dest, textRange)? = link?.kind {
        #expect(dest == "guides/setup.md")
        #expect((source as NSString).substring(with: textRange) == "setup")
    } else { Issue.record("expected a link span") }
}

@Test func scanIgnoresImagesAsLinks() {
    let spans = MarkdownStyleScanner.scan("![alt](x.png)")
    #expect(!spans.contains { if case .link = $0.kind { return true } else { return false } })
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path swift/DetDocCore --filter MarkdownStyleScanner`
Expected: FAIL — `cannot find 'MarkdownStyleScanner' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

public enum MarkdownSpanKind: Equatable, Sendable {
    case heading(level: Int)
    case bold
    case italic
    case link(destination: String, textRange: NSRange)
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
        spans.append(contentsOf: links(ns))
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

    private static func links(_ ns: NSString) -> [MarkdownSpan] {
        // [text](dest) not preceded by '!' (which would be an image)
        regex(#"(?<!\!)\[([^\]]*)\]\(([^)\s]+)\)"#)
            .matches(in: ns as String, range: NSRange(location: 0, length: ns.length))
            .map {
                let dest = ns.substring(with: $0.range(at: 2))
                return MarkdownSpan(range: $0.range, kind: .link(destination: dest, textRange: $0.range(at: 1)))
            }
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are static and known-valid; force-try is acceptable here.
        try! NSRegularExpression(pattern: pattern)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path swift/DetDocCore --filter MarkdownStyleScanner`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Services/MarkdownStyleScanner.swift swift/DetDocCore/Tests/DetDocCoreTests/MarkdownStyleScannerTests.swift
git commit -m "feat(core): MarkdownStyleScanner for headings/emphasis/link spans"
```

---

### Task 2: `DocCandidate` + `DocsService.candidates()`

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Models/DocCandidate.swift`
- Modify: `swift/DetDocCore/Sources/DetDocCore/Services/DocsService.swift` (add `candidates()` + a private `firstHeading`)
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/DocCandidateTests.swift`

**Interfaces:**
- Consumes: existing `DocsService.list()` → `[DocFile]` with `path` like `docs/guides/setup.md` and `title` = file name without extension.
- Produces:
  - `struct DocCandidate: Equatable, Sendable { let name: String; let docsRelativePath: String; let title: String? }`
  - `DocsService.candidates() -> [DocCandidate]` — `name` = file name without `.md`; `docsRelativePath` = `path` with the leading `docs/` stripped; `title` = first ATX heading text in the file, or nil.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func candidatesStripDocsPrefixAndReadH1() throws {
    let tmp = TempDir()
    let svc = DocsService(root: tmp.url, config: .default)
    try FileManager.default.createDirectory(at: tmp.url.appendingPathComponent("docs/guides"), withIntermediateDirectories: true)
    try "# Setup Guide\n\nbody".write(to: tmp.url.appendingPathComponent("docs/guides/setup.md"), atomically: true, encoding: .utf8)
    try "no heading".write(to: tmp.url.appendingPathComponent("docs/plain.md"), atomically: true, encoding: .utf8)

    let cands = svc.candidates()
    #expect(cands.contains(DocCandidate(name: "setup", docsRelativePath: "guides/setup.md", title: "Setup Guide")))
    #expect(cands.contains(DocCandidate(name: "plain", docsRelativePath: "plain.md", title: nil)))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path swift/DetDocCore --filter candidatesStripDocsPrefixAndReadH1`
Expected: FAIL — `cannot find 'DocCandidate'` / no member `candidates`.

- [ ] **Step 3: Write the implementation**

`DocCandidate.swift`:
```swift
import Foundation

public struct DocCandidate: Equatable, Sendable {
    public let name: String              // file name without ".md": "setup"
    public let docsRelativePath: String  // "guides/setup.md"
    public let title: String?            // first ATX heading, if any
    public init(name: String, docsRelativePath: String, title: String?) {
        self.name = name; self.docsRelativePath = docsRelativePath; self.title = title
    }
}
```

Add to `DocsService`:
```swift
public func candidates() -> [DocCandidate] {
    list().map { file in
        let rel = file.path.hasPrefix("docs/") ? String(file.path.dropFirst("docs/".count)) : file.path
        return DocCandidate(name: file.title, docsRelativePath: rel, title: firstHeading(file.path))
    }
}

private func firstHeading(_ path: String) -> String? {
    guard let text = try? read(path) else { return nil }
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let t = line.trimmingCharacters(in: .whitespaces)
        let hashes = t.prefix(while: { $0 == "#" }).count
        if hashes >= 1, hashes <= 6, t.dropFirst(hashes).first == " " {
            return String(t.dropFirst(hashes)).trimmingCharacters(in: .whitespaces)
        }
        if !t.isEmpty { return nil }   // first non-blank line isn't a heading
    }
    return nil
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path swift/DetDocCore --filter candidatesStripDocsPrefixAndReadH1`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Models/DocCandidate.swift swift/DetDocCore/Sources/DetDocCore/Services/DocsService.swift swift/DetDocCore/Tests/DetDocCoreTests/DocCandidateTests.swift
git commit -m "feat(core): DocCandidate + DocsService.candidates() with H1 titles"
```

---

### Task 3: `DocLink` — make + internalTarget

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Services/DocLink.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/DocLinkTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `DocLink.make(name: String, docsRelativePath: String) -> String` → `"[name](path)"`.
  - `DocLink.internalTarget(ofDestination: String) -> String?` → the docs-relative `.md` path if the destination is an internal relative `.md` link (strips a trailing `#anchor`, leading `./`); nil for external (`http(s)://`, `mailto:`), pure anchors, or non-`.md`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import DetDocCore

@Test func makeBuildsMarkdownLink() {
    #expect(DocLink.make(name: "setup", docsRelativePath: "guides/setup.md") == "[setup](guides/setup.md)")
}

@Test func internalTargetAcceptsRelativeMd() {
    #expect(DocLink.internalTarget(ofDestination: "guides/setup.md") == "guides/setup.md")
    #expect(DocLink.internalTarget(ofDestination: "./a.md") == "a.md")
    #expect(DocLink.internalTarget(ofDestination: "a.md#section") == "a.md")
}

@Test func internalTargetRejectsExternalAndNonMd() {
    #expect(DocLink.internalTarget(ofDestination: "https://x.com/a.md") == nil)
    #expect(DocLink.internalTarget(ofDestination: "mailto:a@b.com") == nil)
    #expect(DocLink.internalTarget(ofDestination: "#anchor") == nil)
    #expect(DocLink.internalTarget(ofDestination: "image.png") == nil)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path swift/DetDocCore --filter DocLink`
Expected: FAIL — `cannot find 'DocLink' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

public enum DocLink {
    public static func make(name: String, docsRelativePath: String) -> String {
        "[\(name)](\(docsRelativePath))"
    }

    public static func internalTarget(ofDestination destination: String) -> String? {
        let d = destination.trimmingCharacters(in: .whitespaces)
        guard !d.isEmpty, !d.hasPrefix("#") else { return nil }
        guard !d.contains("://"), !d.hasPrefix("mailto:") else { return nil }
        let path = String(d.split(separator: "#", maxSplits: 1).first ?? "")
        let normalized = path.hasPrefix("./") ? String(path.dropFirst(2)) : path
        guard normalized.hasSuffix(".md") else { return nil }
        return normalized
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path swift/DetDocCore --filter DocLink`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Services/DocLink.swift swift/DetDocCore/Tests/DetDocCoreTests/DocLinkTests.swift
git commit -m "feat(core): DocLink make + internalTarget"
```

---

### Task 4: `DocLinkResolver`

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Services/DocLinkResolver.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/DocLinkResolverTests.swift`

**Interfaces:**
- Consumes: `DocLink.internalTarget` (Task 3).
- Produces:
  - `struct DocLinkResolver: Sendable { init(candidates: Set<String>); func resolve(_ destination: String) -> Resolution? }`
  - `DocLinkResolver.Resolution: Equatable, Sendable { let docsRelativePath: String; let docPath: String; let exists: Bool }` — `docPath` is `"docs/" + docsRelativePath` (what `DocEditorViewModel.open` expects). `resolve` returns nil for non-internal destinations.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import DetDocCore

@Test func resolveMarksExistingAndMissing() {
    let r = DocLinkResolver(candidates: ["guides/setup.md"])
    #expect(r.resolve("guides/setup.md") == .init(docsRelativePath: "guides/setup.md", docPath: "docs/guides/setup.md", exists: true))
    #expect(r.resolve("guides/missing.md") == .init(docsRelativePath: "guides/missing.md", docPath: "docs/guides/missing.md", exists: false))
}

@Test func resolveIgnoresExternal() {
    let r = DocLinkResolver(candidates: [])
    #expect(r.resolve("https://x.com") == nil)
    #expect(r.resolve("pic.png") == nil)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path swift/DetDocCore --filter DocLinkResolver`
Expected: FAIL — `cannot find 'DocLinkResolver' in scope`.

- [ ] **Step 3: Write the implementation**

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

    public func resolve(_ destination: String) -> Resolution? {
        guard let target = DocLink.internalTarget(ofDestination: destination) else { return nil }
        return Resolution(docsRelativePath: target, docPath: "docs/\(target)", exists: existing.contains(target))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path swift/DetDocCore --filter DocLinkResolver`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Services/DocLinkResolver.swift swift/DetDocCore/Tests/DetDocCoreTests/DocLinkResolverTests.swift
git commit -m "feat(core): DocLinkResolver for internal link existence"
```

---

## Phase 1 — Editor surface (App)

### Task 5: `LivePreviewTextView` skeleton replaces the split editor

**Files:**
- Create: `swift/DetDocApp/Sources/Workspace/Docs/LivePreviewTextView.swift`
- Modify: `swift/DetDocApp/Sources/Workspace/Docs/DocEditorScreen.swift` (replace the `HStack`+`TextEditor`+`MarkdownPreview` body with `LivePreviewTextView`; delete the private `MarkdownPreview`).

**Interfaces:**
- Consumes: `DocEditorViewModel` (existing `source` getter, `edit(_:)`, `save()`, `isDirty`, `selectedPath`).
- Produces: `struct LivePreviewTextView: NSViewRepresentable` with a `Coordinator: NSObject, NSTextViewDelegate` exposing `var textView: NSTextView?` and `func applyStyling()` (a no-op stub in this task; filled in Task 6). Later tasks add `resolver`, `completion`, `candidatesProvider`, `onFollowLink` parameters.

This task is AppKit wiring; verification is build + run (no unit test).

- [ ] **Step 1: Create the representable (editing only)**

```swift
import SwiftUI
import AppKit
import DetDocCore

struct LivePreviewTextView: NSViewRepresentable {
    @Bindable var editor: DocEditorViewModel

    func makeCoordinator() -> Coordinator { Coordinator(editor: editor) }

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
        context.coordinator.textView = tv
        context.coordinator.applyStyling()
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.editor = editor
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != editor.source {           // external change (open/clear)
            tv.string = editor.source
            context.coordinator.applyStyling()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var editor: DocEditorViewModel
        weak var textView: NSTextView?
        init(editor: DocEditorViewModel) { self.editor = editor }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            editor.edit(tv.string)
            applyStyling()
        }

        func applyStyling() { /* filled in Task 6 */ }
    }
}
```

- [ ] **Step 2: Swap it into `DocEditorScreen`**

Replace the `else { HStack { ... } .toolbar { ... } }` branch body so the editor pane is the live-preview view, and delete the private `MarkdownPreview` struct:

```swift
} else {
    LivePreviewTextView(editor: editor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .principal) { Text(editor.selectedPath ?? "").font(.headline) }
            ToolbarItem { Button("Save") { editor.save() }.disabled(!editor.isDirty) }
        }
}
```

- [ ] **Step 3: Build the app**

Run (from `swift/DetDocApp`): `tuist generate >/dev/null && xcodebuild build -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run the existing editor tests (no regressions)**

Run (from `swift/DetDocApp`): `xcodebuild test -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS' -only-testing:DetDocAppTests/openEditSaveRoundTrips`
Expected: PASS. (Note: the old `previewRendersMarkdown` test asserts on `DocEditorViewModel.previewMarkdown()`, which still exists, so it is unaffected.)

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocApp/Sources/Workspace/Docs/LivePreviewTextView.swift swift/DetDocApp/Sources/Workspace/Docs/DocEditorScreen.swift
git commit -m "feat(app): replace split editor with LivePreviewTextView (TextKit 2)"
```

---

### Task 6: Live inline styling + reveal-raw-under-caret

**Files:**
- Modify: `swift/DetDocApp/Sources/Workspace/Docs/LivePreviewTextView.swift` (implement `applyStyling`)
- Create: `swift/DetDocApp/Sources/Workspace/Docs/MarkdownStyleApplier.swift` (pure helper for "which link spans render styled vs raw given the caret")
- Test: `swift/DetDocApp/Tests/MarkdownStyleApplierTests.swift`

**Interfaces:**
- Consumes: `MarkdownStyleScanner.scan` (Task 1), `MarkdownSpan` (Task 1).
- Produces:
  - `enum MarkdownStyleApplier { static func styledLinkRanges(spans: [MarkdownSpan], caret: NSRange) -> [MarkdownSpan] }` — returns the `.link` spans whose **full range does not contain the caret** (those render as their styled `text`; links touching the caret stay raw for editing).

- [ ] **Step 1: Write the failing test for the pure helper**

```swift
import Foundation
import Testing
@testable import DetDoc
@testable import DetDocCore

@Test func styledLinkRangesExcludesCaretTouchingLink() {
    let link = MarkdownSpan(range: NSRange(location: 4, length: 24),
                            kind: .link(destination: "guides/setup.md", textRange: NSRange(location: 5, length: 5)))
    // caret outside the link -> styled
    #expect(MarkdownStyleApplier.styledLinkRanges(spans: [link], caret: NSRange(location: 0, length: 0)) == [link])
    // caret inside the link -> not styled (raw)
    #expect(MarkdownStyleApplier.styledLinkRanges(spans: [link], caret: NSRange(location: 10, length: 0)).isEmpty)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `swift/DetDocApp`): `tuist generate >/dev/null && xcodebuild test -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS' -only-testing:DetDocAppTests/styledLinkRangesExcludesCaretTouchingLink`
Expected: FAIL — `cannot find 'MarkdownStyleApplier'`.

- [ ] **Step 3: Implement the pure helper**

`MarkdownStyleApplier.swift`:
```swift
import Foundation
import DetDocCore

enum MarkdownStyleApplier {
    static func styledLinkRanges(spans: [MarkdownSpan], caret: NSRange) -> [MarkdownSpan] {
        spans.filter { span in
            guard case .link = span.kind else { return false }
            return !NSLocationInRange(caret.location, NSRange(location: span.range.location, length: span.range.length + 1))
        }
    }
}
```

- [ ] **Step 4: Implement `applyStyling` in the Coordinator**

Replace the stub with:
```swift
func applyStyling() {
    guard let tv = textView, let storage = tv.textStorage else { return }
    let full = NSRange(location: 0, length: (tv.string as NSString).length)
    let caret = tv.selectedRange()
    let spans = MarkdownStyleScanner.scan(tv.string)

    storage.beginEditing()
    storage.setAttributes([
        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
        .foregroundColor: NSColor.textColor,
    ], range: full)

    for span in spans {
        switch span.kind {
        case let .heading(level):
            let size: CGFloat = [1: 22, 2: 19, 3: 16].first { $0.key == level }?.value ?? 14
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: size, weight: .bold), range: span.range)
        case .bold:
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold), range: span.range)
        case .italic:
            if let italic = NSFontManager.shared.convert(.monospacedSystemFont(ofSize: 13, weight: .regular), toHaveTrait: .italicFontMask) as NSFont? {
                storage.addAttribute(.font, value: italic, range: span.range)
            }
        case .link:
            break   // links styled in Task 7 (needs the resolver)
        }
    }
    _ = MarkdownStyleApplier.styledLinkRanges(spans: spans, caret: caret)  // wired in Task 7
    storage.endEditing()
}
```
Also restyle when the caret moves (so links reveal/hide). Add:
```swift
func textViewDidChangeSelection(_ notification: Notification) { applyStyling() }
```

- [ ] **Step 5: Run the helper test + build**

Run (from `swift/DetDocApp`): `xcodebuild test -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS' -only-testing:DetDocAppTests/styledLinkRangesExcludesCaretTouchingLink`
Expected: PASS, BUILD SUCCEEDED.

- [ ] **Step 6: Manual check**

Run the app (`xcodebuild ... -scheme DetDocApp` then launch, or via the project's run flow), open a doc with `# Heading` and `**bold**`; confirm heading is larger/bold and bold text is bold. Typing stays responsive.

- [ ] **Step 7: Commit**

```bash
git add swift/DetDocApp/Sources/Workspace/Docs/LivePreviewTextView.swift swift/DetDocApp/Sources/Workspace/Docs/MarkdownStyleApplier.swift swift/DetDocApp/Tests/MarkdownStyleApplierTests.swift
git commit -m "feat(app): live inline styling for headings/emphasis in editor"
```

---

### Task 7: Internal link styling + cmd-click navigation

**Files:**
- Modify: `swift/DetDocApp/Sources/Workspace/Docs/LivePreviewTextView.swift` (add `resolver`/`onFollowLink`; style links; handle clicks)
- Modify: `swift/DetDocApp/Sources/Workspace/Docs/DocEditorScreen.swift` (pass `resolver` + `onFollowLink`)
- Modify: `swift/DetDocApp/Sources/Workspace/WorkspaceView.swift` (build the resolver from `tree`/docs and route follow → `selectedDoc`)

**Interfaces:**
- Consumes: `DocLinkResolver` (Task 4), `MarkdownStyleApplier.styledLinkRanges` (Task 6), `DocsService.candidates()` (Task 2).
- Produces: `LivePreviewTextView(editor:resolver:onFollowLink:)` where `onFollowLink: (String) -> Void` receives a `docPath` (`"docs/..."`) to open. `DocEditorScreen` gains matching parameters and forwards them.

- [ ] **Step 1: Add params + link styling + click handling to `LivePreviewTextView`**

Add stored properties and thread them into the coordinator:
```swift
struct LivePreviewTextView: NSViewRepresentable {
    @Bindable var editor: DocEditorViewModel
    var resolver: DocLinkResolver
    var onFollowLink: (String) -> Void          // receives a "docs/..." path

    func makeCoordinator() -> Coordinator { Coordinator(editor: editor, resolver: resolver, onFollowLink: onFollowLink) }
    // makeNSView/updateNSView unchanged except: set tv.isAutomaticLinkDetectionEnabled = false
```
In `Coordinator`, store `var resolver` and `let onFollowLink`, and in the `.link` case of `applyStyling` style by existence and tag a clickable link:
```swift
case let .link(destination, _):
    let styledLinks = MarkdownStyleApplier.styledLinkRanges(spans: spans, caret: caret)
    let isStyled = styledLinks.contains(span)
    if let res = resolver.resolve(destination) {
        let color: NSColor = res.exists ? .linkColor : .systemRed
        storage.addAttribute(.foregroundColor, value: color, range: span.range)
        if !res.exists {
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.single.rawValue, range: span.range)
            storage.addAttribute(.toolTip, value: "Missing: \(res.docsRelativePath)", range: span.range)
        }
        if isStyled, res.exists {
            storage.addAttribute(.link, value: "detdoc://\(res.docPath)", range: span.range)
        }
    }
```
Handle the click via the delegate:
```swift
func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
    guard let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:)),
          url.scheme == "detdoc" else { return false }
    let docPath = String(url.absoluteString.dropFirst("detdoc://".count))
    onFollowLink(docPath)
    return true
}
```

- [ ] **Step 2: Forward params from `DocEditorScreen`**

```swift
struct DocEditorScreen: View {
    @Bindable var editor: DocEditorViewModel
    var resolver: DocLinkResolver
    var onFollowLink: (String) -> Void
    // ...
    LivePreviewTextView(editor: editor, resolver: resolver, onFollowLink: onFollowLink)
```

- [ ] **Step 3: Build the resolver and route navigation in `WorkspaceView`**

In `WorkspaceView`, construct a `DocsService`-backed candidate set and pass it down. Add near the other state:
```swift
private var linkResolver: DocLinkResolver {
    let svc = DocsService(root: root, config: (try? ConfigStore().load(root: root)) ?? .default)
    return DocLinkResolver(candidates: Set(svc.candidates().map(\.docsRelativePath)))
}
```
And in the `detail:` closure:
```swift
DocEditorScreen(editor: editor, resolver: linkResolver) { docPath in
    if !tree.isDirectory(docPath) { selectedDoc = docPath }   // reuses onChange(selectedDoc) -> editor.open + tree selection
}
```

- [ ] **Step 4: Build + smoke**

Run (from `swift/DetDocApp`): `tuist generate >/dev/null && xcodebuild build -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Manual check**

Create `docs/a.md` containing `see [b](b.md) and [missing](nope.md)` and a `docs/b.md`. Open `a.md`: `b` renders as a blue link, `missing` is red with a dotted underline; Cmd-click on `b` opens `b.md` and selects it in the tree; the caret on the link reveals the raw `[b](b.md)`.

- [ ] **Step 6: Commit**

```bash
git add swift/DetDocApp/Sources/Workspace/Docs/LivePreviewTextView.swift swift/DetDocApp/Sources/Workspace/Docs/DocEditorScreen.swift swift/DetDocApp/Sources/Workspace/WorkspaceView.swift
git commit -m "feat(app): style + navigate internal doc links in the editor"
```

---

## Phase 2 — `@` picker

### Task 8: `DocLinkCompletion.activeQuery`

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Services/DocLinkCompletion.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/DocLinkCompletionActiveQueryTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct ActiveQuery: Equatable, Sendable { let range: NSRange; let query: String }` (`range` is the `@query` span incl. `@`, UTF-16).
  - `enum DocLinkCompletion { static func activeQuery(in source: String, cursorUTF16Offset: Int) -> ActiveQuery? }` — non-nil only when an `@` at a word boundary (start of text or preceded by whitespace) precedes the cursor with only query chars (`letters`, `digits`, `/ - _ .`) in between.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func activeQueryAtWordBoundary() {
    let q = DocLinkCompletion.activeQuery(in: "see @gu", cursorUTF16Offset: 7)
    #expect(q == ActiveQuery(range: NSRange(location: 4, length: 3), query: "gu"))
}

@Test func activeQueryEmptyRightAfterAt() {
    let q = DocLinkCompletion.activeQuery(in: "@", cursorUTF16Offset: 1)
    #expect(q == ActiveQuery(range: NSRange(location: 0, length: 1), query: ""))
}

@Test func activeQueryRejectsEmailLikeAt() {
    #expect(DocLinkCompletion.activeQuery(in: "mail a@b", cursorUTF16Offset: 8) == nil)
}

@Test func activeQueryStopsAtWhitespace() {
    #expect(DocLinkCompletion.activeQuery(in: "@gu ide", cursorUTF16Offset: 7) == nil)
}

@Test func activeQueryAllowsPathChars() {
    let q = DocLinkCompletion.activeQuery(in: "@guides/se", cursorUTF16Offset: 10)
    #expect(q?.query == "guides/se")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path swift/DetDocCore --filter activeQuery`
Expected: FAIL — `cannot find 'DocLinkCompletion'`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

public struct ActiveQuery: Equatable, Sendable {
    public let range: NSRange
    public let query: String
    public init(range: NSRange, query: String) { self.range = range; self.query = query }
}

public enum DocLinkCompletion {
    public static func activeQuery(in source: String, cursorUTF16Offset: Int) -> ActiveQuery? {
        let ns = source as NSString
        let cursor = max(0, min(cursorUTF16Offset, ns.length))
        var i = cursor
        while i > 0 {
            let c = ns.character(at: i - 1)
            if c == unichar(UInt16(ascii: "@")) {
                let at = i - 1
                let boundary = at == 0 || isWhitespace(ns.character(at: at - 1))
                guard boundary else { return nil }
                let query = ns.substring(with: NSRange(location: i, length: cursor - i))
                return ActiveQuery(range: NSRange(location: at, length: cursor - at), query: query)
            }
            guard isQueryChar(c) else { return nil }
            i -= 1
        }
        return nil
    }

    private static func isQueryChar(_ c: unichar) -> Bool {
        guard let s = Unicode.Scalar(c) else { return false }
        let ch = Character(s)
        return ch.isLetter || ch.isNumber || "/-_.".contains(ch)
    }
    private static func isWhitespace(_ c: unichar) -> Bool {
        guard let s = Unicode.Scalar(c) else { return false }
        return Character(s).isWhitespace
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path swift/DetDocCore --filter activeQuery`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Services/DocLinkCompletion.swift swift/DetDocCore/Tests/DetDocCoreTests/DocLinkCompletionActiveQueryTests.swift
git commit -m "feat(core): DocLinkCompletion.activeQuery tokenizer"
```

---

### Task 9: `DocLinkCompletion.suggestions`

**Files:**
- Modify: `swift/DetDocCore/Sources/DetDocCore/Services/DocLinkCompletion.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/DocLinkCompletionSuggestionsTests.swift`

**Interfaces:**
- Consumes: `DocCandidate` (Task 2).
- Produces: `DocLinkCompletion.suggestions(query: String, candidates: [DocCandidate]) -> [DocCandidate]` — case-insensitive; empty query returns all; prefix matches (on path or name) rank first, then earliest substring in path, then title-only matches, then alphabetical by path.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import DetDocCore

private let cands = [
    DocCandidate(name: "setup", docsRelativePath: "guides/setup.md", title: "Setup Guide"),
    DocCandidate(name: "glossary", docsRelativePath: "guides/glossary.md", title: "Glossary"),
    DocCandidate(name: "arch", docsRelativePath: "arch.md", title: "Guidelines"),
]

@Test func suggestionsEmptyQueryReturnsAll() {
    #expect(DocLinkCompletion.suggestions(query: "", candidates: cands).count == 3)
}

@Test func suggestionsPrefixRanksFirst() {
    let r = DocLinkCompletion.suggestions(query: "gu", candidates: cands)
    #expect(r.first?.docsRelativePath == "guides/glossary.md" || r.first?.docsRelativePath == "guides/setup.md")
    #expect(r.allSatisfy { $0.docsRelativePath.lowercased().contains("gu") || ($0.title ?? "").lowercased().contains("gu") })
}

@Test func suggestionsTitleOnlyMatchIncluded() {
    let r = DocLinkCompletion.suggestions(query: "guidel", candidates: cands)
    #expect(r.map(\.docsRelativePath) == ["arch.md"])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path swift/DetDocCore --filter suggestions`
Expected: FAIL — no member `suggestions`.

- [ ] **Step 3: Add the implementation**

```swift
extension DocLinkCompletion {
    public static func suggestions(query: String, candidates: [DocCandidate]) -> [DocCandidate] {
        let q = query.lowercased()
        guard !q.isEmpty else { return candidates }
        let ranked: [(DocCandidate, Int)] = candidates.compactMap { c in
            let path = c.docsRelativePath.lowercased()
            if let r = path.range(of: q) {
                let isPrefix = path.hasPrefix(q) || c.name.lowercased().hasPrefix(q)
                let offset = path.distance(from: path.startIndex, to: r.lowerBound)
                return (c, isPrefix ? 0 : 1 + offset)
            }
            if (c.title ?? "").lowercased().contains(q) { return (c, 1000) }
            return nil
        }
        return ranked.sorted {
            $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.docsRelativePath < $1.0.docsRelativePath
        }.map(\.0)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path swift/DetDocCore --filter suggestions`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Services/DocLinkCompletion.swift swift/DetDocCore/Tests/DetDocCoreTests/DocLinkCompletionSuggestionsTests.swift
git commit -m "feat(core): DocLinkCompletion.suggestions ranking"
```

---

### Task 10: `DocLinkCompletionModel`

**Files:**
- Create: `swift/DetDocApp/Sources/Workspace/Docs/DocLinkCompletionModel.swift`
- Test: `swift/DetDocApp/Tests/DocLinkCompletionModelTests.swift`

**Interfaces:**
- Consumes: `ActiveQuery` (Task 8), `DocLinkCompletion.suggestions` (Task 9), `DocLink.make` (Task 3), `DocCandidate` (Task 2).
- Produces:
  - `@MainActor @Observable final class DocLinkCompletionModel` with `isActive`, `query`, `items: [DocCandidate]`, `selectedIndex`, `caretRect: CGRect`.
  - `func begin(query:caretRect:candidates:)`, `func update(query:caretRect:candidates:)`, `func moveUp()`, `func moveDown()`, `func cancel()`, `func commit() -> Insertion?`.
  - `struct Insertion: Equatable { let text: String; let range: NSRange }` — `text` is `[name](path)`, `range` is the `@query` span to replace.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import DetDoc
@testable import DetDocCore

private let cands = [
    DocCandidate(name: "setup", docsRelativePath: "guides/setup.md", title: nil),
    DocCandidate(name: "glossary", docsRelativePath: "guides/glossary.md", title: nil),
]

@MainActor @Test func beginPopulatesAndCommitsSelectedLink() {
    let m = DocLinkCompletionModel()
    m.begin(query: ActiveQuery(range: NSRange(location: 0, length: 3), query: "gu"), caretRect: .zero, candidates: cands)
    #expect(m.isActive)
    #expect(m.items.count == 2)
    m.moveDown()
    let ins = m.commit()
    #expect(ins == DocLinkCompletionModel.Insertion(text: "[glossary](guides/glossary.md)", range: NSRange(location: 0, length: 3)))
    #expect(m.isActive == false)
}

@MainActor @Test func moveDownWrapsAndCancelDeactivates() {
    let m = DocLinkCompletionModel()
    m.begin(query: ActiveQuery(range: NSRange(location: 0, length: 1), query: ""), caretRect: .zero, candidates: cands)
    m.moveDown(); m.moveDown()                 // 0 -> 1 -> wrap 0
    #expect(m.selectedIndex == 0)
    m.cancel()
    #expect(m.isActive == false)
    #expect(m.commit() == nil)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run (from `swift/DetDocApp`): `tuist generate >/dev/null && xcodebuild test -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS' -only-testing:DetDocAppTests/beginPopulatesAndCommitsSelectedLink`
Expected: FAIL — `cannot find 'DocLinkCompletionModel'`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation
import Observation
import DetDocCore

@MainActor
@Observable
public final class DocLinkCompletionModel {
    public private(set) var isActive = false
    public private(set) var query = ""
    public private(set) var items: [DocCandidate] = []
    public private(set) var selectedIndex = 0
    public private(set) var caretRect: CGRect = .zero
    private var replaceRange = NSRange(location: 0, length: 0)

    public struct Insertion: Equatable {
        public let text: String
        public let range: NSRange
    }

    public init() {}

    public func begin(query: ActiveQuery, caretRect: CGRect, candidates: [DocCandidate]) {
        isActive = true
        selectedIndex = 0
        update(query: query, caretRect: caretRect, candidates: candidates)
    }

    public func update(query q: ActiveQuery, caretRect: CGRect, candidates: [DocCandidate]) {
        query = q.query
        replaceRange = q.range
        self.caretRect = caretRect
        items = DocLinkCompletion.suggestions(query: q.query, candidates: candidates)
        if selectedIndex >= items.count { selectedIndex = max(0, items.count - 1) }
    }

    public func moveUp() { if !items.isEmpty { selectedIndex = (selectedIndex - 1 + items.count) % items.count } }
    public func moveDown() { if !items.isEmpty { selectedIndex = (selectedIndex + 1) % items.count } }

    public func cancel() { isActive = false; items = []; query = "" }

    public func commit() -> Insertion? {
        guard isActive, items.indices.contains(selectedIndex) else { return nil }
        let c = items[selectedIndex]
        isActive = false
        return Insertion(text: DocLink.make(name: c.name, docsRelativePath: c.docsRelativePath), range: replaceRange)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run (from `swift/DetDocApp`): `xcodebuild test -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS' -only-testing:DetDocAppTests/beginPopulatesAndCommitsSelectedLink -only-testing:DetDocAppTests/moveDownWrapsAndCancelDeactivates`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocApp/Sources/Workspace/Docs/DocLinkCompletionModel.swift swift/DetDocApp/Tests/DocLinkCompletionModelTests.swift
git commit -m "feat(app): DocLinkCompletionModel picker state"
```

---

### Task 11: `DocLinkSuggestionsView` (Liquid Glass popover)

**Files:**
- Create: `swift/DetDocApp/Sources/Workspace/Docs/DocLinkSuggestionsView.swift`

**Interfaces:**
- Consumes: `DocLinkCompletionModel` (Task 10), `DocCandidate` (Task 2).
- Produces: `struct DocLinkSuggestionsView: View { init(model: DocLinkCompletionModel, onPick: @escaping (Int) -> Void) }` — the glass list matching the approved mockup (compact single-line rows: doc icon + docs-relative path with matched prefix highlighted; selected row = tinted-glass capsule; empty state row).

No unit test (pure view); verified visually in Task 12.

- [ ] **Step 1: Implement the view**

```swift
import SwiftUI
import DetDocCore

struct DocLinkSuggestionsView: View {
    @Bindable var model: DocLinkCompletionModel
    var onPick: (Int) -> Void

    var body: some View {
        Group {
            if model.items.isEmpty {
                Text("Нет документов").font(.system(size: 13)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.items.enumerated()), id: \.offset) { i, c in
                        row(c, selected: i == model.selectedIndex)
                            .contentShape(Rectangle())
                            .onTapGesture { onPick(i) }
                    }
                }
            }
        }
        .padding(6)
        .frame(width: 324, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder private func row(_ c: DocCandidate, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text").font(.system(size: 12)).foregroundStyle(selected ? .white : .secondary)
            highlighted(c.docsRelativePath, query: model.query, selected: selected)
                .font(.system(size: 13, design: .monospaced))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if selected { Capsule().glassEffect(.regular.tint(.accentColor).interactive(), in: Capsule()) }
        }
    }

    private func highlighted(_ path: String, query: String, selected: Bool) -> Text {
        let base: Color = selected ? .white : .primary
        guard !query.isEmpty, let r = path.range(of: query, options: .caseInsensitive) else {
            return Text(path).foregroundStyle(base)
        }
        return Text(path[path.startIndex..<r.lowerBound]).foregroundStyle(base)
            + Text(path[r]).foregroundStyle(selected ? .white : .accentColor).bold()
            + Text(path[r.upperBound...]).foregroundStyle(base)
    }
}
```

- [ ] **Step 2: Build**

Run (from `swift/DetDocApp`): `tuist generate >/dev/null && xcodebuild build -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add swift/DetDocApp/Sources/Workspace/Docs/DocLinkSuggestionsView.swift
git commit -m "feat(app): Liquid Glass DocLinkSuggestionsView"
```

---

### Task 12: Wire the picker into `LivePreviewTextView`

**Files:**
- Modify: `swift/DetDocApp/Sources/Workspace/Docs/LivePreviewTextView.swift` (own a `DocLinkCompletionModel`, a candidates provider, a popover panel; detect `@`, position, route keys, apply insertion)
- Modify: `swift/DetDocApp/Sources/Workspace/Docs/DocEditorScreen.swift` (pass a `candidatesProvider`)
- Modify: `swift/DetDocApp/Sources/Workspace/WorkspaceView.swift` (provide candidates from `DocsService`)

**Interfaces:**
- Consumes: `DocLinkCompletion.activeQuery` (Task 8), `DocLinkCompletionModel` (Task 10), `DocLinkSuggestionsView` (Task 11), `DocsService.candidates()` (Task 2).
- Produces: `LivePreviewTextView(editor:resolver:candidatesProvider:onFollowLink:)` where `candidatesProvider: () -> [DocCandidate]`.

AppKit/TextKit wiring; verified by build + manual interaction.

- [ ] **Step 1: Add the model, candidates provider, and a popover panel to the coordinator**

Add the parameter and coordinator state:
```swift
var candidatesProvider: () -> [DocCandidate]
// makeCoordinator passes candidatesProvider into the Coordinator
```
In `Coordinator` add:
```swift
let completion = DocLinkCompletionModel()
let candidatesProvider: () -> [DocCandidate]
private var panel: NSPanel?
private lazy var cachedCandidates: [DocCandidate] = []

private func showPanel() {
    let host = NSHostingController(rootView: DocLinkSuggestionsView(model: completion) { [weak self] i in
        self?.completion.selectByTap(i); self?.commitCompletion()
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
    if rect == .zero { rect = tv.firstRect(forCharacterRange: NSRange(location: max(0, caret.location - 1), length: 1), actualRange: nil) }
    panel.setFrameTopLeftPoint(NSPoint(x: rect.minX, y: rect.minY - 6))
    if panel.parent == nil { win.addChildWindow(panel, ordered: .above) }
}
private func hidePanel() { panel?.orderOut(nil); if let p = panel { p.parent?.removeChildWindow(p) }; panel = nil }
```
Add `selectByTap` to the model (Task 10 file) so a click can set the index:
```swift
public func selectByTap(_ i: Int) { if items.indices.contains(i) { selectedIndex = i } }
```

- [ ] **Step 2: Detect `@` on edit + selection change**

In the coordinator, after `editor.edit` / styling, call `updateCompletion()`:
```swift
private func updateCompletion() {
    guard let tv = textView else { return }
    let cursor = tv.selectedRange().location
    guard let q = DocLinkCompletion.activeQuery(in: tv.string, cursorUTF16Offset: cursor) else {
        if completion.isActive { completion.cancel(); hidePanel() }
        return
    }
    if !completion.isActive { cachedCandidates = candidatesProvider() }
    let wasActive = completion.isActive
    let rect = caretRectForPanel()
    if wasActive { completion.update(query: q, caretRect: rect, candidates: cachedCandidates) }
    else { completion.begin(query: q, caretRect: rect, candidates: cachedCandidates) }
    if panel == nil { showPanel() }
    positionPanel()
}
private func caretRectForPanel() -> CGRect { textView?.selectedRange() != nil ? .zero : .zero } // panel uses screen rect directly
```
Call `updateCompletion()` from both `textDidChange` and `textViewDidChangeSelection` (after `applyStyling`).

- [ ] **Step 3: Route keys while active**

```swift
func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    guard completion.isActive else { return false }
    switch selector {
    case #selector(NSResponder.moveUp(_:)): completion.moveUp(); return true
    case #selector(NSResponder.moveDown(_:)): completion.moveDown(); return true
    case #selector(NSResponder.insertNewline(_:)): commitCompletion(); return true
    case #selector(NSResponder.cancelOperation(_:)): completion.cancel(); hidePanel(); return true
    default: return false
    }
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
    applyStyling()
}
```

- [ ] **Step 4: Pass the candidates provider down**

In `DocEditorScreen` add `var candidatesProvider: () -> [DocCandidate]` and forward it; in `WorkspaceView`:
```swift
DocEditorScreen(editor: editor, resolver: linkResolver,
                candidatesProvider: {
                    let svc = DocsService(root: root, config: (try? ConfigStore().load(root: root)) ?? .default)
                    return svc.candidates()
                }) { docPath in
    if !tree.isDirectory(docPath) { selectedDoc = docPath }
}
```

- [ ] **Step 5: Build + manual check**

Run (from `swift/DetDocApp`): `tuist generate >/dev/null && xcodebuild build -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.
Then run the app, open a doc, type `@gu`: the glass popover appears at the caret with matching docs; ↑/↓ move selection; ↵ inserts `[setup](guides/setup.md)` replacing `@gu`; esc dismisses.

- [ ] **Step 6: Commit**

```bash
git add swift/DetDocApp/Sources/Workspace/Docs/LivePreviewTextView.swift swift/DetDocApp/Sources/Workspace/Docs/DocLinkCompletionModel.swift swift/DetDocApp/Sources/Workspace/Docs/DocEditorScreen.swift swift/DetDocApp/Sources/Workspace/WorkspaceView.swift
git commit -m "feat(app): @-triggered doc link picker in the editor"
```

---

## Phase 3 — Polish

### Task 13: Dismissal, empty state, and incremental restyle

**Files:**
- Modify: `swift/DetDocApp/Sources/Workspace/Docs/LivePreviewTextView.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/DocLinkCompletionActiveQueryTests.swift` (add edge cases)

**Interfaces:**
- Consumes: everything above. No new public API.

- [ ] **Step 1: Add tokenizer edge-case tests**

```swift
@Test func activeQueryNilWhenCursorBeforeAt() {
    #expect(DocLinkCompletion.activeQuery(in: "@gu", cursorUTF16Offset: 0) == nil)
}

@Test func activeQueryHandlesCyrillicBeforeAt() {
    // "слово @s" — '@' preceded by a space after a Cyrillic word still triggers
    let src = "слово @s"
    let q = DocLinkCompletion.activeQuery(in: src, cursorUTF16Offset: (src as NSString).length)
    #expect(q?.query == "s")
}
```

- [ ] **Step 2: Run them (red → implement is already green for these; confirm)**

Run: `swift test --package-path swift/DetDocCore --filter activeQuery`
Expected: PASS (existing impl already satisfies these; if `activeQueryHandlesCyrillicBeforeAt` fails, the boundary check must use scalar whitespace as written — it does).

- [ ] **Step 3: Harden dismissal + blur in the coordinator**

```swift
func textViewDidChangeSelection(_ notification: Notification) {
    applyStyling()
    updateCompletion()
}
// Dismiss when the text view loses focus.
func textDidEndEditing(_ notification: Notification) {
    if completion.isActive { completion.cancel(); hidePanel() }
}
```

- [ ] **Step 4: Avoid full restyle thrash on large docs**

Guard styling to run only when text actually changed since last style pass:
```swift
private var lastStyledString: String = ""
// at the top of applyStyling(), after fetching tv:
if tv.string == lastStyledString, !forceRestyle { /* still re-evaluate caret-driven link reveal */ }
lastStyledString = tv.string
```
Keep it simple: cache `lastStyledString`; on selection-only changes, re-run scan but skip if the string is unchanged AND no link span is adjacent to the caret. (A full re-scan per keystroke is acceptable for typical doc sizes; this guard only prevents redundant work on pure cursor moves.)

- [ ] **Step 5: Build + manual check**

Run (from `swift/DetDocApp`): `tuist generate >/dev/null && xcodebuild build -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED. Manually: typing `@zzz` with no match shows the "Нет документов" empty state; clicking elsewhere / esc dismisses; large docs stay responsive.

- [ ] **Step 6: Run the full suites**

Run: `swift test --package-path swift/DetDocCore`
Run (from `swift/DetDocApp`): `tuist generate >/dev/null && xcodebuild test -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS'`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add swift/DetDocApp/Sources/Workspace/Docs/LivePreviewTextView.swift swift/DetDocCore/Tests/DetDocCoreTests/DocLinkCompletionActiveQueryTests.swift
git commit -m "feat(app): picker dismissal, empty state, restyle guard"
```

---

## Self-review checklist (done while writing)

- **Spec coverage:** `@` trigger + insertion (Tasks 8–12); stored `[name](path.md)` (Task 3); link text = file name w/o `.md` (Task 2 `name`, Task 3 `make`); docs-relative paths (Tasks 2/4); inline link styling + reveal-under-caret (Tasks 6/7); cmd-click navigation (Task 7); broken-link highlight (Task 7); Liquid Glass popper light/dark (Task 11); single live-preview surface replacing the split editor (Task 5); core unit tests for `activeQuery`/`suggestions`/`make`/`resolve`/`candidates`/scanner (Tasks 1–4, 8, 9); model transitions (Task 10). Images/canvas are explicitly out of scope (spec) — no tasks, by design.
- **Type consistency:** `ActiveQuery`, `DocCandidate`, `DocLinkResolver.Resolution`, `DocLinkCompletionModel.Insertion`, and method names (`activeQuery`, `suggestions`, `make`, `internalTarget`, `resolve`, `candidates`, `scan`, `styledLinkRanges`, `begin/update/moveUp/moveDown/cancel/commit/selectByTap`) match across producing and consuming tasks.
- **Placeholder scan:** no TBD/TODO; every code step shows the code; `applyStyling` link branch is explicitly deferred from Task 6 to Task 7 with the consuming code shown in Task 7.
- **Deviation:** `swift-markdown` intentionally not adopted (see Notes) — flagged for the reviewer.
