import Foundation
import Testing
@testable import DetDoc
@testable import DetDocCore

@MainActor
@Test func refreshLoadsStatusDocsAndRuns() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    try fx.write("docs/extra.md", "# Extra\n")

    // seed a saved run
    let store = ArtifactStore(projectRoot: fx.root)
    var manifest = RunManifest.initial(mode: .run, baseCommit: try await fx.repo.headCommit())
    manifest.approvedTargets = ["src/a.swift"]
    try store.createRun(manifest)
    try store.writeText(manifest.runId, "changes.patch", "patch\n")

    let vm = WorkspaceViewModel(root: fx.root)
    await vm.refresh()

    #expect(vm.status?.initialized == true)
    #expect(vm.docs.contains { $0.path == "docs/extra.md" })
    #expect(vm.runs.contains { $0.runId == manifest.runId && $0.hasPatch })
}

@MainActor
@Test func refreshReportsUninitializedWithoutConfig() async throws {
    let fx = try await VMGitFixture()
    let vm = WorkspaceViewModel(root: fx.root)
    await vm.refresh()
    #expect(vm.status?.initialized == false)
    #expect(vm.docs.isEmpty)
}
