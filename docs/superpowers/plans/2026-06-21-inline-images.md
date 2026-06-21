# Inline Images Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user drag or paste an image into the Markdown editor and have it render inline as a compact preview, stored on disk next to the document and referenced via an `@`-token.

**Architecture:** Image tokens reuse the existing `@<path>` syntax, classified by file extension. A shared `AtTokenScanner` produces raw tokens; `DocRefScanner` keeps the non-image ones, a new `ImageRefScanner` keeps the image ones. A core `DocImageImporter` copies files into an `assets/` folder beside the document and resolves tokens back to file URLs. The editor's TextKit 2 content-storage delegate replaces image tokens with a `DocImageAttachment` preview (collapsing/revealing on caret movement, exactly like the doc-link bubbles). A `NSTextView` subclass intercepts drag/paste of image data.

**Tech Stack:** Swift 6, SwiftUI, AppKit, TextKit 2 (`NSTextLayoutManager`/`NSTextContentStorage`), Swift Testing, Quartz (`QLPreviewPanel`). Core is an SwiftPM package (`swift/DetDocCore`); the app is a Tuist project (`swift/DetDocApp`).

## Global Constraints

- Swift tools version 6.4; core builds with `swiftSettings: [.treatAllWarnings(as: .error)]` — **no warnings allowed** in `DetDocCore`.
- Platform: macOS 27.
- Core tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`) — not XCTest.
- Image tokens are **docs-root-relative**, like doc links: `@guides/assets/x.png` → `<root>/docs/guides/assets/x.png`.
- Recognized image extensions (lowercased): `png`, `jpg`, `jpeg`, `gif`, `heic`, `webp`.
- `editor.selectedPath` is root-relative **including** the `docs/` prefix (e.g. `docs/guides/setup.md`).
- App target uses `buildableFolders: ["Sources"]` — new files under `Sources/` are picked up automatically; no `tuist generate` needed for added files (only if the `.xcodeproj` does not yet exist).

## Commands

- Core tests (filtered): `swift test --package-path swift/DetDocCore --filter <name>`
- Core tests (all): `swift test --package-path swift/DetDocCore`
- App build (from `swift/DetDocApp`): `xcodebuild build -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS'`
  - If `DetDocApp.xcodeproj` does not exist yet: run `tuist generate` first (in `swift/DetDocApp`).

---

### Task 1: Image-token recognition (core)

Split the existing `@`-token tokenizer out of `DocRefScanner`, add `ImageRef`/`ImageRefScanner`, and make `DocRefScanner` ignore image-extension tokens so the two scanners own disjoint token sets.

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Services/AtToken.swift`
- Create: `swift/DetDocCore/Sources/DetDocCore/Services/ImageRef.swift`
- Modify: `swift/DetDocCore/Sources/DetDocCore/Services/DocRef.swift`
- Test (create): `swift/DetDocCore/Tests/DetDocCoreTests/ImageRefTests.swift`
- Test (modify): `swift/DetDocCore/Tests/DetDocCoreTests/DocRefTests.swift`

**Interfaces:**
- Produces:
  - `struct ImageRef: Equatable, Sendable { let range: NSRange; let path: String }`
  - `enum ImageRefScanner` with `static let imageExtensions: Set<String>`, `static func isImagePath(_ path: String) -> Bool`, `static func scan(_ text: String) -> [ImageRef]`
  - (internal) `struct AtToken`, `enum AtTokenScanner` with `static func scan(_ text: String) -> [AtToken]`
  - `DocRefScanner.scan` now excludes tokens where `ImageRefScanner.isImagePath(path)` is true (same public signature).

- [ ] **Step 1: Write the failing ImageRef tests**

Create `swift/DetDocCore/Tests/DetDocCoreTests/ImageRefTests.swift`:

```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func imageScanFindsPngToken() {
    let refs = ImageRefScanner.scan("see @guides/assets/window.png here")
    #expect(refs.count == 1)
    #expect(refs[0].path == "guides/assets/window.png")
    // range covers "@guides/assets/window.png" = 25 chars at offset 4
    #expect(refs[0].range == NSRange(location: 4, length: 25))
}

@Test func imageScanRecognizesAllExtensions() {
    for ext in ["png", "jpg", "jpeg", "gif", "heic", "webp"] {
        let refs = ImageRefScanner.scan("@a/b.\(ext)")
        #expect(refs.count == 1, "expected \(ext) to be an image")
    }
}

@Test func imageScanIsCaseInsensitiveOnExtension() {
    let refs = ImageRefScanner.scan("@a/B.PNG")
    #expect(refs.count == 1)
    #expect(refs[0].path == "a/B.PNG")
}

@Test func imageScanIgnoresNonImageTokens() {
    #expect(ImageRefScanner.scan("@guides/setup").isEmpty)
    #expect(ImageRefScanner.scan("@a/b.txt").isEmpty)
}

