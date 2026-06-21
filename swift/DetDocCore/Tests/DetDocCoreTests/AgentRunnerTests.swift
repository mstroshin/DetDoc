import Foundation
import Testing
@testable import DetDocCore

@Test func fakeAgentPlanTargetsFileWithModeAppropriateReason() async throws {
    let agent = FakeAgentRunner(target: "src/app.swift", content: "let x = 2\n")
    let run = try await agent.plan(PlanRequest(mode: .run, input: "diff", config: .default, cwd: FileManager.default.temporaryDirectory))
    #expect(run.plan.changes.first?.targetFiles == ["src/app.swift"])
    #expect(run.plan.changes.first?.reason.hasPrefix("doc-diff:") == true)
    let fix = try await agent.plan(PlanRequest(mode: .fix, input: "msg", config: .default, cwd: FileManager.default.temporaryDirectory))
    #expect(fix.plan.changes.first?.reason == "intent:fix")
}

@Test func fakeAgentImplementWritesContent() async throws {
    let tmp = TempDir()
    let agent = FakeAgentRunner(target: "src/app.swift", content: "let x = 2\n")
    _ = try await agent.implement(ImplementRequest(mode: .run, input: "diff", config: .default, cwd: tmp.url, approvedPlan: ProposedPlan(summary: "s", changes: [], risk: "low"), approvedTargets: ["src/app.swift"], progress: nil))
    let written = try String(contentsOf: tmp.url.appendingPathComponent("src/app.swift"), encoding: .utf8)
    #expect(written == "let x = 2\n")
}

/// G2: the fake runner must refuse to write a target that is not in the approved set, so a
/// flow test can never accidentally simulate an out-of-scope edit (parity with the TS
/// FakeAgentRunner's unapproved-write guard).
@Test func fakeAgentRejectsUnapprovedWrite() async throws {
    let tmp = TempDir()
    let agent = FakeAgentRunner(target: "src/secret.swift", content: "x\n")
    await #expect {
        _ = try await agent.implement(ImplementRequest(
            mode: .run, input: "diff", config: .default, cwd: tmp.url,
            approvedPlan: ProposedPlan(summary: "s", changes: [], risk: "low"),
            approvedTargets: ["src/app.swift"], progress: nil))
    } throws: { ($0 as? DetDocError)?.code == "FAKE_UNAPPROVED_WRITE" }
}
