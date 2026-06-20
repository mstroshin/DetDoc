import Foundation
import Testing
@testable import DetDocViewModels
@testable import DetDocCore

@MainActor
@Test func applyReportsBaseMismatchError() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    let store = ArtifactStore(projectRoot: fx.root)
    var manifest = RunManifest.initial(mode: .run, baseCommit: "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef")  // wrong base
    manifest.approvedTargets = ["src/a.swift"]
    try store.createRun(manifest)
    try store.writeText(manifest.runId, "changes.patch", "patch\n")

    let vm = RunsViewModel(root: fx.root)
    vm.refresh()
    #expect(vm.runs.contains { $0.runId == manifest.runId })
    await vm.apply(manifest.runId)
    #expect(vm.error?.code == "APPLY_BASE_MISMATCH")
}