@Test func imageScanTrimsTrailingPunctuation() {
    // trailing sentence dot is not part of the path; ".png" stays
    let refs = ImageRefScanner.scan("img @a/b.png.")
    #expect(refs.count == 1)
    #expect(refs[0].path == "a/b.png")
    #expect(refs[0].range == NSRange(location: 4, length: 8)) // "@a/b.png"
}

@Test func isImagePathClassifies() {
    #expect(ImageRefScanner.isImagePath("x/y.png"))
    #expect(ImageRefScanner.isImagePath("x/y.JPEG"))
    #expect(!ImageRefScanner.isImagePath("x/y"))
    #expect(!ImageRefScanner.isImagePath("x/y.md"))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path swift/DetDocCore --filter imageScan`
Expected: FAIL — `cannot find 'ImageRefScanner' in scope`.

- [ ] **Step 3: Create the shared tokenizer**

Create `swift/DetDocCore/Sources/DetDocCore/Services/AtToken.swift`:

```swift
import Foundation

/// A raw `@<path>` token found in text, before classification into doc-ref vs image-ref.
struct AtToken: Equatable {
    let range: NSRange   // covers "@path" including the leading @
    let path: String     // path without the @, trailing "./-_" punctuation trimmed
}

enum AtTokenScanner {
    /// Finds `@<path>` tokens where `@` is at a word boundary (start of text or
    /// preceded by whitespace) and is followed by >=1 path char (letters, digits,
    /// and `/ - _ .`). Trailing `./-_` punctuation is trimmed from the path.
    static func scan(_ text: String) -> [AtToken] {
        let ns = text as NSString
        let re = try! NSRegularExpression(pattern: #"(?<![^\s])@([\p{L}\p{N}/_.\-]+)"#)
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let full = m.range
            var path = ns.substring(with: m.range(at: 1))
            var len = full.length
            while let last = path.last, "./-_".contains(last) { path.removeLast(); len -= 1 }
            guard !path.isEmpty else { return nil }
            return AtToken(range: NSRange(location: full.location, length: len), path: path)
        }
    }
}
```

- [ ] **Step 4: Create ImageRef + ImageRefScanner**

Create `swift/DetDocCore/Sources/DetDocCore/Services/ImageRef.swift`:

```swift
import Foundation

public struct ImageRef: Equatable, Sendable {
    public let range: NSRange   // covers "@guides/assets/window.png" (includes the @)
    public let path: String     // docs-relative path WITH extension, e.g. "guides/assets/window.png"
    public init(range: NSRange, path: String) { self.range = range; self.path = path }
}

public enum ImageRefScanner {
    /// Image file extensions recognized as inline-image tokens (lowercased).
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp"]

    /// True if `path`'s extension is a recognized image extension (case-insensitive).
    public static func isImagePath(_ path: String) -> Bool {
        guard let dot = path.lastIndex(of: "."), dot < path.index(before: path.endIndex) else { return false }
        let ext = path[path.index(after: dot)...].lowercased()
        return imageExtensions.contains(ext)
    }

    /// Finds `@<path>` tokens whose path ends in a recognized image extension.
    public static func scan(_ text: String) -> [ImageRef] {
        AtTokenScanner.scan(text).compactMap { tok in
            guard isImagePath(tok.path) else { return nil }
            return ImageRef(range: tok.range, path: tok.path)
        }
    }
}
```

- [ ] **Step 5: Refactor DocRefScanner onto the shared tokenizer + exclude image tokens**

Replace the body of `swift/DetDocCore/Sources/DetDocCore/Services/DocRef.swift` with:

```swift
import Foundation

public struct DocRef: Equatable, Sendable {
    public let range: NSRange   // covers "@guides/setup" (includes the @)
    public let path: String     // docs-relative path WITHOUT .md, e.g. "guides/setup"
    public init(range: NSRange, path: String) { self.range = range; self.path = path }
}

public enum DocRefScanner {
    /// Finds `@<path>` doc-link tokens. Tokens whose path ends in a recognized image
    /// extension are owned by `ImageRefScanner` and excluded here.
    public static func scan(_ text: String) -> [DocRef] {
        AtTokenScanner.scan(text).compactMap { tok in
            guard !ImageRefScanner.isImagePath(tok.path) else { return nil }
            return DocRef(range: tok.range, path: tok.path)
        }
    }
}
```

- [ ] **Step 6: Add the DocRef regression test**

Append to `swift/DetDocCore/Tests/DetDocCoreTests/DocRefTests.swift`:

```swift
@Test func scanExcludesImageExtensionTokens() {
    // A token with an image extension is NOT a doc ref (it belongs to ImageRefScanner).
    let refs = DocRefScanner.scan("@guides/assets/window.png and @guides/setup")
    #expect(refs.count == 1)
    #expect(refs[0].path == "guides/setup")
}
```

- [ ] **Step 7: Run the full core suite to verify pass**

Run: `swift test --package-path swift/DetDocCore`
Expected: PASS — new `imageScan*`/`isImagePath*` tests pass, the new `scanExcludesImageExtensionTokens` passes, and all pre-existing `DocRefTests` still pass.

- [ ] **Step 8: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Services/AtToken.swift \
        swift/DetDocCore/Sources/DetDocCore/Services/ImageRef.swift \
        swift/DetDocCore/Sources/DetDocCore/Services/DocRef.swift \
        swift/DetDocCore/Tests/DetDocCoreTests/ImageRefTests.swift \
        swift/DetDocCore/Tests/DetDocCoreTests/DocRefTests.swift
git commit -m "feat(core): ImageRefScanner + shared @-token tokenizer; DocRef excludes images"
```

---

### Task 2: DocImageImporter (core)

Copy/write dragged images into the doc's `assets/` folder and resolve tokens back to file URLs.

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Services/DocImageImporter.swift`
- Test (create): `swift/DetDocCore/Tests/DetDocCoreTests/DocImageImporterTests.swift`

**Interfaces:**
- Consumes: `DetDocError` (existing, `init(_ code: String, _ message: String)`).
- Produces:
  - `struct DocImageImporter: Sendable { init(root: URL) }`
  - `func importFile(at sourceURL: URL, forDoc docPath: String) throws -> String` — returns docs-relative token path (e.g. `guides/assets/window.png`).
  - `func importData(_ data: Data, basename: String, ext: String = "png", forDoc docPath: String) throws -> String`
  - `func resolve(_ tokenPath: String) -> URL?` — absolute file URL iff the file exists.
  - (internal) `func assetsDir(forDoc docPath: String) -> (dir: URL, tokenPrefix: String)`

- [ ] **Step 1: Write the failing importer tests**

Create `swift/DetDocCore/Tests/DetDocCoreTests/DocImageImporterTests.swift`:

```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func importFileCopiesAndReturnsTokenPath() throws {
    let tmp = TempDir()
    let importer = DocImageImporter(root: tmp.url)
    let src = tmp.url.appendingPathComponent("window.png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: src)

    let token = try importer.importFile(at: src, forDoc: "docs/guides/setup.md")
    #expect(token == "guides/assets/window.png")
    let dest = tmp.url.appendingPathComponent("docs/guides/assets/window.png")
    #expect(FileManager.default.fileExists(atPath: dest.path))
}

@Test func importFileDedupesOnCollision() throws {
    let tmp = TempDir()
    let importer = DocImageImporter(root: tmp.url)
    let src = tmp.url.appendingPathComponent("window.png")
    try Data([0x89]).write(to: src)

    let t1 = try importer.importFile(at: src, forDoc: "docs/guides/setup.md")
    let t2 = try importer.importFile(at: src, forDoc: "docs/guides/setup.md")
    #expect(t1 == "guides/assets/window.png")
    #expect(t2 == "guides/assets/window-1.png")
}

@Test func importFileForRootDocUsesDocsAssets() throws {
    let tmp = TempDir()
    let importer = DocImageImporter(root: tmp.url)
    let src = tmp.url.appendingPathComponent("a.png")
    try Data([0x89]).write(to: src)

    let token = try importer.importFile(at: src, forDoc: "docs/idea.md")
    #expect(token == "assets/a.png")
}

@Test func importDataWritesPng() throws {
    let tmp = TempDir()
    let importer = DocImageImporter(root: tmp.url)
    let token = try importer.importData(Data([0x89, 0x50]), basename: "image-20260621-143000",
                                        forDoc: "docs/features/auth/brief.md")
    #expect(token == "features/auth/assets/image-20260621-143000.png")
    let dest = tmp.url.appendingPathComponent("docs/features/auth/assets/image-20260621-143000.png")
    #expect(FileManager.default.fileExists(atPath: dest.path))
}

@Test func resolveReturnsURLWhenPresentNilWhenMissing() throws {
    let tmp = TempDir()
    let importer = DocImageImporter(root: tmp.url)
    #expect(importer.resolve("guides/assets/window.png") == nil)

    let src = tmp.url.appendingPathComponent("window.png")
    try Data([0x89]).write(to: src)
    let token = try importer.importFile(at: src, forDoc: "docs/guides/setup.md")
    let url = importer.resolve(token)
    #expect(url != nil)
    #expect(url?.lastPathComponent == "window.png")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path swift/DetDocCore --filter importFile`
Expected: FAIL — `cannot find 'DocImageImporter' in scope`.

- [ ] **Step 3: Implement DocImageImporter**

Create `swift/DetDocCore/Sources/DetDocCore/Services/DocImageImporter.swift`:

```swift
import Foundation

/// Imports dragged/pasted images into the `assets/` folder next to a document and
/// resolves image tokens back to absolute file URLs for rendering.
public struct DocImageImporter: Sendable {
    private let root: URL
    public init(root: URL) { self.root = root }

    /// Copies the file at `sourceURL` into `<docDir>/assets/` (deduping the name)
    /// and returns the docs-relative token path, e.g. "guides/assets/window.png".
    public func importFile(at sourceURL: URL, forDoc docPath: String) throws -> String {
        let (dir, tokenPrefix) = assetsDir(forDoc: docPath)
        let name = uniqueName(sourceURL.lastPathComponent, in: dir)
        let dest = dir.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: dest)
        } catch {
            throw DetDocError("IMAGE_IMPORT_FAILED", "\(sourceURL.lastPathComponent): \(error)")
        }
        return "\(tokenPrefix)/\(name)"
    }

    /// Writes `data` into `<docDir>/assets/<basename>.<ext>` (deduping) and returns
    /// the docs-relative token path. The caller supplies `basename` (e.g. a timestamp)
    /// so the clock stays out of core.
    public func importData(_ data: Data, basename: String, ext: String = "png",
                           forDoc docPath: String) throws -> String {
        let (dir, tokenPrefix) = assetsDir(forDoc: docPath)
        let name = uniqueName("\(basename).\(ext)", in: dir)
        let dest = dir.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dest)
        } catch {
            throw DetDocError("IMAGE_IMPORT_FAILED", "\(basename).\(ext): \(error)")
        }
        return "\(tokenPrefix)/\(name)"
    }

    /// Returns the absolute file URL for an image token path iff the file exists.
    public func resolve(_ tokenPath: String) -> URL? {
        let clean = tokenPath.hasPrefix("/") ? String(tokenPath.dropFirst()) : tokenPath
        guard !clean.isEmpty else { return nil }
        let url = root.appendingPathComponent("docs").appendingPathComponent(clean)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Helpers

    /// The absolute assets directory and its docs-relative token prefix for `docPath`.
    /// `docPath` is root-relative incl. "docs/" (e.g. "docs/guides/setup.md").
    func assetsDir(forDoc docPath: String) -> (dir: URL, tokenPrefix: String) {
        let docsRel = docPath.hasPrefix("docs/") ? String(docPath.dropFirst("docs/".count)) : docPath
        let comps = docsRel.split(separator: "/").map(String.init)
        let prefixComps = comps.dropLast() + ["assets"]   // doc's directory + assets
        let tokenPrefix = prefixComps.joined(separator: "/")
        let dir = root.appendingPathComponent("docs").appendingPathComponent(tokenPrefix)
        return (dir, tokenPrefix)
    }

    private func uniqueName(_ filename: String, in dir: URL) -> String {
        let ext = (filename as NSString).pathExtension
        let stem = (filename as NSString).deletingPathExtension
        var candidate = filename
        var i = 1
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(stem)-\(i)" : "\(stem)-\(i).\(ext)"
            i += 1
        }
        return candidate
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path swift/DetDocCore`
Expected: PASS — all `DocImageImporterTests` pass, no regressions.

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Services/DocImageImporter.swift \
        swift/DetDocCore/Tests/DetDocCoreTests/DocImageImporterTests.swift
git commit -m "feat(core): DocImageImporter — copy into per-doc assets, resolve tokens"
```

---

### Task 3: Image attachment + preview view (app)

Define the `NSTextAttachment` and SwiftUI preview that renders a dragged image inline at ~120 px tall. Mirrors the Swift 6 isolation pattern in `DocLinkBubble.swift`.

**Files:**
- Create: `swift/DetDocApp/Sources/Workspace/Docs/DocImageBubble.swift`

**Interfaces:**
- Produces:
  - `final class DocImageAttachment: NSTextAttachment` with `@MainActor init(url: URL, onOpen: @escaping @MainActor () -> Void)`.
  - `struct DocImageView: View` (internal to the file).
  - `final class DocImageProvider: NSTextAttachmentViewProvider` (internal).

- [ ] **Step 1: Write the file**

Create `swift/DetDocApp/Sources/Workspace/Docs/DocImageBubble.swift`:

```swift
import AppKit
import SwiftUI

// MARK: - View

struct DocImageView: View {
    let image: NSImage
    let size: CGSize
    let onOpen: () -> Void

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { onOpen() }
            .help("Click to open full size")
    }
}

