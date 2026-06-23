import SwiftUI
import AppKit
import DetDocCore

struct DocGraphView: View {
    @Bindable var model: DocGraphViewModel
    let root: URL
    /// Currently selected doc, project-root-relative (e.g. "docs/guides/setup.md").
    /// Drives the highlight; shared with the file tree.
    let selectedDoc: String?
    /// Single click on a node — select/focus it (stays on the canvas).
    let onSelectDoc: (String) -> Void
    /// Double click on a node — open its text (caller switches away from the canvas).
    let onOpenDoc: (String) -> Void

    /// Fixed world canvas; nodes are placed relative to its centre.
    private let worldSize: CGFloat = 6000
    private var center: CGPoint { CGPoint(x: worldSize / 2, y: worldSize / 2) }

    /// Measured card sizes (world points) per node path, so edges can meet the real
    /// rectangle border. Falls back to a default until a node has been laid out once.
    @State private var nodeSizes: [String: CGSize] = [:]
    private let defaultNodeSize = CGSize(width: 130, height: 38)

    var body: some View {
        // The world is a fixed 6000pt canvas. Pin it to the detail pane's exact size via a
        // GeometryReader-driven fixed frame and clip — otherwise the oversized content
        // expands the view and draws over the sidebar, toolbar, and inspector.
        GeometryReader { geo in
            ZStack {
                Color(nsColor: .textBackgroundColor)

                world
                    .frame(width: worldSize, height: worldSize)
                    .scaleEffect(model.scale)
                    .offset(model.offset)
                    .coordinateSpace(name: "graph")
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(panGesture)
            .gesture(zoomGesture)
            .overlay(alignment: .topTrailing) { resetButton }
            .overlay { imageOverlay }
        }
        .accessibilityIdentifier("docGraph.canvas")
        .onAppear { if model.nodes.isEmpty && model.edges.isEmpty { model.refresh() } }
    }

    private func worldPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: center.x + p.x, y: center.y + p.y) }
    private func isSelected(_ node: DocGraphViewModel.Node) -> Bool { selectedDoc == "docs/" + node.path }

    // MARK: World (edges + nodes share one coordinate space)

    private var world: some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                let lineColor = Color(nsColor: .tertiaryLabelColor)
                let headColor = Color(nsColor: .systemGray)   // opaque, so the line never shows through
                for e in model.edges {
                    guard let a = model.nodes.first(where: { $0.path == e.a }),
                          let b = model.nodes.first(where: { $0.path == e.b }) else { continue }
                    let shapes = directedEdge(
                        srcCenter: worldPoint(a.position), srcSize: nodeSizes[e.a] ?? defaultNodeSize,
                        dstCenter: worldPoint(b.position), dstSize: nodeSizes[e.b] ?? defaultNodeSize)
                    ctx.stroke(shapes.line, with: .color(lineColor), lineWidth: 1.5)
                    ctx.fill(shapes.head, with: .color(headColor))
                }
            }
            .frame(width: worldSize, height: worldSize)

            ForEach(model.nodes) { node in
                DocGraphNodeView(
                    node: node, root: root, isSelected: isSelected(node),
                    onSelect: { onSelectDoc(node.path) },
                    onOpen: { onOpenDoc(node.path) },
                    onImageTap: { model.showImage($0) }
                )
                .onGeometryChange(for: CGSize.self) { $0.size } action: { nodeSizes[node.path] = $0 }
                .position(worldPoint(node.position))
                .gesture(nodeDrag(node))
            }
        }
    }

    /// Point where the ray from a rectangle's centre toward `p` crosses the rectangle border.
    static func borderPoint(center c: CGPoint, size: CGSize, toward p: CGPoint) -> CGPoint {
        let dx = p.x - c.x, dy = p.y - c.y
        if dx == 0 && dy == 0 { return c }
        let hw = size.width / 2, hh = size.height / 2
        let sx = dx == 0 ? CGFloat.greatestFiniteMagnitude : hw / abs(dx)
        let sy = dy == 0 ? CGFloat.greatestFiniteMagnitude : hh / abs(dy)
        let s = min(sx, sy)
        return CGPoint(x: c.x + dx * s, y: c.y + dy * s)
    }

    /// Edge clipped to both node rectangles: it starts on the source's border and the
    /// arrowhead tip lands exactly on the target's border, so it slides along the edges as
    /// nodes move.
    private func directedEdge(srcCenter: CGPoint, srcSize: CGSize,
                              dstCenter: CGPoint, dstSize: CGSize) -> (line: Path, head: Path) {
        let start = Self.borderPoint(center: srcCenter, size: srcSize, toward: dstCenter)
        let tip = Self.borderPoint(center: dstCenter, size: dstSize, toward: srcCenter)
        let dx = tip.x - start.x, dy = tip.y - start.y
        let len = (dx * dx + dy * dy).squareRoot()
        var line = Path(); line.move(to: start)
        guard len > 1 else { line.addLine(to: tip); return (line, Path()) }
        let ux = dx / len, uy = dy / len
        let headLen: CGFloat = 11, half: CGFloat = 6
        let base = CGPoint(x: tip.x - ux * headLen, y: tip.y - uy * headLen)
        line.addLine(to: base)           // stop at the arrowhead base; the opaque head finishes the tip
        let px = -uy, py = ux            // perpendicular unit vector
        var head = Path()
        head.move(to: tip)
        head.addLine(to: CGPoint(x: base.x + px * half, y: base.y + py * half))
        head.addLine(to: CGPoint(x: base.x - px * half, y: base.y - py * half))
        head.closeSubpath()
        return (line, head)
    }

    // MARK: Gestures

    private func nodeDrag(_ node: DocGraphViewModel.Node) -> some Gesture {
        DragGesture(coordinateSpace: .named("graph"))
            .onChanged { v in
                // Move by the drag delta from the grab position, not by snapping the node's
                // centre to the cursor — otherwise grabbing a node off-centre makes it jump.
                if draggingPath != node.path {
                    draggingPath = node.path
                    dragStartPos = node.position
                }
                model.moveNode(node.path, to: CGPoint(x: dragStartPos.x + v.translation.width,
                                                      y: dragStartPos.y + v.translation.height))
            }
            .onEnded { _ in
                draggingPath = nil
                model.persistPositions()
            }
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
    @State private var draggingPath: String?
    @State private var dragStartPos: CGPoint = .zero

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
    let isSelected: Bool
    let onSelect: () -> Void
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
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                          lineWidth: isSelected ? 2.5 : 1))
        .contentShape(Rectangle())
        // Double click opens the text; a single click only selects/focuses the node.
        .onTapGesture(count: 2) { onOpen() }
        .onTapGesture(count: 1) { onSelect() }
        .accessibilityIdentifier("docGraph.node.\(node.path)")
    }
}

