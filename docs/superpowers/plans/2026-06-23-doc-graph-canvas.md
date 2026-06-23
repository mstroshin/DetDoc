# Doc Graph (Canvas) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Obsidian-style "Canvas" view that renders all docs as nodes, doc→doc links as connecting lines, image thumbnails on nodes, with hybrid auto-layout + persisted manual drag, and click-a-node-to-open.

**Architecture:** Pure Core builds the graph (`DocGraphBuilder`), computes a deterministic force-directed auto-layout (`ForceLayout`), and persists dragged positions locally (`CanvasLayoutStore`). An `@Observable` App view model (`DocGraphViewModel`) merges saved + auto positions; a SwiftUI view (`DocGraphView`) draws edges in one `Canvas` pass with node views overlaid under a shared pan/zoom transform. The Workspace gains a toolbar toggle that swaps the editor for the canvas.

**Tech Stack:** Swift 6, SwiftPM (`DetDocCore`), SwiftUI / AppKit (`DetDocApp`), Swift Testing, Tuist.

## Global Constraints

- macOS 27+, Swift 6 toolchain.
- Core (`DetDocCore`) is pure, `nonisolated`-by-default, `Sendable`; no CoreGraphics, no SwiftUI. CG types only in the App layer.
- App target default actor isolation is `@MainActor`; module name is `DetDoc` (tests `@testable import DetDoc`).
- `Sources/` and `Tests/` are file-system-synchronized Tuist groups — new files are picked up without `tuist generate`.
- Every view gets accessibility identifiers (project CLAUDE.md). Every iOS/macOS view gets a `#Preview` with multiple states (project CLAUDE.md).
- doc↔doc links only (no doc→code links on the graph). Layout is computed once (no live physics). Positions are local-only (gitignored).
- Naming: code uses the `DocGraph*` prefix to avoid colliding with the existing in-document `CanvasSketch*` feature; the user-facing button label is "Canvas".

---

## File Structure

**Core (`swift/DetDocCore/Sources/DetDocCore/Services/`):**
- `DocGraph.swift` — `DocGraphPoint`, `DocGraphEdge`, `DocGraphNode`, `DocGraph`, `DocGraphBuilder`. Builds the graph from docs. One job: docs → graph.
- `ForceLayout.swift` — deterministic force-directed layout: node ids + edges → positions.
- `CanvasLayoutStore.swift` — load/save dragged positions to `.detdoc/canvas-layout.json`.
- `Support/GitignoreManager.swift` (modify) — add the layout file to managed ignore entries.

**Core tests (`swift/DetDocCore/Tests/DetDocCoreTests/`):**
- `DocGraphBuilderTests.swift`, `ForceLayoutTests.swift`, `CanvasLayoutStoreTests.swift`.

**App (`swift/DetDocApp/Sources/Workspace/Docs/`):**
- `DocGraphViewModel.swift` — `@MainActor @Observable`; merges positions, drag, persist, image-zoom state.
- `DocGraphView.swift` — the canvas: edges `Canvas` + overlaid node views + pan/zoom + image overlay + previews.

**App integration (`swift/DetDocApp/Sources/Workspace/WorkspaceView.swift`, modify):** toolbar toggle + swap detail.

**App tests (`swift/DetDocApp/Tests/`):** `DocGraphViewModelTests.swift`.

---

## Task 1: Core — graph model + builder

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Services/DocGraph.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/DocGraphBuilderTests.swift`

**Interfaces:**
- Consumes: `DocsService.candidates() -> [DocCandidate]` (`.docsRelativePath` e.g. `"guides/setup.md"`, `.name`, `.title`), `DocsService.read(_:)` (path includes `docs/` prefix), `DocRefScanner.scan(_:) -> [DocRef]` (`.path` without `.md`), `ImageRefScanner.scan(_:) -> [ImageRef]` (`.path` with extension, docs-relative), `DocLinkResolver(candidates:).resolve(_:) -> Resolution?` (`.docsRelativePath`, `.exists`).
- Produces:
  - `struct DocGraphPoint: Codable, Equatable, Sendable { var x: Double; var y: Double }`
  - `struct DocGraphEdge: Hashable, Sendable, Comparable { let a, b: String; init(_:_:) normalizes a<=b }`
  - `struct DocGraphNode: Equatable, Sendable { let path, title: String; let imagePaths: [String] }`
  - `struct DocGraph: Equatable, Sendable { let nodes: [DocGraphNode]; let edges: [DocGraphEdge] }`
  - `struct DocGraphBuilder: Sendable { init(docs: DocsService); func build() -> DocGraph }`

- [ ] **Step 1: Write the failing test**

Create `swift/DetDocCore/Tests/DetDocCoreTests/DocGraphBuilderTests.swift`:

```swift
import Foundation
import Testing
@testable import DetDocCore

