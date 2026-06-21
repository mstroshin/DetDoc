import Foundation
import Testing
@testable import DetDocCore

@Test func scanFindsAtxHeadingLevel() {
    let spans = MarkdownStyleScanner.scan("## Title\n")
    #expect(spans.contains(MarkdownSpan(range: NSRange(location: 0, length: 8), kind: .heading(level: 2))))
}

@Test func scanFindsBoldAndItalic() {
    let spans = MarkdownStyleScanner.scan("a **b** c *d* e")
    #expect(spans.contains { $0.kind == .bold && ($0.range as NSRange).location == 2 && $0.range.length == 5 })
    #expect(spans.contains { $0.kind == .italic && $0.range.location == 10 && $0.range.length == 3 })
}
