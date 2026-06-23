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
