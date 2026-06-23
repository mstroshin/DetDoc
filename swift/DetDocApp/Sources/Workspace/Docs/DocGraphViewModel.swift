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
    /// Nodes the user has placed by hand; only these are persisted, so un-moved nodes keep
    /// following the folder-grouped auto layout (and re-flow when docs change).
    private var movedPaths: Set<String> = []

    init(root: URL, config: DetDocConfig) {
        self.root = root
        self.config = config
        self.store = CanvasLayoutStore(root: root)
    }

    /// Parent folder of a docs-relative path ("" for a root-level doc).
    static func parentFolder(_ path: String) -> String {
        guard let i = path.lastIndex(of: "/") else { return "" }
        return String(path[..<i])
    }

    func refresh() {
        let graph = DocGraphBuilder(docs: DocsService(root: root, config: config)).build()
        let saved = store.load()
        let folders = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.path, Self.parentFolder($0.path)) })
        let auto = ForceLayout.compute(nodeIDs: graph.nodes.map(\.path), edges: graph.edges, groups: folders)
        nodes = graph.nodes.map { n in
            let p = saved[n.path] ?? auto[n.path] ?? DocGraphPoint(x: 0, y: 0)
            return Node(path: n.path, title: n.title, imagePaths: n.imagePaths,
                        position: CGPoint(x: p.x, y: p.y))
        }
        edges = graph.edges
        // Saved nodes are user-placed overrides; keep treating them as moved so they persist.
        movedPaths = Set(graph.nodes.map(\.path)).intersection(saved.keys)
    }

    func moveNode(_ path: String, to point: CGPoint) {
        guard let i = nodes.firstIndex(where: { $0.path == path }) else { return }
        nodes[i].position = point
        movedPaths.insert(path)
    }

    func persistPositions() {
        var map: [String: DocGraphPoint] = [:]
        for n in nodes where movedPaths.contains(n.path) {
            map[n.path] = DocGraphPoint(x: n.position.x, y: n.position.y)
        }
        store.save(map)
    }

    func showImage(_ path: String) { zoomedImagePath = path }
    func closeImage() { zoomedImagePath = nil }
    func resetView() { scale = 1; offset = .zero }

#if DEBUG
    /// Preview/test seam: inject node + edge state without reading the filesystem.
    func setPreviewState(nodes: [Node], edges: [DocGraphEdge]) {
        self.nodes = nodes
        self.edges = edges
    }
#endif
}
