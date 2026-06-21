# Docs File Tree Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat list of document paths in the workspace left panel with a hierarchical `docs/` file tree that supports new file, new folder, rename, and delete.

**Architecture:** A pure `DocTreeBuilder` folds relative paths into `DocTreeNode` values; a `@MainActor @Observable DocsTreeViewModel` (App target) wraps the existing `DocsCore.DocsService` for listing + mutations and exposes the tree; `DocsExplorerView` renders it with `List(_:children:selection:)` plus context-menu/bottom-bar operations. Filesystem reads (directory listing, directory creation) are added to `DocsService` in Core.

**Tech Stack:** Swift 6, SwiftUI (macOS 27), Swift Testing (`import Testing`, `#expect`), SwiftPM (`DetDocCore`), Tuist-generated `DetDocApp.xcodeproj`.

## Global Constraints

- Swift 6 toolchain; `SWIFT_VERSION` is `6.0`; macOS deployment target `27.0`.
- Tests use Swift Testing (`@Test`, `#expect`, `#require`) — not XCTest.
- App target's Swift module name is `DetDoc` (tests `@testable import DetDoc`).
- `Sources/` and `Tests/` are Tuist file-system-synchronized buildable folders: new files are picked up **without** re-running `tuist generate`, but the project must already be generated (it is git-ignored).
- Scope is `docs/` Markdown only (respect the config `docs` policy already applied by `DocsService.list()`). No whole-repo browser, no git badges, no drag-and-drop, no persisted expansion state.
- Filesystem mutations go through `DocsService` and surface failures as `DetDocError`.

---

## Preliminary: ensure the app project is generated

The App-target tasks build/test through `DetDocApp.xcodeproj`, which is git-ignored. Generate it once if missing:

```bash
cd swift/DetDocApp && [ -d DetDocApp.xcodeproj ] || tuist generate --no-open
```

Because `Sources/` and `Tests/` are synchronized buildable folders, later tasks that add files do **not** need to re-run `tuist generate`.

---

## File Structure

- Modify `swift/DetDocCore/Sources/DetDocCore/Services/DocsService.swift` — add `listDirectories()` and `createDirectory(_:)`.
- Modify `swift/DetDocCore/Tests/DetDocCoreTests/DocsServiceTests.swift` — tests for the two new methods.
- Create `swift/DetDocApp/Sources/Workspace/Docs/DocTreeNode.swift` — `DocTreeNode` value type + `DocTreeBuilder` pure builder.
- Create `swift/DetDocApp/Tests/DocTreeBuilderTests.swift` — builder unit tests.
- Create `swift/DetDocApp/Sources/Workspace/Docs/DocsTreeViewModel.swift` — observable tree VM + operations + selection helpers.
- Create `swift/DetDocApp/Tests/DocsTreeViewModelTests.swift` — VM operation + helper tests.
- Modify `swift/DetDocApp/Sources/Workspace/Docs/DocEditorViewModel.swift` — add `clear()`.
- Modify `swift/DetDocApp/Tests/DocEditorViewModelTests.swift` — test for `clear()`.
- Modify `swift/DetDocApp/Sources/Workspace/Docs/DocsExplorerView.swift` — rewrite to the tree + operations UI.
- Modify `swift/DetDocApp/Sources/Workspace/WorkspaceView.swift` — own the tree VM, refresh it, route selection to the editor (files only), clear editor when selection clears.

---

### Task 1: `DocsService.listDirectories()` + `createDirectory(_:)` (Core)

**Files:**
- Modify: `swift/DetDocCore/Sources/DetDocCore/Services/DocsService.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/DocsServiceTests.swift`

**Interfaces:**
- Consumes: existing `private func relativePath(_ url: URL) -> String`, `DetDocError`.
- Produces:
  - `func listDirectories() -> [String]` — sorted relative paths of every subdirectory under `docs/` (e.g. `["docs/features", "docs/features/example-feature"]`); `[]` when `docs/` is absent or has no subdirectories.
  - `func createDirectory(_ path: String) throws` — creates the directory (with intermediates); throws `DetDocError("DOC_ALREADY_EXISTS", path)` if it already exists, `DetDocError("DOC_WRITE_FAILED", …)` on other failure.

