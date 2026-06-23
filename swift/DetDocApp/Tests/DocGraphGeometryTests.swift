import Foundation
import Testing
@testable import DetDoc

@MainActor
@Test func borderPointHitsRectEdgeAlongRay() {
    let c = CGPoint(x: 0, y: 0)
    let wide = CGSize(width: 100, height: 40)   // half-extents 50 × 20

    // Straight right / down land on the mid-edges.
    #expect(DocGraphView.borderPoint(center: c, size: wide, toward: CGPoint(x: 1000, y: 0)) == CGPoint(x: 50, y: 0))
    #expect(DocGraphView.borderPoint(center: c, size: wide, toward: CGPoint(x: 0, y: 1000)) == CGPoint(x: 0, y: 20))
    #expect(DocGraphView.borderPoint(center: c, size: wide, toward: CGPoint(x: -1000, y: 0)) == CGPoint(x: -50, y: 0))

    // A 45° ray on a square exits at the corner.
    let square = CGSize(width: 40, height: 40)   // half-extents 20 × 20
    #expect(DocGraphView.borderPoint(center: c, size: square, toward: CGPoint(x: 100, y: 100)) == CGPoint(x: 20, y: 20))

    // Coincident centre is degenerate → returns the centre, no NaN.
    #expect(DocGraphView.borderPoint(center: c, size: wide, toward: c) == c)
}
