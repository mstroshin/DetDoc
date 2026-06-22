import Foundation
import Testing
@testable import DetDocCore

@Test func serializeLineFormatsHeadingAndRefs() {
    let link = CodeLink(docPath: "docs/spec.md", heading: "## Plan approval",
                        refs: ["AppCoordinator.swift#approvePlan", "PlanGateView.swift#PlanGateView"])
    #expect(CodeLinkBlock.serializeLine(link)
        == "<!-- detdoc:link \"## Plan approval\" AppCoordinator.swift#approvePlan PlanGateView.swift#PlanGateView -->")
}

@Test func isLinkLineDetectsOurComments() {
    #expect(CodeLinkBlock.isLinkLine("  <!-- detdoc:link \"## H\" a.swift#x -->  "))
    #expect(!CodeLinkBlock.isLinkLine("## H"))
    #expect(!CodeLinkBlock.isLinkLine("<!-- a normal comment -->"))
}

@Test func applyAppendsBlockAtEndAndLeavesProseUntouched() {
    let md = "# Title\n\nSome prose.\n"
    let out = CodeLinkBlock.apply(to: md, links: [
        CodeLink(docPath: "d.md", heading: "## A", refs: ["a.swift#x"]),
    ])
    #expect(out == "# Title\n\nSome prose.\n\n<!-- detdoc:link \"## A\" a.swift#x -->\n")
}

@Test func applyIsIdempotent() {
    let md = "# Title\n\nSome prose.\n"
    let links = [CodeLink(docPath: "d.md", heading: "## A", refs: ["a.swift#x"])]
    let once = CodeLinkBlock.apply(to: md, links: links)
    let twice = CodeLinkBlock.apply(to: once, links: links)
    #expect(once == twice)
}

@Test func applyWithEmptyLinksStripsExistingBlock() {
    let md = "# Title\n\nSome prose.\n\n<!-- detdoc:link \"## A\" a.swift#x -->\n"
    #expect(CodeLinkBlock.apply(to: md, links: []) == "# Title\n\nSome prose.\n")
}

@Test func scanFindsCommentRange() {
    let para = "<!-- detdoc:link \"## A\" a.swift#x -->"
    let ranges = CodeLinkScanner.scan(para)
    #expect(ranges == [NSRange(location: 0, length: (para as NSString).length)])
}

@Test func scanIgnoresPlainText() {
    #expect(CodeLinkScanner.scan("just prose").isEmpty)
}