- [ ] **Step 1: Write the failing tests**

Append to `swift/DetDocCore/Tests/DetDocCoreTests/DocsServiceTests.swift`:

```swift
@Test func listDirectoriesReturnsSubdirsSorted() throws {
    let (tmp, svc) = docsService()
    try FileManager.default.createDirectory(at: tmp.url.appendingPathComponent("docs/b/c"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: tmp.url.appendingPathComponent("docs/a"), withIntermediateDirectories: true)
    try "x".write(to: tmp.url.appendingPathComponent("docs/a/f.md"), atomically: true, encoding: .utf8)
    #expect(svc.listDirectories() == ["docs/a", "docs/b", "docs/b/c"])
}

@Test func listDirectoriesEmptyWhenNoDocs() throws {
    let (_, svc) = docsService()
    #expect(svc.listDirectories().isEmpty)
}

@Test func createDirectoryMakesDirAndRejectsDuplicate() throws {
    let (tmp, svc) = docsService()
    try svc.createDirectory("docs/new")
    var isDir: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: tmp.url.appendingPathComponent("docs/new").path, isDirectory: &isDir))
    #expect(isDir.boolValue)
    #expect(throws: DetDocError.self) { try svc.createDirectory("docs/new") }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path swift/DetDocCore --filter listDirectories`
Expected: FAIL — `value of type 'DocsService' has no member 'listDirectories'` (compile error).

- [ ] **Step 3: Add the two methods**

In `swift/DetDocCore/Sources/DetDocCore/Services/DocsService.swift`, add inside the `DocsService` struct (e.g. after `list()`):

```swift
public func listDirectories() -> [String] {
    let docsDir = root.appendingPathComponent("docs")
    guard let enumerator = FileManager.default.enumerator(at: docsDir, includingPropertiesForKeys: [.isDirectoryKey]) else {
        return []
    }
    var dirs: [String] = []
    for case let url as URL in enumerator {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        if values?.isDirectory == true {
            dirs.append(relativePath(url))
        }
    }
    return dirs.sorted()
}

public func createDirectory(_ path: String) throws {
    let url = root.appendingPathComponent(path)
    if FileManager.default.fileExists(atPath: url.path) {
        throw DetDocError("DOC_ALREADY_EXISTS", path)
    }
    do {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    } catch {
        throw DetDocError("DOC_WRITE_FAILED", "\(path): \(error)")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path swift/DetDocCore --filter "listDirectories|createDirectory"`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Services/DocsService.swift swift/DetDocCore/Tests/DetDocCoreTests/DocsServiceTests.swift
git commit -m "feat(core): add DocsService.listDirectories and createDirectory"
```

---

### Task 2: `DocTreeNode` + `DocTreeBuilder` (App, pure)

**Files:**
- Create: `swift/DetDocApp/Sources/Workspace/Docs/DocTreeNode.swift`
- Test: `swift/DetDocApp/Tests/DocTreeBuilderTests.swift`

**Interfaces:**
- Produces:
  - `struct DocTreeNode: Identifiable, Hashable { let id: String; let name: String; let isDirectory: Bool; var children: [DocTreeNode]? }`
  - `enum DocTreeBuilder { static func build(files: [String], directories: [String]) -> [DocTreeNode] }` — folds relative paths into a forest; directories sort before files, then case-insensitive by name; intermediate directories are derived from file/dir ancestors; files are leaves (`children == nil`); empty directories are nodes with `children == []`.

- [ ] **Step 1: Write the failing tests**

Create `swift/DetDocApp/Tests/DocTreeBuilderTests.swift`:

```swift
import Testing
@testable import DetDoc

@Test func buildEmptyInputReturnsEmpty() {
    #expect(DocTreeBuilder.build(files: [], directories: []).isEmpty)
}

