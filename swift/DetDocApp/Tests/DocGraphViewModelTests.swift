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

    #expect(vm.nodes.map(\.path).contains("a.md"))                    // a.md present
    #expect(vm.nodes.map(\.path).contains("b.md"))                    // b.md present
    #expect(!vm.nodes.map(\.path).contains("ghost.md"))               // ghost.md dropped
    let a = try #require(vm.nodes.first { $0.path == "a.md" })
    #expect(a.position == CGPoint(x: 42, y: 7))                      // saved position kept
    let b = try #require(vm.nodes.first { $0.path == "b.md" })
    #expect(b.position != CGPoint(x: 42, y: 7))                      // b got an auto position
    #expect(b.position != .zero)                                     // ...not the origin fallback
    #expect(vm.edges.contains(DocGraphEdge("a.md", "b.md")))
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

@MainActor
@Test func persistsOnlyMovedNodes() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    try fx.write("docs/a.md", "# A\n")
    try fx.write("docs/b.md", "# B\n")

    let vm = DocGraphViewModel(root: fx.root, config: .default)
    vm.refresh()
    vm.moveNode("a.md", to: CGPoint(x: 5, y: 6))
    vm.persistPositions()

    // Only the moved node is saved; un-moved nodes keep following the auto layout.
    let saved = CanvasLayoutStore(root: fx.root).load()
    #expect(saved.keys.sorted() == ["a.md"])
    #expect(saved["a.md"] == DocGraphPoint(x: 5, y: 6))
    withExtendedLifetime(fx) {}
}

@MainActor
@Test func nodePathOpensInEditorWhenDocsPrefixed() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    try fx.write("docs/guides/setup.md", "# Setup\nbody\n")

    let vm = DocGraphViewModel(root: fx.root, config: .default)
    vm.refresh()
    let node = try #require(vm.nodes.first { $0.path == "guides/setup.md" })

    let editor = DocEditorViewModel(root: fx.root, config: .default)
    // WorkspaceView prepends "docs/" before handing the path to the editor.
    editor.open("docs/" + node.path)
    #expect(editor.error == nil)
    #expect(editor.source.contains("Setup"))

    // The bare (docs/-stripped) node path must NOT resolve — guards against
    // anyone "simplifying" the prefix away again.
    let editor2 = DocEditorViewModel(root: fx.root, config: .default)
    editor2.open(node.path)
    #expect(editor2.error != nil)
    withExtendedLifetime(fx) {}
}
