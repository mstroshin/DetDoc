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

@Test func scanFindsLinkWithTextAndDestination() {
    let source = "see [setup](guides/setup.md) now"
    let spans = MarkdownStyleScanner.scan(source)
    let link = spans.first { if case .link = $0.kind { return true } else { return false } }
    #expect(link?.range == NSRange(location: 4, length: 24))   // "[setup](guides/setup.md)"
    if case let .link(dest, textRange)? = link?.kind {
        #expect(dest == "guides/setup.md")
        #expect((source as NSString).substring(with: textRange) == "setup")
    } else { Issue.record("expected a link span") }
}

@Test func scanIgnoresImagesAsLinks() {
    let spans = MarkdownStyleScanner.scan("![alt](x.png)")
    #expect(!spans.contains { if case .link = $0.kind { return true } else { return false } })
}