// MARK: - Previews

#Preview("Connected nodes, one selected") {
    let model = DocGraphViewModel(root: URL(fileURLWithPath: "/tmp"), config: .default)
    model.setPreviewState(
        nodes: [
            .init(path: "setup.md", title: "Setup", imagePaths: [], position: CGPoint(x: -120, y: -40)),
            .init(path: "api.md", title: "API", imagePaths: [], position: CGPoint(x: 120, y: -40)),
            .init(path: "deploy.md", title: "Deploy", imagePaths: [], position: CGPoint(x: 0, y: 90)),
        ],
        // setup → api → deploy (arrows point at the dependency).
        edges: [DocGraphEdge("setup.md", "api.md"), DocGraphEdge("api.md", "deploy.md")]
    )
    return DocGraphView(model: model, root: URL(fileURLWithPath: "/tmp"),
                        selectedDoc: "docs/api.md", onSelectDoc: { _ in }, onOpenDoc: { _ in })
        .frame(width: 600, height: 400)
}

#Preview("Empty graph") {
    let model = DocGraphViewModel(root: URL(fileURLWithPath: "/tmp"), config: .default)
    model.setPreviewState(nodes: [], edges: [])
    return DocGraphView(model: model, root: URL(fileURLWithPath: "/tmp"),
                        selectedDoc: nil, onSelectDoc: { _ in }, onOpenDoc: { _ in })
        .frame(width: 600, height: 400)
}
