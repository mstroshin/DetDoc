import Foundation
import Testing
@testable import DetDocCore

@Test func collectReturnsPatchForNewTargetFile() async throws {
    let fx = try await GitFixture()
    try fx.write("README.md", "hi\n")
    try await fx.commitAll("init")
    try fx.write("src/new.swift", "let x = 1\n")  // untracked target
    let patch = try await PatchCollector.collect(fx.repo, approvedTargets: ["src/new.swift"])
    #expect(patch.contains("src/new.swift"))
    #expect(patch.hasSuffix("\n"))
}

@Test func collectRejectsEmptyTargets() async throws {
    let fx = try await GitFixture()
    await #expect { _ = try await PatchCollector.collect(fx.repo, approvedTargets: []) }
        throws: { ($0 as? DetDocError)?.code == "NO_APPROVED_TARGETS" }
}

@Test func collectRejectsEmptyPatch() async throws {
    let fx = try await GitFixture()
    try fx.write("src/x.swift", "same\n")
    try await fx.commitAll("init")  // target unchanged → empty diff
    await #expect { _ = try await PatchCollector.collect(fx.repo, approvedTargets: ["src/x.swift"]) }
        throws: { ($0 as? DetDocError)?.code == "EMPTY_PATCH" }
}
