import Foundation
import Testing
@testable import DetDocCore

@Test func moveLineDownToBottom() {
    // "A\n@x.png\nB\n" — move the image line to the boundary after B (index 11)
    let m = ParagraphMover.move(in: "A\n@x.png\nB\n", lineContaining: 2, toBoundary: 11)
    #expect(m?.text == "A\nB\n@x.png")
    #expect(m?.caret == 4)
}

@Test func moveLineUpToTop() {
    let m = ParagraphMover.move(in: "A\n@x.png\nB\n", lineContaining: 2, toBoundary: 0)
    #expect(m?.text == "@x.png\nA\nB\n")
    #expect(m?.caret == 0)
}

@Test func targetInsideSourceLineIsNoOp() {
    #expect(ParagraphMover.move(in: "A\n@x.png\nB\n", lineContaining: 2, toBoundary: 2) == nil)
    #expect(ParagraphMover.move(in: "A\n@x.png\nB\n", lineContaining: 2, toBoundary: 5) == nil)
}

@Test func targetAtNextBoundaryIsNoOp() {
    // index 9 is the start of "B\n" — the image is already immediately before it
    #expect(ParagraphMover.move(in: "A\n@x.png\nB\n", lineContaining: 2, toBoundary: 9) == nil)
}

@Test func lastLineWithoutNewlineMovesUp() {
    // image is the last line with no trailing newline
    let m = ParagraphMover.move(in: "L1\n@x.png", lineContaining: 3, toBoundary: 0)
    #expect(m?.text == "@x.png\nL1\n")
    #expect(m?.caret == 0)
}

@Test func emptyTextIsNoOp() {
    #expect(ParagraphMover.move(in: "", lineContaining: 0, toBoundary: 0) == nil)
}
