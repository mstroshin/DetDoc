import Testing
@testable import DetDocCore

@Test func resolveMarksExistingAndMissing() {
    let r = DocLinkResolver(candidates: ["guides/setup.md"])
    #expect(r.resolve("guides/setup.md") == .init(docsRelativePath: "guides/setup.md", docPath: "docs/guides/setup.md", exists: true))
    #expect(r.resolve("guides/missing.md") == .init(docsRelativePath: "guides/missing.md", docPath: "docs/guides/missing.md", exists: false))
}

@Test func resolveIgnoresExternal() {
    let r = DocLinkResolver(candidates: [])
    #expect(r.resolve("https://x.com") == nil)
    #expect(r.resolve("pic.png") == nil)
}
