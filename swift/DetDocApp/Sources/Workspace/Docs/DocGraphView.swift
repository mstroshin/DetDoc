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
        .onAppear { if model.nodes.isEmpty && model.edges.isEmpty { model.refresh() } }
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
