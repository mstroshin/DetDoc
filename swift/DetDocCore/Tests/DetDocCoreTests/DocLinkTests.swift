import Testing
@testable import DetDocCore

@Test func makeBuildsAtToken() {
    #expect(DocLink.make(docsRelativePath: "guides/setup.md") == "@guides/setup")
}

@Test func makeWithoutExtensionIsIdempotent() {
    #expect(DocLink.make(docsRelativePath: "guides/setup") == "@guides/setup")
}
