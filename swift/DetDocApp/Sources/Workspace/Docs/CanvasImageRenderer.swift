import AppKit
import SwiftUI

/// A pen color for the sketch canvas, stored as explicit sRGB components so the
/// model stays `Sendable` and rasterization is deterministic (no implicit color
/// space conversions). White is the default; the palette adds five more.
struct CanvasColor: Equatable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    var swiftUIColor: Color { Color(.sRGB, red: red, green: green, blue: blue) }
}

extension CanvasColor {
    static let white  = CanvasColor(red: 1.00, green: 1.00, blue: 1.00)
    static let red    = CanvasColor(red: 1.00, green: 0.23, blue: 0.19)
    static let orange = CanvasColor(red: 1.00, green: 0.58, blue: 0.00)
    static let yellow = CanvasColor(red: 1.00, green: 0.84, blue: 0.04)
    static let green  = CanvasColor(red: 0.20, green: 0.82, blue: 0.35)
    static let blue   = CanvasColor(red: 0.22, green: 0.56, blue: 1.00)

    /// The board background — the eraser paints with this to clear strokes back to black.
    static let black  = CanvasColor(red: 0.00, green: 0.00, blue: 0.00)

    /// White (default) followed by five distinct colors that read well on black.
    static let palette: [CanvasColor] = [.white, .red, .orange, .yellow, .green, .blue]
}

/// One freehand stroke: a polyline drawn with a single color and width.
struct CanvasStroke: Equatable, Sendable {
    var points: [CGPoint]
    var color: CanvasColor
    var width: CGFloat
}

/// Rasterizes sketch strokes onto a solid black background and returns PNG data.
/// Drawing happens in point coordinates with a top-left origin (matching SwiftUI),
/// scaled up by `scale` for crispness.
enum CanvasImageRenderer {
    static func png(strokes: [CanvasStroke], size: CGSize, scale: CGFloat = 2) -> Data? {
        let pxW = Int((size.width * scale).rounded())
        let pxH = Int((size.height * scale).rounded())
        guard pxW > 0, pxH > 0,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        defer { NSGraphicsContext.restoreGraphicsState() }

        let cg = ctx.cgContext
        // Normalize to a known user space regardless of the bitmap context's base
        // CTM: identity == device pixels (origin bottom-left, y-up). Then flip to a
        // top-left origin in point units so stroke coordinates match SwiftUI.
        cg.concatenate(cg.ctm.inverted())
        cg.translateBy(x: 0, y: CGFloat(pxH))
        cg.scaleBy(x: scale, y: -scale)

        NSColor.black.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

        for stroke in strokes {
            guard !stroke.points.isEmpty else { continue }
            stroke.color.nsColor.set()
            if stroke.points.count == 1 {
                // A lone tap renders as a filled dot the width of the pen.
                let p = stroke.points[0]
                let r = max(stroke.width / 2, 0.5)
                NSBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)).fill()
                continue
            }
            let path = NSBezierPath()
            path.lineWidth = stroke.width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: stroke.points[0])
            for pt in stroke.points.dropFirst() { path.line(to: pt) }
            path.stroke()
        }

        return rep.representation(using: .png, properties: [:])
    }
}