// MARK: - Attachment

// Same isolation strategy as DocLinkBubbleAttachment: the attachment is built on the
// main thread by the @MainActor content-storage delegate and only used on main.
// `url` is Sendable; `onOpen` is a non-Sendable closure marked nonisolated(unsafe)
// because it is exclusively invoked on the main thread (SwiftUI onTapGesture).
final class DocImageAttachment: NSTextAttachment {
    let url: URL
    nonisolated(unsafe) let onOpen: () -> Void

    @MainActor
    init(url: URL, onOpen: @escaping @MainActor () -> Void) {
        self.url = url
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

// MARK: - Attachment view provider

// loadView()/attachmentBounds(…) are nonisolated in the SDK but always called on the
// main thread; we bridge non-Sendable values through MainThreadOnly + assumeIsolated,
// exactly like DocLinkBubble.
private struct MainThreadOnly<T>: @unchecked Sendable { let value: T }

final class DocImageProvider: NSTextAttachmentViewProvider {
    private let image: NSImage?
    private let onOpen: MainThreadOnly<() -> Void>
    private let containerWidth: CGFloat

    override init(
        textAttachment: NSTextAttachment,
        parentView: NSView?,
        textLayoutManager: NSTextLayoutManager?,
        location: any NSTextLocation
    ) {
        let a = textAttachment as? DocImageAttachment
        self.image = a.flatMap { NSImage(contentsOf: $0.url) }
        self.onOpen = MainThreadOnly(value: a?.onOpen ?? {})
        let cw = textLayoutManager?.textContainer?.size.width ?? 480
        self.containerWidth = (cw.isFinite && cw > 0) ? cw : 480
        super.init(textAttachment: textAttachment, parentView: parentView,
                   textLayoutManager: textLayoutManager, location: location)
    }

    /// Compact preview: <=120 pt tall, width by aspect, capped to the container width.
    private func displaySize() -> CGSize {
        guard let image, image.size.width > 0, image.size.height > 0 else {
            return CGSize(width: 120, height: 90)
        }
        let aspect = image.size.width / image.size.height
        var h = min(image.size.height, 120)
        var w = h * aspect
        let cap = max(80, containerWidth - 24)
        if w > cap { w = cap; h = w / aspect }
        return CGSize(width: w.rounded(), height: h.rounded())
    }

    override func loadView() {
        let size = displaySize()
        let follow = onOpen
        let providerBox = MainThreadOnly(value: self)
        if let image {
            let imageBox = MainThreadOnly(value: image)
            MainActor.assumeIsolated {
                providerBox.value.view = NSHostingView(
                    rootView: DocImageView(image: imageBox.value, size: size, onOpen: follow.value)
                )
            }
        } else {
            MainActor.assumeIsolated { providerBox.value.view = NSView() }
        }
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        let size = displaySize()
        return CGRect(x: 0, y: -4, width: size.width, height: size.height)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run (from `swift/DetDocApp`): `xcodebuild build -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED. (If `DetDocApp.xcodeproj` is missing, run `tuist generate` first.)

- [ ] **Step 3: Commit**

```bash
git add swift/DetDocApp/Sources/Workspace/Docs/DocImageBubble.swift
git commit -m "feat(app): DocImageAttachment + compact inline image preview view"
```

---

### Task 4: Render image tokens in the editor + Quick Look (app)

Teach the content-storage delegate to collapse resolvable image tokens into `DocImageAttachment` previews (revealing raw text when the caret is inside, red dotted when missing), wire the `DocImageImporter` through the view hierarchy, and open Quick Look on tap.

**Files:**
- Modify: `swift/DetDocApp/Sources/Workspace/Docs/LivePreviewTextView.swift`
- Modify: `swift/DetDocApp/Sources/Workspace/Docs/DocEditorScreen.swift`
- Modify: `swift/DetDocApp/Sources/Workspace/WorkspaceView.swift`

**Interfaces:**
- Consumes: `DocImageAttachment` (Task 3), `ImageRefScanner` + `DocImageImporter` (Tasks 1–2).
- Produces (used by Task 5):
  - `LivePreviewTextView` and its `Coordinator` gain `var imageImporter: DocImageImporter`.
  - `Coordinator.openQuickLook(_ url: URL)`.
  - `Coordinator.tokenRange(atCaret:)` (renamed from `linkRange`, now also matching image tokens).

- [ ] **Step 1: Add the importer to the view + coordinator and wire it through**

In `LivePreviewTextView.swift`, add the stored property to the struct (after `var resolver: DocLinkResolver`):

```swift
    var imageImporter: DocImageImporter
```

Update `makeCoordinator()`:

```swift
    func makeCoordinator() -> Coordinator {
        Coordinator(editor: editor, resolver: resolver,
                    imageImporter: imageImporter,
                    candidatesProvider: candidatesProvider,
                    onFollowLink: onFollowLink)
    }
```

In `updateNSView`, after `context.coordinator.resolver = resolver` add:

```swift
        context.coordinator.imageImporter = imageImporter
```

In the `Coordinator` class, add the stored property (after `var resolver: DocLinkResolver`):

```swift
        var imageImporter: DocImageImporter
```

Update the `Coordinator.init` signature and body:

```swift
        init(editor: DocEditorViewModel, resolver: DocLinkResolver,
             imageImporter: DocImageImporter,
             candidatesProvider: @escaping () -> [DocCandidate],
             onFollowLink: @escaping (String) -> Void) {
            self.editor = editor
            self.resolver = resolver
            self.imageImporter = imageImporter
            self.candidatesProvider = candidatesProvider
            self.onFollowLink = onFollowLink
        }
```

- [ ] **Step 2: Render image tokens in the content-storage delegate**

In `textContentStorage(_:textParagraphWith:)`, change the early-out to also scan image refs. Replace:

```swift
            let spans = MarkdownStyleScanner.scan(raw.string)
            let refs = DocRefScanner.scan(raw.string)
            if spans.isEmpty && refs.isEmpty { return nil }   // plain paragraph -> default rendering
```

with:

```swift
            let spans = MarkdownStyleScanner.scan(raw.string)
            let refs = DocRefScanner.scan(raw.string)
            let imageRefs = ImageRefScanner.scan(raw.string)
            if spans.isEmpty && refs.isEmpty && imageRefs.isEmpty { return nil }   // plain paragraph -> default rendering
```

Then, immediately **after** the `for ref in refs { … }` loop (and before the `// Apply highest-offset-first` comment), insert the image loop:

```swift
            // --- @-token images ---
            for img in imageRefs {
                let absStart = paraStart + img.range.location
                let absEnd = absStart + img.range.length
                let caretInToken = caret >= absStart && caret < absEnd

                if let url = imageImporter.resolve(img.path) {
                    display.addAttribute(.foregroundColor, value: NSColor.linkColor, range: img.range)
                    if !caretInToken {
                        let attachment = DocImageAttachment(url: url) { [weak self] in
                            self?.openQuickLook(url)
                        }
                        modifications.append((range: img.range, replacement: NSAttributedString(attachment: attachment)))
                    }
                } else {
                    display.addAttribute(.foregroundColor, value: NSColor.systemRed, range: img.range)
                    display.addAttribute(.underlineStyle, value: NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.single.rawValue, range: img.range)
                    display.addAttribute(.toolTip, value: "Missing image: \(img.path)", range: img.range)
                }
            }
```

- [ ] **Step 3: Generalize caret-boundary detection to image tokens**

Rename `linkRange(atCaret:)` to `tokenRange(atCaret:)` and make it scan both token kinds. Replace the whole method:

```swift
        /// Returns the document-absolute NSRange of the @-token span (doc link OR
        /// image) that contains `caret`, or nil if the caret is not inside a token.
        private func tokenRange(atCaret caret: Int) -> NSRange? {
            guard let storage = textView?.textStorage, caret >= 0, caret <= storage.length else { return nil }
            let ns = storage.string as NSString
            let para = ns.paragraphRange(for: NSRange(location: min(caret, max(0, ns.length - 1)), length: 0))
            let paraStr = ns.substring(with: para)
            let ranges = DocRefScanner.scan(paraStr).map(\.range) + ImageRefScanner.scan(paraStr).map(\.range)
            for r in ranges {
                let absStart = para.location + r.location
                let absEnd = absStart + r.length
                if caret >= absStart && caret < absEnd { return NSRange(location: absStart, length: absEnd - absStart) }
            }
            return nil
        }
```

Update the two call sites in `textViewDidChangeSelection`:

```swift
        func textViewDidChangeSelection(_ notification: Notification) {
            let new = textView?.selectedRange().location ?? 0
            let oldToken = tokenRange(atCaret: lastCaret)
            let newToken = tokenRange(atCaret: new)
            if oldToken != newToken {
                refreshCaretParagraphs(old: lastCaret, new: new)
            }
            lastCaret = new
            updateCompletion(allowOpen: false)
        }
```

- [ ] **Step 4: Add the Quick Look helper**

At the top of `LivePreviewTextView.swift`, add to the imports:

```swift
import Quartz
```

Add a Quick Look data source as a new type at the bottom of the file (after the `Coordinator` class closes, inside the file scope):

```swift
// QLPreviewPanel's data-source methods are nonisolated in the SDK but the panel only
// drives them on the main thread; @preconcurrency + @MainActor satisfies Swift 6.
@MainActor
final class ImageQuickLookSource: NSObject, @preconcurrency QLPreviewPanelDataSource {
    var url: URL?
    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int { url == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> any QLPreviewItem {
        (url as NSURL?) ?? NSURL(fileURLWithPath: "/")
    }
}
```

In the `Coordinator`, add a stored property (next to `private var panel: NSPanel?`):

```swift
        private let quickLook = ImageQuickLookSource()
```

And add the method (anywhere in the `Coordinator`, e.g. after `hidePanel()`):

```swift
        func openQuickLook(_ url: URL) {
            quickLook.url = url
            guard let panel = QLPreviewPanel.shared() else { return }
            panel.dataSource = quickLook
            panel.makeKeyAndOrderFront(nil)
            panel.reloadData()
        }
```

- [ ] **Step 5: Pass the importer through DocEditorScreen**

In `DocEditorScreen.swift`, add the property and pass it down. After `var resolver: DocLinkResolver` add:

```swift
    var imageImporter: DocImageImporter
```

Update the `LivePreviewTextView(...)` call:

```swift
                LivePreviewTextView(editor: editor, resolver: resolver,
                                   imageImporter: imageImporter,
                                   candidatesProvider: candidatesProvider,
                                   onFollowLink: onFollowLink)
```

- [ ] **Step 6: Construct + inject the importer in WorkspaceView**

In `WorkspaceView.swift`, add a computed importer (next to `linkResolver`):

```swift
    private var imageImporter: DocImageImporter { DocImageImporter(root: root) }
```

Update the `DocEditorScreen(...)` call to pass it:

```swift
            DocEditorScreen(editor: editor, resolver: linkResolver,
                            imageImporter: imageImporter,
                            candidatesProvider: {
                                let svc = DocsService(root: root, config: self.config)
                                return svc.candidates()
                            }) { docPath in
                if !tree.isDirectory(docPath) { selectedDoc = docPath }
            }
```

- [ ] **Step 7: Build to verify it compiles**

Run (from `swift/DetDocApp`): `xcodebuild build -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 8: Manual verification of rendering**

1. Launch the app on a project; open a doc, e.g. `docs/guides/setup.md` (create one if needed).
2. In Finder, place a real PNG at `<project>/docs/guides/assets/window.png`.
3. In the editor, type a new line: `@guides/assets/window.png`.
4. Move the caret off that line → the token collapses into a ~120 px image preview.
5. Move the caret back onto the token → it reveals the raw `@guides/assets/window.png` text (link-colored).
6. Click the preview → Quick Look opens the image full size; Esc closes it.
7. Type a bad token `@guides/assets/missing.png` → it shows red dotted with a "Missing image" tooltip, no preview.

Expected: all of the above behave as described.

- [ ] **Step 9: Commit**

```bash
git add swift/DetDocApp/Sources/Workspace/Docs/LivePreviewTextView.swift \
        swift/DetDocApp/Sources/Workspace/Docs/DocEditorScreen.swift \
        swift/DetDocApp/Sources/Workspace/WorkspaceView.swift
git commit -m "feat(app): render @-token images inline; Quick Look on tap"
```

---

### Task 5: Drag & paste image input (app)

Subclass `NSTextView` to intercept image drops (file URLs + raster data) and image paste, import via `DocImageImporter`, and insert the token on its own line. Rebuild the editor's TextKit 2 stack around the subclass.

**Files:**
- Create: `swift/DetDocApp/Sources/Workspace/Docs/ImageDropTextView.swift`
- Modify: `swift/DetDocApp/Sources/Workspace/Docs/LivePreviewTextView.swift`

**Interfaces:**
- Consumes: `Coordinator.imageImporter` + `Coordinator.editor` (Task 4); `ImageRefScanner.isImagePath` (Task 1).
- Produces:
  - `final class ImageDropTextView: NSTextView` with `weak var coordinator: LivePreviewTextView.Coordinator?`.
  - `Coordinator.handleImageDrop(_:into:) -> Bool`, `Coordinator.handleImagePaste(into:) -> Bool`.

- [ ] **Step 1: Create the drop-aware text view subclass**

Create `swift/DetDocApp/Sources/Workspace/Docs/ImageDropTextView.swift`:

```swift
import AppKit

/// NSTextView subclass that intercepts image drops and image paste, delegating the
/// import + insertion to the LivePreviewTextView coordinator. Non-image drags/pastes
/// fall through to the default NSTextView behavior.
final class ImageDropTextView: NSTextView {
    weak var coordinator: LivePreviewTextView.Coordinator?

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if coordinator?.handleImageDrop(sender, into: self) == true { return true }
        return super.performDragOperation(sender)
    }

    override func paste(_ sender: Any?) {
        if coordinator?.handleImagePaste(into: self) == true { return }
        super.paste(sender)
    }
}
```

- [ ] **Step 2: Add the import/insert handlers to the Coordinator**

In `LivePreviewTextView.swift`, add these methods to the `Coordinator` (e.g. after `openQuickLook`):

```swift
        // MARK: - Image drop / paste

        /// Returns true if the drag carried image file URLs or raster data that we
        /// imported and inserted as @-tokens.
        func handleImageDrop(_ sender: any NSDraggingInfo, into tv: NSTextView) -> Bool {
            guard let docPath = editor.selectedPath else { return false }
            let pb = sender.draggingPasteboard
            let point = tv.convert(sender.draggingLocation, from: nil)
            let charIndex = tv.characterIndexForInsertion(at: point)

            var tokens: [String] = []
            let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
            if let urls = pb.readObjects(forClasses: [NSURL.self], options: opts) as? [URL] {
                for url in urls where ImageRefScanner.isImagePath(url.lastPathComponent) {
                    if let token = try? imageImporter.importFile(at: url, forDoc: docPath) { tokens.append(token) }
                }
            }
            if tokens.isEmpty, let data = imageData(from: pb),
               let token = try? imageImporter.importData(data, basename: Self.generatedBasename(), forDoc: docPath) {
                tokens.append(token)
            }
            guard !tokens.isEmpty else { return false }
            insertImageTokens(tokens, at: charIndex, in: tv)
            return true
        }

        /// Returns true if the pasteboard held image data (and no plain text) that we
        /// imported and inserted at the caret.
        func handleImagePaste(into tv: NSTextView) -> Bool {
            guard let docPath = editor.selectedPath else { return false }
            let pb = NSPasteboard.general
            if pb.string(forType: .string) != nil { return false }   // let normal text paste win
            guard let data = imageData(from: pb),
                  let token = try? imageImporter.importData(data, basename: Self.generatedBasename(), forDoc: docPath)
            else { return false }
            insertImageTokens([token], at: tv.selectedRange().location, in: tv)
            return true
        }

        private func imageData(from pb: NSPasteboard) -> Data? {
            if let png = pb.data(forType: .png) { return png }
            if let tiff = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) { return png }
            return nil
        }

        private func insertImageTokens(_ tokens: [String], at index: Int, in tv: NSTextView) {
            let ns = tv.string as NSString
            let loc = max(0, min(index, ns.length))
            let newline = UInt16(UnicodeScalar("\n").value)
            let needsLeading = loc > 0 && ns.character(at: loc - 1) != newline
            let needsTrailing = loc < ns.length && ns.character(at: loc) != newline
            var text = tokens.map { "@\($0)" }.joined(separator: "\n")
            if needsLeading { text = "\n" + text }
            if needsTrailing { text += "\n" }
            let range = NSRange(location: loc, length: 0)
            if tv.shouldChangeText(in: range, replacementString: text) {
                tv.textStorage?.replaceCharacters(in: range, with: text)
                tv.didChangeText()
                tv.setSelectedRange(NSRange(location: loc + (text as NSString).length, length: 0))
            }
            editor.edit(tv.string)
        }

        private static func generatedBasename() -> String {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            return "image-\(f.string(from: Date()))"
        }
```

- [ ] **Step 3: Rebuild the editor stack around the subclass**

In `LivePreviewTextView.swift`, replace the body of `makeNSView(context:)` with a manual TextKit 2 stack that uses `ImageDropTextView`:

```swift
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true

        // TextKit 2 stack so the content-storage delegate (live preview) works.
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        let layoutManager = NSTextLayoutManager()
        layoutManager.textContainer = container
        let contentStorage = NSTextContentStorage()
        contentStorage.addTextLayoutManager(layoutManager)

        let tv = ImageDropTextView(frame: .zero, textContainer: container)
        tv.coordinator = context.coordinator
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]

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
        contentStorage.delegate = context.coordinator

