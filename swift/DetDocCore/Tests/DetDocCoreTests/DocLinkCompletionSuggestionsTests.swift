import Testing
@testable import DetDocCore

private let cands = [
    DocCandidate(name: "setup", docsRelativePath: "guides/setup.md", title: "Setup Guide"),
    DocCandidate(name: "glossary", docsRelativePath: "guides/glossary.md", title: "Glossary"),
    DocCandidate(name: "arch", docsRelativePath: "arch.md", title: "Guidelines"),
]

@Test func suggestionsEmptyQueryReturnsAll() {
    #expect(DocLinkCompletion.suggestions(query: "", candidates: cands).count == 3)
}

@Test func suggestionsPrefixRanksFirst() {
    let r = DocLinkCompletion.suggestions(query: "gu", candidates: cands)
    #expect(r.map(\.docsRelativePath) == ["guides/glossary.md", "guides/setup.md", "arch.md"])
}

@Test func suggestionsTitleOnlyMatchIncluded() {
    let r = DocLinkCompletion.suggestions(query: "guidel", candidates: cands)
    #expect(r.map(\.docsRelativePath) == ["arch.md"])
}
