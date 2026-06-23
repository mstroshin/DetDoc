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
                let color = Color(nsColor: .tertiaryLabelColor)
                for e in model.edges {
                    guard let a = model.nodes.first(where: { $0.path == e.a }),
                          let b = model.nodes.first(where: { $0.path == e.b }) else { continue }
                    let shapes = directedEdge(from: worldPoint(a.position), to: worldPoint(b.position))
                    ctx.stroke(shapes.line, with: .color(color), lineWidth: 1.5)
                    ctx.fill(shapes.head, with: .color(color))
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
                .position(worldPoint(node.position))
                .gesture(nodeDrag(node))
            }
        }
    }

    /// A line from the source's centre to the target's edge, plus a filled arrowhead at the
    /// target end so the line reads as "a depends on b".
    private func directedEdge(from a: CGPoint, to b: CGPoint) -> (line: Path, head: Path) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = (dx * dx + dy * dy).squareRoot()
        var line = Path(); line.move(to: a)
        guard len > 1 else { line.addLine(to: b); return (line, Path()) }
        let ux = dx / len, uy = dy / len
        let inset: CGFloat = 48          // back the head off so it sits at the card edge, not under it
        let tip = CGPoint(x: b.x - ux * inset, y: b.y - uy * inset)
        line.addLine(to: tip)
        let size: CGFloat = 11, half: CGFloat = 6
        let base = CGPoint(x: tip.x - ux * size, y: tip.y - uy * size)
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
