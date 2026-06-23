import Foundation

public struct DocGraphPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// Directed link edge: `a` (the source doc) points at `b` (the dependency it links to).
/// Direction is kept — A→B and B→A are two distinct edges; exact duplicates dedupe.
public struct DocGraphEdge: Hashable, Sendable, Comparable {
    public let a: String   // source: the doc that contains the link
    public let b: String   // target: the linked dependency the arrow points at
    public init(_ a: String, _ b: String) {
        self.a = a; self.b = b
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