@Test func buildNestsFilesUnderDocsRoot() throws {
    let nodes = DocTreeBuilder.build(
        files: ["docs/idea.md", "docs/features/_guide.md", "docs/features/x/brief.md"],
        directories: []
    )
    // Single "docs" root folder.
    #expect(nodes.count == 1)
    let docs = try #require(nodes.first)
    #expect(docs.id == "docs")
    #expect(docs.isDirectory)
    let docsChildren = try #require(docs.children)
    // Directory "features" sorts before file "idea.md".
    #expect(docsChildren.map(\.name) == ["features", "idea.md"])
    let features = try #require(docsChildren.first { $0.name == "features" })
    #expect(features.children?.map(\.name) == ["x", "_guide.md"])
    // Files are leaves.
    let idea = try #require(docsChildren.first { $0.name == "idea.md" })
    #expect(idea.isDirectory == false)
    #expect(idea.children == nil)
}

@Test func buildIncludesEmptyDirectories() throws {
    let nodes = DocTreeBuilder.build(files: ["docs/a.md"], directories: ["docs/empty"])
    let docs = try #require(nodes.first)
    let empty = try #require(docs.children?.first { $0.name == "empty" })
    #expect(empty.isDirectory)
    #expect(empty.children == [])
}

@Test func buildSortsCaseInsensitively() throws {
    let nodes = DocTreeBuilder.build(files: ["docs/Zebra.md", "docs/apple.md"], directories: [])
    let docs = try #require(nodes.first)
    #expect(docs.children?.map(\.name) == ["apple.md", "Zebra.md"])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
cd swift/DetDocApp && xcodebuild test -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS' -only-testing:DetDocAppTests 2>&1 | tail -20
```
Expected: FAIL — build error `cannot find 'DocTreeBuilder' in scope`.

- [ ] **Step 3: Create the type and builder**

Create `swift/DetDocApp/Sources/Workspace/Docs/DocTreeNode.swift`:

```swift
import Foundation

struct DocTreeNode: Identifiable, Hashable {
    let id: String          // relative path: "docs/guide/intro.md" or "docs/guide"
    let name: String        // last path component: "intro.md" / "guide"
    let isDirectory: Bool
    var children: [DocTreeNode]?   // nil for files; [] for an empty directory
}

enum DocTreeBuilder {
    static func build(files: [String], directories: [String]) -> [DocTreeNode] {
        let fileSet = Set(files)
        var dirSet = Set<String>()

        func addAncestors(of path: String) {
            var comps = path.split(separator: "/").map(String.init)
            comps.removeLast()
            var acc: [String] = []
            for c in comps {
                acc.append(c)
                dirSet.insert(acc.joined(separator: "/"))
            }
        }
        for f in fileSet { addAncestors(of: f) }
        for d in directories {
            dirSet.insert(d)
            addAncestors(of: d)
        }

        func parent(of path: String) -> String {
            var comps = path.split(separator: "/").map(String.init)
            comps.removeLast()
            return comps.joined(separator: "/")
        }
        var childrenByParent: [String: [String]] = [:]
        for d in dirSet { childrenByParent[parent(of: d), default: []].append(d) }
        for f in fileSet { childrenByParent[parent(of: f), default: []].append(f) }

        func name(of path: String) -> String { String(path.split(separator: "/").last ?? "") }

        func node(for path: String) -> DocTreeNode {
            if dirSet.contains(path) {
                let kids = (childrenByParent[path] ?? []).map(node(for:))
                return DocTreeNode(id: path, name: name(of: path), isDirectory: true, children: sortNodes(kids))
            }
            return DocTreeNode(id: path, name: name(of: path), isDirectory: false, children: nil)
        }

        let roots = (childrenByParent[""] ?? []).map(node(for:))
        return sortNodes(roots)
    }

    private static func sortNodes(_ nodes: [DocTreeNode]) -> [DocTreeNode] {
        nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
cd swift/DetDocApp && xcodebuild test -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS' -only-testing:DetDocAppTests 2>&1 | tail -20
```
Expected: PASS (the 4 `build*` tests pass; existing tests still pass).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocApp/Sources/Workspace/Docs/DocTreeNode.swift swift/DetDocApp/Tests/DocTreeBuilderTests.swift
git commit -m "feat(app): add DocTreeNode and pure DocTreeBuilder"
```

---

### Task 3: `DocsTreeViewModel` (App)

**Files:**
- Create: `swift/DetDocApp/Sources/Workspace/Docs/DocsTreeViewModel.swift`
- Test: `swift/DetDocApp/Tests/DocsTreeViewModelTests.swift`

**Interfaces:**
- Consumes: `DocTreeNode`, `DocTreeBuilder` (Task 2); `DocsService`, `DetDocConfig`, `DetDocError` (Core).
- Produces (`public final class DocsTreeViewModel`, `@MainActor @Observable`):
  - `init(root: URL, config: DetDocConfig)`
  - `private(set) var nodes: [DocTreeNode]`
  - `private(set) var error: DetDocError?`
  - `func refresh()`
  - `@discardableResult func newFile(name: String, in directory: String) -> String?` — returns created relative path (`.md`-normalized) or `nil` on error.
  - `@discardableResult func newFolder(name: String, in directory: String) -> String?`
  - `@discardableResult func rename(_ path: String, to newName: String) -> String?` — renames within the same parent; returns the new path or `nil`.
  - `func delete(_ path: String)`
  - `func dismissError()`
  - `func isDirectory(_ id: String) -> Bool`
  - `func directoryForNewEntry(selection: String?) -> String`
  - `static func remapAfterRename(selection: String?, from: String, to: String) -> String?`
  - `static func remapAfterDelete(selection: String?, deleted: String) -> String?`

- [ ] **Step 1: Write the failing tests**

Create `swift/DetDocApp/Tests/DocsTreeViewModelTests.swift`:

```swift
import Foundation
import Testing
@testable import DetDoc
@testable import DetDocCore

@MainActor
private func makeVM() async throws -> (VMGitFixture, DocsTreeViewModel) {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    let vm = DocsTreeViewModel(root: fx.root, config: .default)
    vm.refresh()
    return (fx, vm)
}

@MainActor
@Test func refreshExposesDocsContentsAtTopLevel() async throws {
    let (_, vm) = try await makeVM()
    // The single "docs" root is unwrapped: starter docs/ contents are top-level.
    #expect(vm.nodes.contains { $0.name == "idea.md" })
    #expect(vm.nodes.contains { $0.name == "features" && $0.isDirectory })
}

@MainActor
@Test func newFileCreatesMarkdownAndAppearsInTree() async throws {
    let (fx, vm) = try await makeVM()
    let path = vm.newFile(name: "notes", in: "docs")
    #expect(path == "docs/notes.md")
    #expect(try String(contentsOf: fx.root.appendingPathComponent("docs/notes.md"), encoding: .utf8).contains("notes"))
    #expect(vm.nodes.contains { $0.name == "notes.md" })
    #expect(vm.error == nil)
}

@MainActor
@Test func newFileInSubfolderLandsThere() async throws {
    let (_, vm) = try await makeVM()
    let path = vm.newFile(name: "todo.md", in: "docs/features")
    #expect(path == "docs/features/todo.md")
}

@MainActor
@Test func newFolderCreatesEmptyDirectoryNode() async throws {
    let (_, vm) = try await makeVM()
    let path = vm.newFolder(name: "drafts", in: "docs")
    #expect(path == "docs/drafts")
    let drafts = try #require(vm.nodes.first { $0.name == "drafts" })
    #expect(drafts.isDirectory)
    #expect(drafts.children == [])
}

@MainActor
@Test func duplicateCreateSetsError() async throws {
    let (_, vm) = try await makeVM()
    let path = vm.newFile(name: "idea", in: "docs")   // docs/idea.md already exists
    #expect(path == nil)
    #expect(vm.error?.code == "DOC_ALREADY_EXISTS")
    vm.dismissError()
    #expect(vm.error == nil)
}

@MainActor
@Test func renameFileKeepsParentAndReturnsNewPath() async throws {
    let (_, vm) = try await makeVM()
    let newPath = vm.rename("docs/idea.md", to: "concept")
    #expect(newPath == "docs/concept.md")
    #expect(vm.nodes.contains { $0.name == "concept.md" })
    #expect(vm.nodes.contains { $0.name == "idea.md" } == false)
}

@MainActor
@Test func renameDirectoryReturnsNewPath() async throws {
    let (_, vm) = try await makeVM()
    let newPath = vm.rename("docs/features", to: "specs")
    #expect(newPath == "docs/specs")
    #expect(vm.isDirectory("docs/specs"))
}

@MainActor
@Test func deleteRemovesNode() async throws {
    let (_, vm) = try await makeVM()
    vm.delete("docs/idea.md")
    #expect(vm.nodes.contains { $0.name == "idea.md" } == false)
    #expect(vm.error == nil)
}

@MainActor
@Test func directoryForNewEntryResolvesFromSelection() async throws {
    let (_, vm) = try await makeVM()
    #expect(vm.directoryForNewEntry(selection: nil) == "docs")
    #expect(vm.directoryForNewEntry(selection: "docs/features") == "docs/features")     // directory selected
    #expect(vm.directoryForNewEntry(selection: "docs/idea.md") == "docs")               // file -> its parent
}

@Test func remapAfterRenameHandlesSelfAndDescendants() {
    #expect(DocsTreeViewModel.remapAfterRename(selection: "docs/idea.md", from: "docs/idea.md", to: "docs/concept.md") == "docs/concept.md")
    #expect(DocsTreeViewModel.remapAfterRename(selection: "docs/features/brief.md", from: "docs/features", to: "docs/specs") == "docs/specs/brief.md")
    #expect(DocsTreeViewModel.remapAfterRename(selection: "docs/other.md", from: "docs/features", to: "docs/specs") == "docs/other.md")
    #expect(DocsTreeViewModel.remapAfterRename(selection: nil, from: "a", to: "b") == nil)
}

@Test func remapAfterDeleteClearsSelfAndDescendants() {
    #expect(DocsTreeViewModel.remapAfterDelete(selection: "docs/idea.md", deleted: "docs/idea.md") == nil)
    #expect(DocsTreeViewModel.remapAfterDelete(selection: "docs/features/brief.md", deleted: "docs/features") == nil)
    #expect(DocsTreeViewModel.remapAfterDelete(selection: "docs/other.md", deleted: "docs/features") == "docs/other.md")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
cd swift/DetDocApp && xcodebuild test -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS' -only-testing:DetDocAppTests 2>&1 | tail -20
```
Expected: FAIL — build error `cannot find 'DocsTreeViewModel' in scope`.

- [ ] **Step 3: Create the view model**

Create `swift/DetDocApp/Sources/Workspace/Docs/DocsTreeViewModel.swift`:

```swift
import Foundation
import Observation
import DetDocCore

@MainActor
@Observable
public final class DocsTreeViewModel {
    public private(set) var nodes: [DocTreeNode] = []
    public private(set) var error: DetDocError?

    private let docs: DocsService

    public init(root: URL, config: DetDocConfig) {
        self.docs = DocsService(root: root, config: config)
    }

    public func refresh() {
        let built = DocTreeBuilder.build(files: docs.list().map(\.path), directories: docs.listDirectories())
        // Unwrap the single "docs" root so the panel shows docs/ contents directly.
        if built.count == 1, built[0].id == "docs", built[0].isDirectory {
            nodes = built[0].children ?? []
        } else {
            nodes = built
        }
    }

    @discardableResult
    public func newFile(name: String, in directory: String) -> String? {
        let leaf = name.hasSuffix(".md") ? name : name + ".md"
        let path = directory.isEmpty ? leaf : "\(directory)/\(leaf)"
        let title = leaf.hasSuffix(".md") ? String(leaf.dropLast(3)) : leaf
        return run { try docs.create(path, "# \(title)\n"); return path }
    }

    @discardableResult
    public func newFolder(name: String, in directory: String) -> String? {
        let path = directory.isEmpty ? name : "\(directory)/\(name)"
        return run { try docs.createDirectory(path); return path }
    }

    @discardableResult
    public func rename(_ path: String, to newName: String) -> String? {
        let parent = Self.parentDirectory(of: path)
        let leaf = (!isDirectory(path) && !newName.hasSuffix(".md")) ? newName + ".md" : newName
        let newPath = parent.isEmpty ? leaf : "\(parent)/\(leaf)"
        return run { try docs.rename(path, to: newPath); return newPath }
    }

    public func delete(_ path: String) {
        _ = run { try docs.delete(path); return "" }
    }

    public func dismissError() { error = nil }

    public func isDirectory(_ id: String) -> Bool {
        Self.find(id, in: nodes)?.isDirectory ?? false
    }

    public func directoryForNewEntry(selection: String?) -> String {
        guard let selection, let node = Self.find(selection, in: nodes) else { return "docs" }
        return node.isDirectory ? node.id : Self.parentDirectory(of: node.id)
    }

    public static func remapAfterRename(selection: String?, from: String, to: String) -> String? {
        guard let selection else { return nil }
        if selection == from { return to }
        if selection.hasPrefix(from + "/") { return to + String(selection.dropFirst(from.count)) }
        return selection
    }

    public static func remapAfterDelete(selection: String?, deleted: String) -> String? {
        guard let selection else { return nil }
        if selection == deleted || selection.hasPrefix(deleted + "/") { return nil }
        return selection
    }

    // MARK: - Private

    private func run(_ op: () throws -> String) -> String? {
        do {
            let result = try op()
            error = nil
            refresh()
            return result
        } catch let e as DetDocError {
            error = e
            return nil
        } catch {
            self.error = DetDocError("DOC_OP_FAILED", "\(error)")
            return nil
        }
    }

    static func parentDirectory(of path: String) -> String {
        var comps = path.split(separator: "/").map(String.init)
        comps.removeLast()
        return comps.joined(separator: "/")
    }

    static func find(_ id: String, in nodes: [DocTreeNode]) -> DocTreeNode? {
        for n in nodes {
            if n.id == id { return n }
            if let c = n.children, let hit = find(id, in: c) { return hit }
        }
        return nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
cd swift/DetDocApp && xcodebuild test -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS' -only-testing:DetDocAppTests 2>&1 | tail -20
```
Expected: PASS (all `DocsTreeViewModel` tests + existing tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocApp/Sources/Workspace/Docs/DocsTreeViewModel.swift swift/DetDocApp/Tests/DocsTreeViewModelTests.swift
git commit -m "feat(app): add DocsTreeViewModel with tree refresh and file operations"
```

---

### Task 4: `DocEditorViewModel.clear()` (App)

**Files:**
- Modify: `swift/DetDocApp/Sources/Workspace/Docs/DocEditorViewModel.swift`
- Test: `swift/DetDocApp/Tests/DocEditorViewModelTests.swift`

**Interfaces:**
- Produces: `func clear()` on `DocEditorViewModel` — resets `selectedPath = nil`, `source = ""`, `isDirty = false`, `error = nil`.

- [ ] **Step 1: Write the failing test**

Append to `swift/DetDocApp/Tests/DocEditorViewModelTests.swift`:

```swift
@MainActor
@Test func clearResetsEditorState() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    let vm = DocEditorViewModel(root: fx.root, config: .default)
    vm.open("docs/idea.md")
    vm.edit("changed\n")
    vm.clear()
    #expect(vm.selectedPath == nil)
    #expect(vm.source == "")
    #expect(vm.isDirty == false)
    #expect(vm.error == nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd swift/DetDocApp && xcodebuild test -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS' -only-testing:DetDocAppTests 2>&1 | tail -20
```
Expected: FAIL — build error `value of type 'DocEditorViewModel' has no member 'clear'`.

- [ ] **Step 3: Add `clear()`**

In `swift/DetDocApp/Sources/Workspace/Docs/DocEditorViewModel.swift`, add after `open(_:)`:

```swift
public func clear() {
    selectedPath = nil
    source = ""
    isDirty = false
    error = nil
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd swift/DetDocApp && xcodebuild test -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS' -only-testing:DetDocAppTests 2>&1 | tail -20
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocApp/Sources/Workspace/Docs/DocEditorViewModel.swift swift/DetDocApp/Tests/DocEditorViewModelTests.swift
git commit -m "feat(app): add DocEditorViewModel.clear"
```

---

### Task 5: Rewrite `DocsExplorerView` to a tree + wire `WorkspaceView`

**Files:**
- Modify: `swift/DetDocApp/Sources/Workspace/Docs/DocsExplorerView.swift`
- Modify: `swift/DetDocApp/Sources/Workspace/WorkspaceView.swift`

**Interfaces:**
- Consumes: `DocsTreeViewModel` (Task 3, incl. static `remapAfterRename`/`remapAfterDelete`), `DocEditorViewModel.clear()` and `DocEditorViewModel.isDirty`/`selectedPath` (Task 4 / existing).
- Produces: `DocsExplorerView(tree: DocsTreeViewModel, selection: Binding<String?>, dirtyPath: String?)`.

This task has no new unit test (it is SwiftUI view glue; behavior is covered by Task 3's VM tests). Its deliverable is the integrated, compiling UI with the full app test suite still green.

- [ ] **Step 1: Rewrite `DocsExplorerView`**

Replace the entire contents of `swift/DetDocApp/Sources/Workspace/Docs/DocsExplorerView.swift`:

```swift
import SwiftUI
import DetDocCore

struct DocsExplorerView: View {
    let tree: DocsTreeViewModel
    @Binding var selection: String?
    var dirtyPath: String?

    @State private var showNewFile = false
    @State private var showNewFolder = false
    @State private var nameInput = ""
    @State private var renameTarget: String?
    @State private var deleteTarget: String?

    var body: some View {
        List(tree.nodes, children: \.children, selection: $selection) { node in
            HStack(spacing: 6) {
                Label(node.name, systemImage: node.isDirectory ? "folder" : "doc.text")
                if !node.isDirectory, node.id == dirtyPath {
                    Spacer()
                    Circle().fill(.secondary).frame(width: 6, height: 6)
                        .help("Unsaved changes")
                }
            }
            .contextMenu {
                Button("Rename…") { nameInput = node.name; renameTarget = node.id }
                Button("Delete…", role: .destructive) { deleteTarget = node.id }
            }
        }
        .overlay {
            if tree.nodes.isEmpty {
                ContentUnavailableView("No documents", systemImage: "doc",
                    description: Text("Markdown files under docs/ appear here."))
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Button { nameInput = ""; showNewFile = true } label: { Image(systemName: "doc.badge.plus") }
                    .help("New File")
                Button { nameInput = ""; showNewFolder = true } label: { Image(systemName: "folder.badge.plus") }
                    .help("New Folder")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .alert("New File", isPresented: $showNewFile) {
            TextField("Name", text: $nameInput)
            Button("Create") {
                let dir = tree.directoryForNewEntry(selection: selection)
                if let path = tree.newFile(name: nameInput, in: dir) { selection = path }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Name", text: $nameInput)
            Button("Create") {
                let dir = tree.directoryForNewEntry(selection: selection)
                if let path = tree.newFolder(name: nameInput, in: dir) { selection = path }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Name", text: $nameInput)
            Button("Rename") {
                if let target = renameTarget, let newPath = tree.rename(target, to: nameInput) {
                    selection = DocsTreeViewModel.remapAfterRename(selection: selection, from: target, to: newPath)
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .alert("Delete", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
            Button("Delete", role: .destructive) {
                if let target = deleteTarget {
                    tree.delete(target)
                    selection = DocsTreeViewModel.remapAfterDelete(selection: selection, deleted: target)
                }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("Delete “\(deleteTarget ?? "")”? This cannot be undone.")
        }
        .alert("Operation failed",
               isPresented: Binding(get: { tree.error != nil }, set: { if !$0 { tree.dismissError() } }),
               presenting: tree.error) { _ in
            Button("OK") {}
        } message: { err in
            Text(err.message)
        }
    }
}
```

- [ ] **Step 2: Wire `WorkspaceView`**

In `swift/DetDocApp/Sources/Workspace/WorkspaceView.swift`:

Add a tree VM state property after the existing `@State private var settings`:

```swift
    @State private var tree: DocsTreeViewModel
```

In `init(root:)`, after the `_settings = …` line, add:

```swift
        _tree = State(initialValue: DocsTreeViewModel(root: root, config: config))
```

Replace the sidebar content in `NavigationSplitView`:

```swift
            DocsExplorerView(docs: workspace.docs, selection: $selectedDoc)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
                .navigationTitle("Docs")
```

with:

```swift
            DocsExplorerView(tree: tree, selection: $selectedDoc,
                             dirtyPath: editor.isDirty ? editor.selectedPath : nil)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
                .navigationTitle("Docs")
```

Replace the existing selection `onChange`:

```swift
        .onChange(of: selectedDoc) { _, new in if let new { editor.open(new) } }
```

with (open only files; clear the editor when selection clears):

```swift
        .onChange(of: selectedDoc) { _, new in
            if let new, !tree.isDirectory(new) { editor.open(new) }
            else if new == nil { editor.clear() }
        }
```

In the `.task { await workspace.refresh() … }` block, refresh the tree alongside the workspace. Change:

```swift
        .task {
            await workspace.refresh()
```

to:

```swift
        .task {
            await workspace.refresh()
            tree.refresh()
```

And in the completion `onChange` that refreshes after a run, refresh the tree too. Change:

```swift
        .onChange(of: panel.stage) { _, stage in if stage == .completed { Task { await workspace.refresh(); runs.refresh() } } }
```

to:

```swift
        .onChange(of: panel.stage) { _, stage in if stage == .completed { Task { await workspace.refresh(); tree.refresh(); runs.refresh() } } }
```

- [ ] **Step 3: Build to verify it compiles**

Run:
```bash
cd swift/DetDocApp && xcodebuild build -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the full app test suite**

Run:
```bash
cd swift/DetDocApp && xcodebuild test -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS' 2>&1 | tail -25
```
Expected: `** TEST SUCCEEDED **` — all `DetDocAppTests` pass (builder, tree VM, editor, and the pre-existing suites).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocApp/Sources/Workspace/Docs/DocsExplorerView.swift swift/DetDocApp/Sources/Workspace/WorkspaceView.swift
git commit -m "feat(app): render docs as a file tree with create/rename/delete"
```

---

## Final verification

- [ ] **Core suite:** `swift test --package-path swift/DetDocCore 2>&1 | tail -5` → all pass.
- [ ] **App suite:** `cd swift/DetDocApp && xcodebuild test -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS' 2>&1 | tail -5` → `** TEST SUCCEEDED **`.
- [ ] **Manual smoke (optional):** `open swift/DetDocApp/DetDocApp.xcodeproj`, run, point at a repo with `docs/`. Confirm: nested folders render; selecting a file opens it; selecting a folder does not; New File creates and opens a `.md`; New Folder shows an empty folder; Rename of the open doc keeps it open under the new name; Delete of the open doc clears the editor.

## Notes for the implementer

- Run the **Preliminary** step before Task 2 (the first App-target task) so `DetDocApp.xcodeproj` exists.
- `WorkspaceViewModel.docs` is no longer read by the sidebar after Task 5, but leave it — `refresh()` still populates it and other code/tests may rely on it (e.g. `WorkspaceViewModelTests`). Do not remove it as part of this plan (out of scope).
- `DocsTreeViewModel.refresh()` unwraps the single `docs` root so the panel (titled "Docs") shows docs/ contents at the top level. Folders use the native `List(_:children:selection:)` disclosure and start **collapsed**; this is intentional and not persisted.
- The `DocTreeBuilder` itself always produces the `docs` root node (it is path-generic); only the VM unwraps it. Task 2's builder tests therefore still assert the `docs` root, while Task 3's VM tests assert the unwrapped top level.
