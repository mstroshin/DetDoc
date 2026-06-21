import Foundation
import AppKit
import Testing
@testable import DetDoc
@testable import DetDocCore

/// End-to-end of the data path behind the canvas feature: a sketch is rendered to
/// PNG, imported into the doc's `assets/`, and resolves back as a doc image token —
/// exactly the steps `Coordinator.finishCanvas` performs. The AppKit menu/sheet glue
/// is thin and verified by running the app.
@MainActor
@Test func sketchRendersImportsAndResolvesAsDocImage() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    let importer = DocImageImporter(root: fx.root)

    let stroke = CanvasStroke(
        points: [CGPoint(x: 0, y: 20), CGPoint(x: 80, y: 20)],
        color: .white, width: 8)
    let png = try #require(CanvasImageRenderer.png(strokes: [stroke],
                                                   size: CGSize(width: 80, height: 40), scale: 2))

    let token = try importer.importData(png, basename: "sketch-test", forDoc: "docs/idea.md")
    #expect(token == "assets/sketch-test.png")

    // The token resolves to an on-disk file that is a valid PNG of the scaled size.
    let url = try #require(importer.resolve(token))
    let rep = try #require(NSBitmapImageRep(data: Data(contentsOf: url)))
    #expect(rep.pixelsWide == 160)
    #expect(rep.pixelsHigh == 80)

    // And the scanner that drives inline rendering recognizes it as an image.
    #expect(ImageRefScanner.isImagePath(token))
}
