import Foundation
import Testing
@testable import DetDocCore

@Test func createRunWritesManifestThatReadsBack() throws {
    let tmp = TempDir()
    let store = ArtifactStore(projectRoot: tmp.url)
    let manifest = RunManifest(runId: "20260620T101112Z-run-1a2b3c4d", mode: .run, baseCommit: "abc123", approvedTargets: ["src/a.ts"])

    try store.createRun(manifest)

    let manifestURL = store.runDir(manifest.runId).appendingPathComponent("manifest.json")
    #expect(FileManager.default.fileExists(atPath: manifestURL.path))
    let raw = try String(contentsOf: manifestURL, encoding: .utf8)
    #expect(raw.hasSuffix("\n"))  // pretty JSON + trailing newline

    let readBack: RunManifest = try store.readJSON(RunManifest.self, manifest.runId, "manifest.json")
    #expect(readBack == manifest)
}

@Test func writeAndReadTextRoundTrips() throws {
    let tmp = TempDir()
    let store = ArtifactStore(projectRoot: tmp.url)
    let manifest = RunManifest(runId: "r1", mode: .fix, baseCommit: "h")
    try store.createRun(manifest)
    try store.writeText("r1", "changes.patch", "diff --git a/x b/x\n")
    #expect(try store.readText("r1", "changes.patch") == "diff --git a/x b/x\n")
}

@Test func deleteRunRemovesDirectory() throws {
    let tmp = TempDir()
    let store = ArtifactStore(projectRoot: tmp.url)
    try store.createRun(RunManifest(runId: "r2", mode: .run, baseCommit: "h"))
    try store.deleteRun("r2")
    #expect(!FileManager.default.fileExists(atPath: store.runDir("r2").path))
}