private func write(_ tmp: TempDir, _ rel: String, _ text: String) throws {
    let url = tmp.url.appendingPathComponent(rel)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}

@Test func buildsNodesEdgesAndImages() throws {
    let tmp = TempDir()
    try write(tmp, "docs/a.md", "# Alpha\nSee @b and an image @assets/x.png and @assets/x.png again.\n")
    try write(tmp, "docs/b.md", "# Beta\nBack to @a and a dangling @nope link.\n")
    try write(tmp, "docs/assets/x.png", "fake")   // not a .md, not a node

    let graph = DocGraphBuilder(docs: DocsService(root: tmp.url, config: .default)).build()

    // Nodes: only the two markdown docs, titled by first heading, sorted by path.
    #expect(graph.nodes.map(\.path) == ["a.md", "b.md"])
    #expect(graph.nodes.first?.title == "Alpha")
    // Images: docs-relative, de-duplicated, only on the owning node.
    #expect(graph.nodes.first?.imagePaths == ["assets/x.png"])
    #expect(graph.nodes.last?.imagePaths == [])
    // Edges: a<->b once (undirected, de-duplicated), dangling @nope excluded.
    #expect(graph.edges == [DocGraphEdge("a.md", "b.md")])
}

@Test func dropsSelfLinks() throws {
    let tmp = TempDir()
    try write(tmp, "docs/a.md", "# A\nLink to myself @a here.\n")
    let graph = DocGraphBuilder(docs: DocsService(root: tmp.url, config: .default)).build()
    #expect(graph.edges.isEmpty)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path swift/DetDocCore --filter DocGraphBuilder`
Expected: FAIL — `cannot find 'DocGraphBuilder' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `swift/DetDocCore/Sources/DetDocCore/Services/DocGraph.swift`:

```swift
import Foundation

public struct DocGraphPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// Undirected, de-duplicating edge: `init` normalises the endpoints so A↔B == B↔A.
public struct DocGraphEdge: Hashable, Sendable, Comparable {
    public let a: String
    public let b: String
    public init(_ x: String, _ y: String) {
        if x <= y { a = x; b = y } else { a = y; b = x }
    }
    public static func < (l: DocGraphEdge, r: DocGraphEdge) -> Bool {
        l.a == r.a ? l.b < r.b : l.a < r.a
    }
}

public struct DocGraphNode: Equatable, Sendable {
    public let path: String          // docs-relative, e.g. "guides/setup.md"
    public let title: String
    public let imagePaths: [String]  // docs-relative, with extension
    public init(path: String, title: String, imagePaths: [String]) {
        self.path = path; self.title = title; self.imagePaths = imagePaths
    }
}

public struct DocGraph: Equatable, Sendable {
    public let nodes: [DocGraphNode]
    public let edges: [DocGraphEdge]
    public init(nodes: [DocGraphNode], edges: [DocGraphEdge]) {
        self.nodes = nodes; self.edges = edges
    }
}

public struct DocGraphBuilder: Sendable {
    private let docs: DocsService
    public init(docs: DocsService) { self.docs = docs }

    public func build() -> DocGraph {
        // candidates() are already sorted by docsRelativePath and carry the first heading.
        let candidates = docs.candidates()
        let existing = Set(candidates.map(\.docsRelativePath))
        let resolver = DocLinkResolver(candidates: existing)

        var nodes: [DocGraphNode] = []
        var edges = Set<DocGraphEdge>()

        for c in candidates {
            // ponytail: one extra read per doc (candidates() already read for the heading).
            // Negligible for doc-sized corpora; reuses DocsService heading logic (DRY).
            let text = (try? docs.read("docs/\(c.docsRelativePath)")) ?? ""

            var seen = Set<String>()
            var images: [String] = []
            for ref in ImageRefScanner.scan(text) where seen.insert(ref.path).inserted {
                images.append(ref.path)
            }
            nodes.append(DocGraphNode(path: c.docsRelativePath,
                                      title: c.title ?? c.name,
                                      imagePaths: images))

            for ref in DocRefScanner.scan(text) {
                guard let res = resolver.resolve(ref.path), res.exists,
                      res.docsRelativePath != c.docsRelativePath else { continue }
                edges.insert(DocGraphEdge(c.docsRelativePath, res.docsRelativePath))
            }
        }
        return DocGraph(nodes: nodes, edges: edges.sorted())
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path swift/DetDocCore --filter DocGraphBuilder`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Services/DocGraph.swift swift/DetDocCore/Tests/DetDocCoreTests/DocGraphBuilderTests.swift
git commit -m "feat(core): build doc graph (nodes, undirected edges, images) from docs"
```

---

## Task 2: Core — force-directed auto-layout

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Services/ForceLayout.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/ForceLayoutTests.swift`

**Interfaces:**
- Consumes: `DocGraphPoint`, `DocGraphEdge` (Task 1).
- Produces: `enum ForceLayout { static func compute(nodeIDs: [String], edges: [DocGraphEdge], iterations: Int = 300) -> [String: DocGraphPoint] }`

- [ ] **Step 1: Write the failing test**

Create `swift/DetDocCore/Tests/DetDocCoreTests/ForceLayoutTests.swift`:

```swift
import Foundation
import Testing
@testable import DetDocCore

private func dist(_ a: DocGraphPoint, _ b: DocGraphPoint) -> Double {
    ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
}

@Test func connectedNodesEndCloserThanUnconnected() {
    let ids = ["a", "b", "c", "d"]
    let edges = [DocGraphEdge("a", "b"), DocGraphEdge("c", "d")]
    let p = ForceLayout.compute(nodeIDs: ids, edges: edges)

    let avgEdge = (dist(p["a"]!, p["b"]!) + dist(p["c"]!, p["d"]!)) / 2
    let nonEdge = [dist(p["a"]!, p["c"]!), dist(p["a"]!, p["d"]!),
                   dist(p["b"]!, p["c"]!), dist(p["b"]!, p["d"]!)]
    let avgNonEdge = nonEdge.reduce(0, +) / Double(nonEdge.count)
    #expect(avgEdge < avgNonEdge)
}

@Test func layoutIsDeterministic() {
    let ids = ["a", "b", "c"]
    let edges = [DocGraphEdge("a", "b")]
    #expect(ForceLayout.compute(nodeIDs: ids, edges: edges)
            == ForceLayout.compute(nodeIDs: ids, edges: edges))
}

@Test func handlesEmptyAndSingle() {
    #expect(ForceLayout.compute(nodeIDs: [], edges: []).isEmpty)
    #expect(ForceLayout.compute(nodeIDs: ["solo"], edges: []) == ["solo": DocGraphPoint(x: 0, y: 0)])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path swift/DetDocCore --filter ForceLayout`
Expected: FAIL — `cannot find 'ForceLayout' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `swift/DetDocCore/Sources/DetDocCore/Services/ForceLayout.swift`:

```swift
import Foundation

/// Deterministic Fruchterman–Reingold layout. No RNG: nodes seed on a circle by index,
/// coincident points are separated by a fixed deterministic nudge. Same input → same output.
public enum ForceLayout {
    public static func compute(nodeIDs: [String],
                               edges: [DocGraphEdge],
                               iterations: Int = 300) -> [String: DocGraphPoint] {
        let n = nodeIDs.count
        if n == 0 { return [:] }
        if n == 1 { return [nodeIDs[0]: DocGraphPoint(x: 0, y: 0)] }

        let area = Double(n) * 100_000.0
        let k = (area / Double(n)).squareRoot()          // ideal edge length
        let radius = k * Double(n) / (2 * .pi) + 1

        var pos: [String: (x: Double, y: Double)] = [:]
        for (i, id) in nodeIDs.enumerated() {
            let angle = 2 * .pi * Double(i) / Double(n)
            pos[id] = (radius * Foundation.cos(angle), radius * Foundation.sin(angle))
        }

        var temp = k * 2                                  // max displacement, cooled each pass
        for _ in 0..<iterations {
            var disp: [String: (x: Double, y: Double)] = [:]
            for id in nodeIDs { disp[id] = (0, 0) }

            // Repulsion between every pair.
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let a = nodeIDs[i], b = nodeIDs[j]
                    var dx = pos[a]!.x - pos[b]!.x
                    var dy = pos[a]!.y - pos[b]!.y
                    var d = (dx * dx + dy * dy).squareRoot()
                    if d < 0.01 { dx = 0.01 * Double(i - j); dy = 0.01; d = (dx * dx + dy * dy).squareRoot() }
                    let force = k * k / d
                    disp[a]!.x += dx / d * force; disp[a]!.y += dy / d * force
                    disp[b]!.x -= dx / d * force; disp[b]!.y -= dy / d * force
                }
            }
            // Attraction along edges.
            for e in edges {
                guard let pa = pos[e.a], let pb = pos[e.b] else { continue }
                let dx = pa.x - pb.x, dy = pa.y - pb.y
                var d = (dx * dx + dy * dy).squareRoot()
                if d < 0.01 { d = 0.01 }
                let force = d * d / k
                disp[e.a]!.x -= dx / d * force; disp[e.a]!.y -= dy / d * force
                disp[e.b]!.x += dx / d * force; disp[e.b]!.y += dy / d * force
            }
            // Apply, capped by current temperature.
            for id in nodeIDs {
                let d = disp[id]!
                let len = (d.x * d.x + d.y * d.y).squareRoot()
                if len > 0 {
                    let cap = Swift.min(len, temp)
                    pos[id]!.x += d.x / len * cap
                    pos[id]!.y += d.y / len * cap
                }
            }
            temp *= 0.95
        }
        return pos.mapValues { DocGraphPoint(x: $0.x, y: $0.y) }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path swift/DetDocCore --filter ForceLayout`
Expected: PASS (all three tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Services/ForceLayout.swift swift/DetDocCore/Tests/DetDocCoreTests/ForceLayoutTests.swift
git commit -m "feat(core): deterministic force-directed layout for the doc graph"
```

---

## Task 3: Core — persist positions + gitignore

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Services/CanvasLayoutStore.swift`
- Modify: `swift/DetDocCore/Sources/DetDocCore/Support/GitignoreManager.swift:4`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/CanvasLayoutStoreTests.swift`

**Interfaces:**
- Consumes: `DocGraphPoint` (Task 1).
- Produces: `struct CanvasLayoutStore: Sendable { init(root: URL); func load() -> [String: DocGraphPoint]; func save(_: [String: DocGraphPoint]) }`

- [ ] **Step 1: Write the failing test**

Create `swift/DetDocCore/Tests/DetDocCoreTests/CanvasLayoutStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func savesAndLoadsRoundTrip() {
    let tmp = TempDir()
    let store = CanvasLayoutStore(root: tmp.url)
    store.save(["a.md": DocGraphPoint(x: 12, y: -3.5)])
    #expect(store.load() == ["a.md": DocGraphPoint(x: 12, y: -3.5)])
}

@Test func loadMissingFileReturnsEmpty() {
    let tmp = TempDir()
    #expect(CanvasLayoutStore(root: tmp.url).load().isEmpty)
}

@Test func gitignoreCoversLayoutFile() {
    #expect(GitignoreManager.managedEntries.contains(".detdoc/canvas-layout.json"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path swift/DetDocCore --filter CanvasLayoutStore`
Expected: FAIL — `cannot find 'CanvasLayoutStore' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `swift/DetDocCore/Sources/DetDocCore/Services/CanvasLayoutStore.swift`:

```swift
import Foundation

/// Loads/saves user-dragged canvas positions to `.detdoc/canvas-layout.json` (local, gitignored).
/// Best-effort: never throws into the UI; a missing/corrupt file is treated as no saved layout.
public struct CanvasLayoutStore: Sendable {
    private let root: URL
    public init(root: URL) { self.root = root }

    private var fileURL: URL {
        root.appendingPathComponent(".detdoc").appendingPathComponent("canvas-layout.json")
    }

    public func load() -> [String: DocGraphPoint] {
        guard let data = try? Data(contentsOf: fileURL),
              let map = try? JSONDecoder().decode([String: DocGraphPoint].self, from: data)
        else { return [:] }
        return map
    }

    public func save(_ positions: [String: DocGraphPoint]) {
        guard let data = try? JSONEncoder().encode(positions) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL, atomically: true)
    }
}
```

Modify `swift/DetDocCore/Sources/DetDocCore/Support/GitignoreManager.swift:4` — add the layout file to the managed entries:

```swift
    public static let managedEntries = [".DS_Store", ".detdoc/runs/*", "!.detdoc/runs/.gitkeep", ".detdoc/canvas-layout.json", ".worktrees/"]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path swift/DetDocCore --filter CanvasLayoutStore`
Expected: PASS (all three tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Services/CanvasLayoutStore.swift swift/DetDocCore/Sources/DetDocCore/Support/GitignoreManager.swift swift/DetDocCore/Tests/DetDocCoreTests/CanvasLayoutStoreTests.swift
git commit -m "feat(core): persist canvas node positions to gitignored .detdoc file"
```

---

## Task 4: App — DocGraphViewModel

**Files:**
- Create: `swift/DetDocApp/Sources/Workspace/Docs/DocGraphViewModel.swift`
- Test: `swift/DetDocApp/Tests/DocGraphViewModelTests.swift`

**Interfaces:**
- Consumes: `DocGraphBuilder`, `DocGraph`, `ForceLayout`, `CanvasLayoutStore`, `DocGraphPoint`, `DocGraphEdge`, `DocsService`, `DetDocConfig` (Core).
- Produces:
  - `struct DocGraphViewModel.Node: Identifiable, Equatable { let path, title: String; let imagePaths: [String]; var position: CGPoint; var id: String { path } }`
  - `final class DocGraphViewModel` with: `nodes: [Node]`, `edges: [DocGraphEdge]`, `scale: CGFloat`, `offset: CGSize`, `zoomedImagePath: String?`, and methods `refresh()`, `moveNode(_ path: String, to: CGPoint)`, `persistPositions()`, `showImage(_:)`, `closeImage()`, `resetView()`.

- [ ] **Step 1: Write the failing test**

Create `swift/DetDocApp/Tests/DocGraphViewModelTests.swift`:

```swift
import Foundation
import Testing
@testable import DetDoc
@testable import DetDocCore

@MainActor
@Test func refreshMergesSavedAutoAndDropsRemoved() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    try fx.write("docs/a.md", "# A\nlink @b\n")
    try fx.write("docs/b.md", "# B\nback @a\n")
    // Pre-seed a saved position for a.md plus a stale entry for a deleted doc.
    CanvasLayoutStore(root: fx.root).save([
        "a.md": DocGraphPoint(x: 42, y: 7),
        "ghost.md": DocGraphPoint(x: 1, y: 1),
    ])

    let vm = DocGraphViewModel(root: fx.root, config: .default)
    vm.refresh()

    #expect(vm.nodes.map(\.path).sorted() == ["a.md", "b.md"])      // ghost.md dropped
    let a = try #require(vm.nodes.first { $0.path == "a.md" })
    #expect(a.position == CGPoint(x: 42, y: 7))                     // saved position kept
    let b = try #require(vm.nodes.first { $0.path == "b.md" })
    #expect(b.position != CGPoint(x: 42, y: 7))                    // b got an auto position
    #expect(vm.edges == [DocGraphEdge("a.md", "b.md")])
    withExtendedLifetime(fx) {}
}

@MainActor
@Test func moveAndPersistSurvivesReload() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    try fx.write("docs/a.md", "# A\n")

    let vm = DocGraphViewModel(root: fx.root, config: .default)
    vm.refresh()
    vm.moveNode("a.md", to: CGPoint(x: 100, y: 200))
    vm.persistPositions()

    let reloaded = DocGraphViewModel(root: fx.root, config: .default)
    reloaded.refresh()
    #expect(reloaded.nodes.first { $0.path == "a.md" }?.position == CGPoint(x: 100, y: 200))
    withExtendedLifetime(fx) {}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run via Xcode MCP `RunSomeTests` (scheme `DetDocApp`, target `DetDocAppTests`, suite `DocGraphViewModelTests`), or:
`cd swift/DetDocApp && xcodebuild test -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS' -only-testing:DetDocAppTests/refreshMergesSavedAutoAndDropsRemoved`
Expected: FAIL — `cannot find 'DocGraphViewModel' in scope` (build error).

- [ ] **Step 3: Write minimal implementation**

Create `swift/DetDocApp/Sources/Workspace/Docs/DocGraphViewModel.swift`:

```swift
import Foundation
import Observation
import DetDocCore

@MainActor
@Observable
final class DocGraphViewModel {
    struct Node: Identifiable, Equatable {
        let path: String
        let title: String
        let imagePaths: [String]
        var position: CGPoint
        var id: String { path }
    }

    private(set) var nodes: [Node] = []
    private(set) var edges: [DocGraphEdge] = []

    // Viewport + interaction state (driven by the view).
    var scale: CGFloat = 1
    var offset: CGSize = .zero
    var zoomedImagePath: String?

    private let root: URL
    private let config: DetDocConfig
    private let store: CanvasLayoutStore

    init(root: URL, config: DetDocConfig) {
        self.root = root
        self.config = config
        self.store = CanvasLayoutStore(root: root)
    }

    func refresh() {
        let graph = DocGraphBuilder(docs: DocsService(root: root, config: config)).build()
        let saved = store.load()
        let auto = ForceLayout.compute(nodeIDs: graph.nodes.map(\.path), edges: graph.edges)
        nodes = graph.nodes.map { n in
            let p = saved[n.path] ?? auto[n.path] ?? DocGraphPoint(x: 0, y: 0)
            return Node(path: n.path, title: n.title, imagePaths: n.imagePaths,
                        position: CGPoint(x: p.x, y: p.y))
        }
        edges = graph.edges
    }

    func moveNode(_ path: String, to point: CGPoint) {
        guard let i = nodes.firstIndex(where: { $0.path == path }) else { return }
        nodes[i].position = point
    }

    func persistPositions() {
        var map: [String: DocGraphPoint] = [:]
        for n in nodes { map[n.path] = DocGraphPoint(x: n.position.x, y: n.position.y) }
        store.save(map)
    }

    func showImage(_ path: String) { zoomedImagePath = path }
    func closeImage() { zoomedImagePath = nil }
    func resetView() { scale = 1; offset = .zero }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run both tests in `DocGraphViewModelTests` (Xcode MCP `RunSomeTests` or `xcodebuild test -only-testing:DetDocAppTests/DocGraphViewModelTests`).
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocApp/Sources/Workspace/Docs/DocGraphViewModel.swift swift/DetDocApp/Tests/DocGraphViewModelTests.swift
git commit -m "feat(app): DocGraphViewModel merges saved + auto layout, drag + persist"
```

---

## Task 5: App — DocGraphView (canvas rendering)

**Files:**
- Create: `swift/DetDocApp/Sources/Workspace/Docs/DocGraphView.swift`

**Interfaces:**
- Consumes: `DocGraphViewModel` (Task 4), `DocGraphEdge` (Core).
- Produces: `struct DocGraphView: View { init(model: DocGraphViewModel, root: URL, onOpenDoc: @escaping (String) -> Void) }`

No unit test (pure SwiftUI rendering); verified by build + preview render. The view model logic it drives is already tested in Task 4.

- [ ] **Step 1: Write the implementation**

Create `swift/DetDocApp/Sources/Workspace/Docs/DocGraphView.swift`:

```swift
import SwiftUI
import AppKit
import DetDocCore

struct DocGraphView: View {
    @Bindable var model: DocGraphViewModel
    let root: URL
    let onOpenDoc: (String) -> Void

    /// Fixed world canvas; nodes are placed relative to its centre.
    private let worldSize: CGFloat = 6000
    private var center: CGPoint { CGPoint(x: worldSize / 2, y: worldSize / 2) }

    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)

            world
                .frame(width: worldSize, height: worldSize)
                .scaleEffect(model.scale)
                .offset(model.offset)
                .coordinateSpace(name: "graph")
        }
        .contentShape(Rectangle())
        .gesture(panGesture)
        .gesture(zoomGesture)
        .overlay(alignment: .topTrailing) { resetButton }
        .overlay { imageOverlay }
        .accessibilityIdentifier("docGraph.canvas")
        .onAppear { model.refresh() }
    }

    // MARK: World (edges + nodes share one coordinate space)

    private var world: some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                for e in model.edges {
                    guard let a = model.nodes.first(where: { $0.path == e.a }),
                          let b = model.nodes.first(where: { $0.path == e.b }) else { continue }
                    var path = Path()
                    path.move(to: CGPoint(x: center.x + a.position.x, y: center.y + a.position.y))
                    path.addLine(to: CGPoint(x: center.x + b.position.x, y: center.y + b.position.y))
                    ctx.stroke(path, with: .color(Color(nsColor: .separatorColor)), lineWidth: 1.5)
                }
            }
            .frame(width: worldSize, height: worldSize)

            ForEach(model.nodes) { node in
                DocGraphNodeView(
                    node: node, root: root,
                    onOpen: { onOpenDoc(node.path) },
                    onImageTap: { model.showImage($0) }
                )
                .position(x: center.x + node.position.x, y: center.y + node.position.y)
                .gesture(nodeDrag(node))
            }
        }
    }

    // MARK: Gestures

    private func nodeDrag(_ node: DocGraphViewModel.Node) -> some Gesture {
        DragGesture(coordinateSpace: .named("graph"))
            .onChanged { v in
                model.moveNode(node.path, to: CGPoint(x: v.location.x - center.x, y: v.location.y - center.y))
            }
            .onEnded { _ in model.persistPositions() }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                model.offset = CGSize(width: panStart.width + v.translation.width,
                                      height: panStart.height + v.translation.height)
            }
            .onEnded { _ in panStart = model.offset }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { v in model.scale = max(0.2, min(3, zoomStart * v.magnification)) }
            .onEnded { _ in zoomStart = model.scale }
    }

    @State private var panStart: CGSize = .zero
    @State private var zoomStart: CGFloat = 1

    // MARK: Overlays

    private var resetButton: some View {
        Button { model.resetView() } label: { Label("Reset view", systemImage: "scope") }
            .padding(8)
            .accessibilityIdentifier("docGraph.resetView")
    }

    @ViewBuilder private var imageOverlay: some View {
        if let path = model.zoomedImagePath,
           let image = NSImage(contentsOf: root.appendingPathComponent("docs").appendingPathComponent(path)) {
            ZStack {
                Color.black.opacity(0.6).ignoresSafeArea()
                Image(nsImage: image)
                    .resizable().scaledToFit()
                    .padding(40)
            }
            .contentShape(Rectangle())
            .onTapGesture { model.closeImage() }
            .accessibilityIdentifier("docGraph.imageOverlay")
        }
    }
}

// MARK: - Node card

private struct DocGraphNodeView: View {
    let node: DocGraphViewModel.Node
    let root: URL
    let onOpen: () -> Void
    let onImageTap: (String) -> Void

    var body: some View {
        VStack(spacing: 4) {
            if let first = node.imagePaths.first,
               let image = NSImage(contentsOf: root.appendingPathComponent("docs").appendingPathComponent(first)) {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: image)
                        .resizable().scaledToFill()
                        .frame(width: 120, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                        .onTapGesture { onImageTap(first) }
                        .accessibilityIdentifier("docGraph.image.\(node.path)")
                    if node.imagePaths.count > 1 {
                        Text("+\(node.imagePaths.count - 1)")
                            .font(.caption2).padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.black.opacity(0.6)).foregroundStyle(.white)
                            .clipShape(Capsule()).padding(4)
                    }
                }
            }
            Text(node.title).font(.callout).lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: 160)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .accessibilityIdentifier("docGraph.node.\(node.path)")
    }
}

// MARK: - Previews

#Preview("Few connected nodes") {
    let model = DocGraphViewModel(root: URL(fileURLWithPath: "/tmp"), config: .default)
    model.setPreviewState(
        nodes: [
            .init(path: "setup.md", title: "Setup", imagePaths: [], position: CGPoint(x: -120, y: -40)),
            .init(path: "api.md", title: "API", imagePaths: [], position: CGPoint(x: 120, y: -40)),
            .init(path: "deploy.md", title: "Deploy", imagePaths: [], position: CGPoint(x: 0, y: 90)),
        ],
        edges: [DocGraphEdge("setup.md", "api.md"), DocGraphEdge("api.md", "deploy.md")]
    )
    return DocGraphView(model: model, root: URL(fileURLWithPath: "/tmp"), onOpenDoc: { _ in })
        .frame(width: 600, height: 400)
}

#Preview("Empty graph") {
    let model = DocGraphViewModel(root: URL(fileURLWithPath: "/tmp"), config: .default)
    model.setPreviewState(nodes: [], edges: [])
    return DocGraphView(model: model, root: URL(fileURLWithPath: "/tmp"), onOpenDoc: { _ in })
        .frame(width: 600, height: 400)
}
```

- [ ] **Step 2: Add the preview seam to the view model**

The previews need to inject state without touching the filesystem. Add to `DocGraphViewModel` (Task 4 file):

```swift
#if DEBUG
    /// Preview/test seam: inject node + edge state without reading the filesystem.
    func setPreviewState(nodes: [Node], edges: [DocGraphEdge]) {
        self.nodes = nodes
        self.edges = edges
    }
#endif
```

But `refresh()` runs in `onAppear` and would overwrite preview state with an empty `/tmp` graph. Guard it: change `onAppear { model.refresh() }` in `DocGraphView` to:

```swift
        .onAppear { if model.nodes.isEmpty && model.edges.isEmpty { model.refresh() } }
```

(For the "Empty graph" preview this calls `refresh()` against `/tmp`, which yields an empty graph — still empty, correct.)

- [ ] **Step 3: Build and render previews**

Build the app target (Xcode MCP `BuildProject` scheme `DetDocApp`, or `xcodebuild build -project swift/DetDocApp/DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS'`).
Expected: BUILD SUCCEEDED.

Render both previews (Xcode MCP `RenderPreview` for `DocGraphView.swift`, both preview names).
Expected: "Few connected nodes" shows three labelled cards joined by two lines; "Empty graph" shows an empty background with the reset button.

- [ ] **Step 4: Commit**

```bash
git add swift/DetDocApp/Sources/Workspace/Docs/DocGraphView.swift swift/DetDocApp/Sources/Workspace/Docs/DocGraphViewModel.swift
git commit -m "feat(app): DocGraphView — edges canvas, node cards, pan/zoom, image overlay"
```

---

## Task 6: App — Workspace toolbar toggle + detail swap

**Files:**
- Modify: `swift/DetDocApp/Sources/Workspace/WorkspaceView.swift`

**Interfaces:**
- Consumes: `DocGraphViewModel` (Task 4), `DocGraphView` (Task 5).
- Produces: a toolbar "Canvas" toggle; the detail area shows `DocGraphView` when on; tapping a node opens the doc and returns to the editor.

No new unit test — covered by Task 4's view-model tests; verified by build + manual toggle. The doc-open path reuses the existing `selectedDoc` mechanism that other tests already exercise.

- [ ] **Step 1: Add the view model + toggle state**

In `WorkspaceView` add two stored properties next to the existing `@State` declarations (after `_docSearch`, near line 14-19):

```swift
    @State private var graph: DocGraphViewModel
    @State private var showCanvas = false
```

In `init(root:)`, after `_docSearch = State(...)` (around line 34), add:

```swift
        _graph = State(initialValue: DocGraphViewModel(root: root, config: config))
```

- [ ] **Step 2: Swap the detail content**

Replace the `detail:` closure body (currently the `DocEditorScreen(...)` block at lines 50-59) with:

```swift
        } detail: {
            if showCanvas {
                DocGraphView(model: graph, root: root, onOpenDoc: { docPath in
                    selectedDoc = docPath
                    showCanvas = false
                })
            } else {
                DocEditorScreen(editor: editor, resolver: linkResolver,
                                imageImporter: imageImporter,
                                candidatesProvider: {
                                    let svc = DocsService(root: root, config: self.config)
                                    return svc.candidates()
                                }) { docPath in
                    if !tree.isDirectory(docPath) { selectedDoc = docPath }
                }
            }
        }
```

- [ ] **Step 3: Add the toolbar toggle**

In the `ToolbarItemGroup` (after the "Fix…" button, around line 67), add:

```swift
                Button { showCanvas.toggle() } label: {
                    Label("Canvas", systemImage: showCanvas ? "doc.text" : "point.3.connected.trianglepath.dotted")
                }
                .accessibilityIdentifier("toolbar.toggleCanvas")
```

- [ ] **Step 4: Build**

Build the app target (Xcode MCP `BuildProject` scheme `DetDocApp`, or `xcodebuild build`).
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Run the full app + view-model test suites**

Run: `swift test --package-path swift/DetDocCore` (all Core tests) and the `DetDocAppTests` target (Xcode MCP `RunAllTests` or `xcodebuild test`).
Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add swift/DetDocApp/Sources/Workspace/WorkspaceView.swift
git commit -m "feat(app): toolbar Canvas toggle swaps editor for the doc graph"
```

---

## Self-Review

**Spec coverage:**
- "docs as nodes, doc→doc links as lines" → Task 1 (builder) + Task 5 (edges Canvas, node cards). ✓
- "images as thumbnails, click for full size" → Task 5 (`DocGraphNodeView` thumbnail + `+N`, `imageOverlay`). ✓
- "auto-layout first show + drag persists (hybrid)" → Task 2 (ForceLayout) + Task 3 (store) + Task 4 (merge, moveNode, persist). ✓
- "open a doc from the canvas" → Task 6 (`onOpenDoc` → `selectedDoc`, return to editor). ✓
- "new representation, toolbar toggle, tree stays" → Task 6. ✓
- "local-only positions, gitignored" → Task 3 (`.detdoc/canvas-layout.json` + managedEntries). ✓
- Non-goals (no code links, no live physics, no shared layout) respected. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code. ✓

**Type consistency:** `DocGraphPoint`/`DocGraphEdge`/`DocGraphNode`/`DocGraph` defined in Task 1 and consumed unchanged in Tasks 2–6. `ForceLayout.compute(nodeIDs:edges:)`, `CanvasLayoutStore.load()/save(_:)`, `DocGraphViewModel.refresh()/moveNode(_:to:)/persistPositions()/showImage(_:)/closeImage()/resetView()`, `DocGraphView(model:root:onOpenDoc:)` — names match across tasks. ✓
