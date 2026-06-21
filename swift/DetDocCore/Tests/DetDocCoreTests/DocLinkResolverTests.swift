import Testing
@testable import DetDocCore

@Test func resolveMarksExistingAndMissing() {
    let r = DocLinkResolver(candidates: ["guides/setup.md"])
    #expect(r.resolve("guides/setup") == .init(docsRelativePath: "guides/setup.md", docPath: "docs/guides/setup.md", exists: true))
    #expect(r.resolve("guides/missing") == .init(docsRelativePath: "guides/missing.md", docPath: "docs/guides/missing.md", exists: false))
}

@Test func resolveEmptyPathReturnsNil() {
    let r = DocLinkResolver(candidates: [])
    #expect(r.resolve("") == nil)
}

@Test func resolveLeadingSlashIsNormalized() {
    let r = DocLinkResolver(candidates: ["guides/setup.md"])
    #expect(r.resolve("/guides/setup") == .init(docsRelativePath: "guides/setup.md", docPath: "docs/guides/setup.md", exists: true))
}
