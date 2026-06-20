import Foundation
import Testing
@testable import DetDocCore

/// Build a saved run whose patch creates `src/new.swift`, with a correct base + preimage.
private func seedSavedRun(_ fx: GitFixture, autoCommitConfig: Bool = true) async throws -> String {
    try fx.write("README.md", "hi\n")
    try await fx.commitAll("init")
    let base = try await fx.repo.headCommit()
    // produce a patch that adds src/new.swift
    try fx.write("src/new.swift", "let x = 1\n")
    let patch = try await PatchCollector.collect(fx.repo, approvedTargets: ["src/new.swift"])
    _ = try await fx.repo.git(["checkout", "--", "."])  // revert working tree to clean base
    try? FileManager.default.removeItem(at: fx.root.appendingPathComponent("src/new.swift"))

    var manifest = RunManifest.initial(mode: .run, baseCommit: base)
    manifest.approvedTargets = ["src/new.swift"]
    manifest.touchedFiles = [TouchedFile(path: "src/new.swift", before: nil, after: "x")]  // before=nil: file absent at base
    let store = ArtifactStore(projectRoot: fx.root)
    try store.createRun(manifest)
    try store.writeText(manifest.runId, "changes.patch", patch)
    return manifest.runId
}

@Test func applySavedRunCommitsPatchAndRemovesArtifacts() async throws {
    let fx = try await GitFixture()
    let runId = try await seedSavedRun(fx)
    let result = try await RunApplier().apply(root: fx.root, runId: runId, autoCommit: true)
    #expect(result.applied)
    #expect(FileManager.default.fileExists(atPath: fx.root.appendingPathComponent("src/new.swift").path))
    let log = try await fx.repo.git(["log", "--oneline", "-1"])
    #expect(log.contains("DetDoc apply \(runId)"))
    #expect(!FileManager.default.fileExists(atPath: ArtifactStore(projectRoot: fx.root).runDir(runId).path))
}

@Test func applyRejectsMovedHead() async throws {
    let fx = try await GitFixture()
    let runId = try await seedSavedRun(fx)
    try fx.write("other.txt", "x\n"); try await fx.commitAll("move head")  // HEAD now != baseCommit
    await #expect { _ = try await RunApplier().apply(root: fx.root, runId: runId, autoCommit: true) }
        throws: { ($0 as? DetDocError)?.code == "APPLY_BASE_MISMATCH" }
}
