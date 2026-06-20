import Foundation
import Testing
@testable import DetDocCore

@Test func manifestDecodesLegacyWithoutOptionalFields() throws {
    let json = """
    { "runId": "20260620T101112Z-run-1a2b3c4d", "mode": "run", "baseCommit": "abc123" }
    """
    let manifest = try JSONDecoder().decode(RunManifest.self, from: Data(json.utf8))
    #expect(manifest.approvedTargets == [])
    #expect(manifest.touchedFiles == [])
}

@Test func manifestRoundTripsWithTouchedFiles() throws {
    var manifest = RunManifest.initial(mode: .fix, baseCommit: "c0ffee")
    manifest.approvedTargets = ["src/a.swift"]
    manifest.touchedFiles = [TouchedFile(path: "src/a.swift", before: "h1", after: "h2")]
    let data = try JSONEncoder().encode(manifest)
    let decoded = try JSONDecoder().decode(RunManifest.self, from: data)
    #expect(decoded == manifest)
}

@Test func manifestInitialHasFreshRunIdAndEmptyCollections() {
    let manifest = RunManifest.initial(mode: .run, baseCommit: "base")
    #expect(manifest.mode == .run)
    #expect(manifest.baseCommit == "base")
    #expect(manifest.approvedTargets.isEmpty)
    #expect(manifest.touchedFiles.isEmpty)
    #expect(manifest.runId.range(of: #"^\d{8}T\d{6}Z-run-[0-9a-f]{8}$"#, options: .regularExpression) != nil)
}
