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

@Test func activeQueryNilWhenCursorBeforeAt() {
    #expect(DocLinkCompletion.activeQuery(in: "@gu", cursorUTF16Offset: 0) == nil)
}

@Test func activeQueryHandlesCyrillicBeforeAt() {
    // "слово @s" — '@' preceded by a space after a Cyrillic word still triggers
    let src = "слово @s"
    let q = DocLinkCompletion.activeQuery(in: src, cursorUTF16Offset: (src as NSString).length)
    #expect(q?.query == "s")
}

@Test func activeQueryRangeSpansWholeTokenWhenCaretMidToken() {
    // "@guides/setup", caret after "@gui" (offset 4)
    let q = DocLinkCompletion.activeQuery(in: "@guides/setup", cursorUTF16Offset: 4)
    #expect(q?.query == "gui")
    #expect(q?.range == NSRange(location: 0, length: 13))   // whole "@guides/setup"
}
