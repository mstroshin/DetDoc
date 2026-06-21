import Foundation
import AppKit
import Testing
@testable import DetDoc

@MainActor
struct CanvasImageRendererTests {

    /// Decodes `data` and samples one pixel in sRGB. The center pixel and the
    /// corners are orientation-invariant, so tests sample only those to stay
    /// independent of the bitmap's y-origin convention.
    private func pixel(_ data: Data, x: Int, y: Int) throws -> (r: Double, g: Double, b: Double) {
        let rep = try #require(NSBitmapImageRep(data: data))
        let c = try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
    }

    @Test func emptyCanvasIsBlackAtExpectedPixelSize() throws {
        let size = CGSize(width: 100, height: 80)
        let data = try #require(CanvasImageRenderer.png(strokes: [], size: size, scale: 2))
        let rep = try #require(NSBitmapImageRep(data: data))
        #expect(rep.pixelsWide == 200)
        #expect(rep.pixelsHigh == 160)
        let center = try pixel(data, x: 100, y: 80)
        #expect(center.r < 0.2 && center.g < 0.2 && center.b < 0.2)
    }

    @Test func whiteStrokeRendersWhiteOnBlack() throws {
        let size = CGSize(width: 100, height: 80)
        let stroke = CanvasStroke(
            points: [CGPoint(x: 0, y: 40), CGPoint(x: 100, y: 40)],
            color: .white, width: 16)
        let data = try #require(CanvasImageRenderer.png(strokes: [stroke], size: size, scale: 2))
        let center = try pixel(data, x: 100, y: 80)          // on the stroke
        #expect(center.r > 0.8 && center.g > 0.8 && center.b > 0.8)
        let corner = try pixel(data, x: 3, y: 3)             // background
        #expect(corner.r < 0.2 && corner.g < 0.2 && corner.b < 0.2)
    }

    @Test func eraserStrokeClearsEarlierStrokeBackToBlack() throws {
        let size = CGSize(width: 100, height: 80)
        let pen = CanvasStroke(points: [CGPoint(x: 0, y: 40), CGPoint(x: 100, y: 40)],
                               color: .white, width: 16)
        let eraser = CanvasStroke(points: [CGPoint(x: 0, y: 40), CGPoint(x: 100, y: 40)],
                                  color: .black, width: 24)
        let data = try #require(CanvasImageRenderer.png(strokes: [pen, eraser], size: size, scale: 2))
        let center = try pixel(data, x: 100, y: 80)   // erased back to black
        #expect(center.r < 0.2 && center.g < 0.2 && center.b < 0.2)
    }

    @Test func strokeUsesItsOwnColor() throws {
        let size = CGSize(width: 100, height: 80)
        let stroke = CanvasStroke(
            points: [CGPoint(x: 0, y: 40), CGPoint(x: 100, y: 40)],
            color: .red, width: 16)
        let data = try #require(CanvasImageRenderer.png(strokes: [stroke], size: size, scale: 2))
        let center = try pixel(data, x: 100, y: 80)
        #expect(center.r > 0.5)
        #expect(center.r > center.g + 0.2)
        #expect(center.r > center.b + 0.2)
    }
}
