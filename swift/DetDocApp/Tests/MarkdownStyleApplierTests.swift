import Foundation
import Testing
@testable import DetDoc
@testable import DetDocCore

@Test func styledLinkRangesExcludesCaretTouchingLink() {
    let link = MarkdownSpan(range: NSRange(location: 4, length: 24),
                            kind: .link(destination: "guides/setup.md", textRange: NSRange(location: 5, length: 5)))
    // caret outside the link -> styled
    #expect(MarkdownStyleApplier.styledLinkRanges(spans: [link], caret: NSRange(location: 0, length: 0)) == [link])
    // caret inside the link -> not styled (raw)
    #expect(MarkdownStyleApplier.styledLinkRanges(spans: [link], caret: NSRange(location: 10, length: 0)).isEmpty)
}
