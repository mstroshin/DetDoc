import SwiftUI

/// A freehand sketch sheet. The user draws on a solid black board with a chosen
/// pen color and width; "Вставить" rasterizes the strokes to PNG and hands the
/// data back so the caller can store it in the doc's `assets/` like any image.
struct CanvasSketchView: View {
    var onInsert: (Data) -> Void
    var onCancel: () -> Void

    @State private var strokes: [CanvasStroke]
    @State private var current: CanvasStroke?
    @State private var color: CanvasColor = .white
    @State private var tool: Tool = .pen
    @State private var width: CGFloat = 4
    @State private var boardSize: CGSize = .zero

    private let widths: [CGFloat] = [2, 4, 8]

    /// `initialStrokes` seeds the board — used by previews to show a drawn state.
    init(onInsert: @escaping (Data) -> Void,
         onCancel: @escaping () -> Void,
         initialStrokes: [CanvasStroke] = []) {
        self.onInsert = onInsert
        self.onCancel = onCancel
        _strokes = State(initialValue: initialStrokes)
    }

    private enum Tool { case pen, eraser }

    /// The eraser draws with the board background, clearing strokes beneath it.
    private var activeColor: CanvasColor { tool == .eraser ? .black : color }

    private var allStrokes: [CanvasStroke] {
        if let current { return strokes + [current] }
        return strokes
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            board
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 460)
    }

    // MARK: - Drawing board

    private var board: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                for stroke in allStrokes { Self.draw(stroke, into: ctx) }
            }
            .background(Color.black)
            .contentShape(Rectangle())
            .accessibilityIdentifier("canvas.board")
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if current == nil {
                            current = CanvasStroke(points: [value.location], color: activeColor, width: width)
                        } else {
                            current?.points.append(value.location)
                        }
                    }
                    .onEnded { _ in
                        if let current { strokes.append(current) }
                        current = nil
                    }
            )
            .onAppear { boardSize = geo.size }
            .onChange(of: geo.size) { _, new in boardSize = new }
        }
        .frame(minHeight: 320)
    }

    private static func draw(_ stroke: CanvasStroke, into ctx: GraphicsContext) {
        guard let first = stroke.points.first else { return }
        let shading = GraphicsContext.Shading.color(stroke.color.swiftUIColor)
        if stroke.points.count == 1 {
            let r = max(stroke.width / 2, 0.5)
            let dot = CGRect(x: first.x - r, y: first.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: dot), with: shading)
            return
        }
        var path = Path()
        path.move(to: first)
        for p in stroke.points.dropFirst() { path.addLine(to: p) }
        ctx.stroke(path, with: shading, style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round))
    }

    // MARK: - Top toolbar (colors + pen width)

    private var toolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                ForEach(Array(CanvasColor.palette.enumerated()), id: \.offset) { item in
                    colorSwatch(item.element, index: item.offset)
                }
                eraserSwatch
            }
            Divider().frame(height: 24)
            HStack(spacing: 10) {
                ForEach(widths, id: \.self) { w in widthSwatch(w) }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func colorSwatch(_ c: CanvasColor, index: Int) -> some View {
        Button { tool = .pen; color = c } label: {
            Circle()
                .fill(c.swiftUIColor)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(.secondary.opacity(0.5), lineWidth: 1))
                .overlay(Circle().stroke(Color.accentColor, lineWidth: 3).padding(-3)
                    .opacity(tool == .pen && color == c ? 1 : 0))
        }
        .buttonStyle(.plain)
        .help("Цвет пера")
        .accessibilityIdentifier("canvas.color.\(index)")
    }

    private var eraserSwatch: some View {
        Button { tool = .eraser } label: {
            Image(systemName: "eraser.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(.secondary.opacity(0.22)))
                .overlay(Circle().strokeBorder(.secondary.opacity(0.5), lineWidth: 1))
                .overlay(Circle().stroke(Color.accentColor, lineWidth: 3).padding(-3)
                    .opacity(tool == .eraser ? 1 : 0))
        }
        .buttonStyle(.plain)
        .help("Ластик")
        .accessibilityIdentifier("canvas.tool.eraser")
    }

    private func widthSwatch(_ w: CGFloat) -> some View {
        Button { width = w } label: {
            Circle()
                .fill(Color.primary)
                .frame(width: w + 8, height: w + 8)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(Color.accentColor.opacity(width == w ? 0.25 : 0))
                )
        }
        .buttonStyle(.plain)
        .help("Толщина пера")
        .accessibilityIdentifier("canvas.width.\(Int(w))")
    }

    // MARK: - Bottom toolbar (undo / clear / cancel / insert)

    private var footer: some View {
        HStack {
            Button { if !strokes.isEmpty { strokes.removeLast() } } label: {
                Label("Отменить", systemImage: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(strokes.isEmpty)
            .accessibilityIdentifier("canvas.undo")

            Button(role: .destructive) { strokes.removeAll(); current = nil } label: {
                Label("Очистить", systemImage: "trash")
            }
            .disabled(strokes.isEmpty)
            .accessibilityIdentifier("canvas.clear")

            Spacer()

            Button("Отмена") { onCancel() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("canvas.cancel")
            Button("Вставить") { insert() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(strokes.isEmpty)
                .accessibilityIdentifier("canvas.insert")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func insert() {
        let size = boardSize.width > 0 && boardSize.height > 0 ? boardSize : CGSize(width: 600, height: 360)
        guard let data = CanvasImageRenderer.png(strokes: strokes, size: size, scale: 2) else { return }
        onInsert(data)
    }
}

#Preview("Empty") {
    CanvasSketchView(onInsert: { _ in }, onCancel: {})
        .frame(width: 640, height: 520)
}

#Preview("With sketch") {
    CanvasSketchView(onInsert: { _ in }, onCancel: {}, initialStrokes: [
        CanvasStroke(points: [CGPoint(x: 120, y: 150), CGPoint(x: 300, y: 210), CGPoint(x: 200, y: 320)],
                     color: .white, width: 4),
        CanvasStroke(points: [CGPoint(x: 340, y: 130), CGPoint(x: 470, y: 250)],
                     color: .red, width: 8),
        CanvasStroke(points: [CGPoint(x: 150, y: 360), CGPoint(x: 430, y: 380)],
                     color: .green, width: 2),
    ])
    .frame(width: 640, height: 520)
}
