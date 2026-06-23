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
    // Edges: directed — a links @b and b links @a, so both directions appear
    // (sorted by source then target); dangling @nope excluded.
    #expect(graph.edges == [DocGraphEdge("a.md", "b.md"), DocGraphEdge("b.md", "a.md")])
}

@Test func dropsSelfLinks() throws {
    let tmp = TempDir()
    try write(tmp, "docs/a.md", "# A\nLink to myself @a here.\n")
    let graph = DocGraphBuilder(docs: DocsService(root: tmp.url, config: .default)).build()
    #expect(graph.edges.isEmpty)
}
