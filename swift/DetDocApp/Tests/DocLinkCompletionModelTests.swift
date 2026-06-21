import Foundation
import Testing
@testable import DetDoc
@testable import DetDocCore

private let cands = [
    DocCandidate(name: "setup", docsRelativePath: "guides/setup.md", title: nil),
    DocCandidate(name: "glossary", docsRelativePath: "guides/glossary.md", title: nil),
]

@MainActor @Test func beginPopulatesAndCommitsSelectedLink() {
    let m = DocLinkCompletionModel()
    m.begin(query: ActiveQuery(range: NSRange(location: 0, length: 3), query: "gu"), caretRect: .zero, candidates: cands)
    #expect(m.isActive)
    #expect(m.items.count == 2)
    m.moveDown()
    let ins = m.commit()
    #expect(ins == DocLinkCompletionModel.Insertion(text: "[setup](guides/setup.md)", range: NSRange(location: 0, length: 3)))
    #expect(m.isActive == false)
}

@MainActor @Test func moveDownWrapsAndCancelDeactivates() {
    let m = DocLinkCompletionModel()
    m.begin(query: ActiveQuery(range: NSRange(location: 0, length: 1), query: ""), caretRect: .zero, candidates: cands)
    m.moveDown(); m.moveDown()                 // 0 -> 1 -> wrap 0
    #expect(m.selectedIndex == 0)
    m.cancel()
    #expect(m.isActive == false)
    #expect(m.commit() == nil)
}
