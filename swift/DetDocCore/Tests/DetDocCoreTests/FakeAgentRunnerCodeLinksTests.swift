import Foundation
import Testing
@testable import DetDocCore

@Test func fakeAgentReturnsConfiguredCodeLinks() async throws {
    let links = [CodeLink(docPath: "docs/idea.md", heading: "## A", refs: ["src/app.swift#run"])]
    let fake = FakeAgentRunner(target: "src/app.swift", content: "x\n", codeLinks: links)
    let req = ImplementRequest(mode: .run, input: "i", config: .default,
                               cwd: FileManager.default.temporaryDirectory,
                               approvedPlan: ProposedPlan(summary: "s",
                                   changes: [PlanChange(reason: "doc-diff:docs/idea.md:L1", targetFiles: ["src/app.swift"], kind: "modify", rationale: "r")],
                                   risk: "low"),
                               approvedTargets: ["src/app.swift"], progress: nil)
    let result = try await fake.implement(req)
    #expect(result.codeLinks == links)
}
