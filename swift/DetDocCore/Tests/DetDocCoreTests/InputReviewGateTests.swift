import Foundation
import Testing
@testable import DetDocCore

private func detdocRepo() async throws -> GitFixture {
    let fx = try await GitFixture()
    try ConfigStore().initFiles(root: fx.root)
    try await fx.commitAll("detdoc init")
    return fx
}

@Test func runFlowEmitsInputReadyBeforePlanReady() async throws {
    let fx = try await detdocRepo()
    try fx.write("docs/idea.md", "changed\n")
    let engine = DetDocEngine(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "let v = 9\n"))
    var phases: [String] = []
    let stream = await engine.start(mode: .run)
    for try await event in stream {
        switch event {
        case .inputReady: phases.append("input"); await engine.submitInputDecision(.confirm)
        case .planReady: phases.append("plan"); await engine.submitPlanDecision(.approve)
        case .patchReady: phases.append("patch"); await engine.submitApplyDecision(.apply)
        default: break
        }
    }
    #expect(phases == ["input", "plan", "patch"])
}

@Test func runFlowCancelAtInputGateCreatesNoRun() async throws {
    let fx = try await detdocRepo()
    try fx.write("docs/idea.md", "changed\n")
    let engine = DetDocEngine(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "x\n"))
    await #expect {
        let stream = await engine.start(mode: .run)
        for try await event in stream {
            if case .inputReady = event { await engine.submitInputDecision(.cancel) }
        }
    } throws: { ($0 as? DetDocError)?.code == "RUN_CANCELLED_BY_USER" }
    // Gate precedes createRun: no run artifacts exist.
    let runsDir = fx.root.appendingPathComponent(".detdoc/runs")
    let entries = (try? FileManager.default.contentsOfDirectory(atPath: runsDir.path)) ?? []
    #expect(entries.filter { $0 != ".gitkeep" }.isEmpty)
}

@Test func fixFlowEmitsNoInputReady() async throws {
    let fx = try await detdocRepo()
    let engine = DetDocEngine(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "x\n"))
    var sawInput = false
    let stream = await engine.start(mode: .fix, message: "fix the bug")
    for try await event in stream {
        switch event {
        case .inputReady: sawInput = true
        case .planReady: await engine.submitPlanDecision(.approve)
        case .patchReady: await engine.submitApplyDecision(.apply)
        default: break
        }
    }
    #expect(!sawInput)
}
