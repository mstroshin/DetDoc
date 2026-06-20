import Foundation
import Testing
@testable import DetDocCore

@Test func manifestDecodesLegacyWithoutOptionalFields() throws {
    let json = """
    { "runId": "20260620T101112Z-run-1a2b3c4d", "mode": "run", "baseCommit": "abc123" }
    """
    let manifest = try JSONDecoder().decode(RunManifest.self, from: Data(json.utf8))
    #expect(manifest.runId == "20260620T101112Z-run-1a2b3c4d")
    #expect(manifest.mode == .run)
    #expect(manifest.baseCommit == "abc123")
    #expect(manifest.approvedTargets == [])
    #expect(manifest.preImageHashes == [:])
}

@Test func manifestRoundTripsWithTargets() throws {
    let manifest = RunManifest(runId: "20260620T101112Z-fix-deadbeef", mode: .fix, baseCommit: "c0ffee", approvedTargets: ["src/a.ts"])
    let data = try JSONEncoder().encode(manifest)
    let decoded = try JSONDecoder().decode(RunManifest.self, from: data)
    #expect(decoded == manifest)
}
