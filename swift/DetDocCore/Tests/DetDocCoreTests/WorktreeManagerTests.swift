import Foundation
import Testing
@testable import DetDocCore

@Test func createAndCleanupWorktree() async throws {
    let fx = try await GitFixture()
    try fx.write("README.md", "hi\n")
    try await fx.commitAll("init")

    let handle = try await WorktreeManager().createFromHead(fx.repo, runId: "20260620T101112Z-run-1a2b3c4d")
    #expect(FileManager.default.fileExists(atPath: handle.path.appendingPathComponent("README.md").path))

    try await WorktreeManager().cleanup(fx.repo, handle)
    #expect(!FileManager.default.fileExists(atPath: handle.path.path))
    let branches = try await fx.repo.git(["branch", "--list", handle.branchName])
    #expect(branches.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}
