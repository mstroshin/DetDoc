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
    #expect(r.first?.docsRelativePath == "guides/glossary.md" || r.first?.docsRelativePath == "guides/setup.md")
    #expect(r.allSatisfy { $0.docsRelativePath.lowercased().contains("gu") || ($0.title ?? "").lowercased().contains("gu") })
}

@Test func suggestionsTitleOnlyMatchIncluded() {
    let r = DocLinkCompletion.suggestions(query: "guidel", candidates: cands)
    #expect(r.map(\.docsRelativePath) == ["arch.md"])
}
