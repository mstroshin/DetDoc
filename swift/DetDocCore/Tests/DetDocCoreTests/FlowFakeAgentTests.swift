import Foundation
import Testing
@testable import DetDocCore

/// Drive the engine to completion, auto-answering both gates.
private func drive(_ engine: DetDocEngine, mode: RunMode, message: String? = nil,
                   plan: PlanDecision, apply: ApplyDecision) async throws -> RunFlowResult? {
    let stream = await engine.start(mode: mode, message: message)
    var result: RunFlowResult?
    for try await event in stream {
        switch event {
        case .planReady: await engine.submitPlanDecision(plan)
        case .patchReady: await engine.submitApplyDecision(apply)
        case .complete(let r): result = r
        default: break
        }
    }
    return result
}

private func detdocRepo() async throws -> GitFixture {
    let fx = try await GitFixture()
    try ConfigStore().initFiles(root: fx.root)
    try await fx.commitAll("detdoc init")
    return fx
}

@Test func runFlowAppliesAndCommitsWithFakeAgent() async throws {
    let fx = try await detdocRepo()
    try fx.write("docs/idea.md", "changed idea\n")   // dirty doc drives the run
    let engine = DetDocEngine(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "let v = 2\n"))
    let result = try await drive(engine, mode: .run, plan: .approve, apply: .apply)
    #expect(result?.applied == true)
    #expect(FileManager.default.fileExists(atPath: fx.root.appendingPathComponent("src/app.swift").path))
    let log = try await fx.repo.git(["log", "--oneline", "-1"])
    #expect(log.contains("DetDoc apply"))
}

@Test func runFlowStopsWhenApplyDiscarded() async throws {
    let fx = try await detdocRepo()
    try fx.write("docs/idea.md", "changed\n")
    let engine = DetDocEngine(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "let v = 3\n"))
    let result = try await drive(engine, mode: .run, plan: .approve, apply: .discard)
    #expect(result?.applied == false)
    // patch saved, not applied to main
    #expect(!FileManager.default.fileExists(atPath: fx.root.appendingPathComponent("src/app.swift").path))
}

@Test func runFlowRejectsWhenPlanRejected() async throws {
    let fx = try await detdocRepo()
    try fx.write("docs/idea.md", "changed\n")
    let engine = DetDocEngine(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "x\n"))
    await #expect { _ = try await drive(engine, mode: .run, plan: .reject, apply: .apply) }
        throws: { ($0 as? DetDocError)?.code == "PLAN_NOT_APPROVED" }
}

@Test func fixFlowRequiresNonEmptyMessage() async throws {
    let fx = try await detdocRepo()
    let engine = DetDocEngine(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "x\n"))
    await #expect { _ = try await drive(engine, mode: .fix, message: "   ", plan: .approve, apply: .apply) }
        throws: { ($0 as? DetDocError)?.code == "EMPTY_FIX_MESSAGE" }
}
