import Testing
@testable import DetDocCore

@Test func makeBuildsMarkdownLink() {
    #expect(DocLink.make(name: "setup", docsRelativePath: "guides/setup.md") == "[setup](guides/setup.md)")
}

@Test func internalTargetAcceptsRelativeMd() {
    #expect(DocLink.internalTarget(ofDestination: "guides/setup.md") == "guides/setup.md")
    #expect(DocLink.internalTarget(ofDestination: "./a.md") == "a.md")
    #expect(DocLink.internalTarget(ofDestination: "a.md#section") == "a.md")
}

@Test func internalTargetRejectsExternalAndNonMd() {
    #expect(DocLink.internalTarget(ofDestination: "https://x.com/a.md") == nil)
    #expect(DocLink.internalTarget(ofDestination: "mailto:a@b.com") == nil)
    #expect(DocLink.internalTarget(ofDestination: "#anchor") == nil)
    #expect(DocLink.internalTarget(ofDestination: "image.png") == nil)
}
