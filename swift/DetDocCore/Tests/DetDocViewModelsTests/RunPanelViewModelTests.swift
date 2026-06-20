import Foundation
import Testing
@testable import DetDocViewModels
@testable import DetDocCore

@MainActor
@Test func runPanelDrivesRunToCompletion() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    try fx.write("docs/idea.md", "changed idea\n")  // dirty doc drives the run

    let vm = RunPanelViewModel(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "let v = 2\n"))
    vm.start(mode: .run)

    await poll { await vm.stage == .planPending }
    #expect(vm.planReview?.summary == "Fake plan")
    vm.approvePlan()

    await poll { await vm.stage == .patchPending }
    #expect(vm.patchReview?.changedFiles.contains("src/app.swift") == true)
    vm.applyPatch()

    await poll { await vm.stage == .completed }
    #expect(vm.result?.applied == true)
    #expect(FileManager.default.fileExists(atPath: fx.root.appendingPathComponent("src/app.swift").path))
}

@MainActor
@Test func runPanelSurfacesPlanRejection() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    try fx.write("docs/idea.md", "changed\n")
    let vm = RunPanelViewModel(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "x\n"))
    vm.start(mode: .run)
    await poll { await vm.stage == .planPending }
    vm.rejectPlan()
    await poll { await vm.stage == .failed }
    #expect(vm.error?.code == "PLAN_NOT_APPROVED")
}

@MainActor
@Test func runPanelCancelEndsInFailedStateWithStableCode() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    try fx.write("docs/idea.md", "changed\n")
    let vm = RunPanelViewModel(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "x\n"))
    vm.start(mode: .run)
    await poll { await vm.stage == .planPending }
    vm.cancel()
    await poll { await vm.stage == .failed }
    #expect(vm.error?.code == "ENGINE_CANCELLED")
}