        tv.registerForDraggedTypes([.fileURL, .tiff, .png])

        scroll.documentView = tv
        return scroll
    }
```

- [ ] **Step 4: Build to verify it compiles**

Run (from `swift/DetDocApp`): `xcodebuild build -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Manual verification of drag & paste**

1. Launch the app; open a doc, e.g. `docs/guides/setup.md`.
2. **Finder drag:** drag a PNG/JPG from Finder onto the editor. Expected: the file is copied to `docs/guides/assets/`, a `@guides/assets/<name>` token is inserted on its own line, and it renders as a preview once the caret leaves the line.
3. **Paste:** copy an image (e.g. screenshot to clipboard with Ctrl-Cmd-Shift-4), put the caret in the doc, Cmd-V. Expected: a PNG `image-<timestamp>.png` is written to `assets/` and inserted/rendered.
4. **Data drag:** drag an image directly from a browser onto the editor. Expected: same as paste (raster data → PNG).
5. **Regression:** plain typing, link bubbles (`@guides/setup`), heading/bold/italic styling, and normal text copy/paste still work.
6. **Collision:** drag the same Finder file twice → second token is `…/<name>-1.png`.
7. Save the doc (Cmd-S via the Save button) and confirm the markdown file contains the `@…png` token and the image file exists under `assets/`.

