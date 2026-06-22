import Foundation
import Testing
@testable import DetDocCore

@Test func parsesFencedBlockWithDocHeadingAndRefs() {
    let text = """
    Done implementing.

    ```detdoc-links
    docs/spec.md ## Plan approval -> AppCoordinator.swift#approvePlan, PlanGateView.swift#PlanGateView
    docs/spec.md ## Patch gate -> AppCoordinator.swift#approveApply
    ```
    """
    let links = PiCodeLinkParsing.parseCodeLinks(fromAssistantText: text)
    #expect(links == [
        CodeLink(docPath: "docs/spec.md", heading: "## Plan approval",
                 refs: ["AppCoordinator.swift#approvePlan", "PlanGateView.swift#PlanGateView"]),
        CodeLink(docPath: "docs/spec.md", heading: "## Patch gate",
                 refs: ["AppCoordinator.swift#approveApply"]),
    ])
}

@Test func returnsEmptyWhenNoBlock() {
    #expect(PiCodeLinkParsing.parseCodeLinks(fromAssistantText: "no links here").isEmpty)
}

@Test func skipsMalformedLines() {
    let text = """
    ```detdoc-links
    garbage with no arrow
    docs/a.md ## H -> a.swift#x
    docs/b.md ## H ->
    ```
    """
    #expect(PiCodeLinkParsing.parseCodeLinks(fromAssistantText: text)
        == [CodeLink(docPath: "docs/a.md", heading: "## H", refs: ["a.swift#x"])])
}

@Test func agentRunResultDefaultsToNoCodeLinks() {
    #expect(AgentRunResult().codeLinks.isEmpty)
}
