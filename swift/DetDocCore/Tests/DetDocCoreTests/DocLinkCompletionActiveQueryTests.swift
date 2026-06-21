import Foundation
import Testing
@testable import DetDocCore

@Test func activeQueryAtWordBoundary() {
    let q = DocLinkCompletion.activeQuery(in: "see @gu", cursorUTF16Offset: 7)
    #expect(q == ActiveQuery(range: NSRange(location: 4, length: 3), query: "gu"))
}

@Test func activeQueryEmptyRightAfterAt() {
    let q = DocLinkCompletion.activeQuery(in: "@", cursorUTF16Offset: 1)
    #expect(q == ActiveQuery(range: NSRange(location: 0, length: 1), query: ""))
}

@Test func activeQueryRejectsEmailLikeAt() {
    #expect(DocLinkCompletion.activeQuery(in: "mail a@b", cursorUTF16Offset: 8) == nil)
}

@Test func activeQueryStopsAtWhitespace() {
    #expect(DocLinkCompletion.activeQuery(in: "@gu ide", cursorUTF16Offset: 7) == nil)
}

@Test func activeQueryAllowsPathChars() {
    let q = DocLinkCompletion.activeQuery(in: "@guides/se", cursorUTF16Offset: 10)
    #expect(q?.query == "guides/se")
}