Expected: all behaviors as described.

- [ ] **Step 6: Commit**

```bash
git add swift/DetDocApp/Sources/Workspace/Docs/ImageDropTextView.swift \
        swift/DetDocApp/Sources/Workspace/Docs/LivePreviewTextView.swift
git commit -m "feat(app): drag & paste images into the editor as @-tokens"
```

---

## Self-Review

**Spec coverage:**
- On-disk `@`-token + extension classification → Task 1. ✓
- Per-doc `assets/` storage + naming/dedupe → Task 2. ✓
- Inline compact (~120 px) preview → Task 3. ✓
- Caret-reveal of raw token, broken-file red dotted, boundary refresh → Task 4. ✓
- Quick Look on tap → Task 4. ✓
- Finder file drag, paste, data drag, own-line insertion, multi-image → Task 5. ✓
- Core unit tests for scanners + importer → Tasks 1–2. ✓
- App layer verified manually → Tasks 3–5 manual steps. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code. ✓

**Type consistency:** `DocImageImporter.resolve`/`importFile`/`importData`, `ImageRefScanner.scan`/`isImagePath`, `DocImageAttachment(url:onOpen:)`, `Coordinator.imageImporter`/`openQuickLook`/`handleImageDrop`/`handleImagePaste`, `tokenRange(atCaret:)` are referenced consistently across tasks. `editor.selectedPath` (incl. `docs/` prefix) matches `DocImageImporter.assetsDir` stripping `docs/`. ✓
