import Foundation
import Testing
@testable import DetDocCore

@Test func headCommitReturnsCommitSha() async throws {
    let fx = try await GitFixture()
    try fx.write("README.md", "hi\n")
    try await fx.commitAll("init")
    let head = try await fx.repo.headCommit()
    #expect(head.count == 40)
}

@Test func statusPorcelainReportsDirtyFiles() async throws {
    let fx = try await GitFixture()
    try fx.write("README.md", "hi\n")
    try await fx.commitAll("init")
    try fx.write("docs/idea.md", "new\n")  // untracked
    let dirty = try await fx.repo.statusPorcelain()
    #expect(dirty.contains { $0.path == "docs/idea.md" && $0.status == "??" })
}

@Test func applyPatchAndChangedFilesRoundTrip() async throws {
    let fx = try await GitFixture()
    try fx.write("src/a.txt", "one\n")
    try await fx.commitAll("init")
    try fx.write("src/a.txt", "two\n")
    let patch = try await fx.repo.diffPaths(["src/a.txt"])
    #expect(try await fx.repo.changedFilesFromPatch(patch) == ["src/a.txt"])
    // revert working tree, then re-apply the patch
    _ = try await fx.repo.git(["checkout", "--", "src/a.txt"])
    try await fx.repo.applyPatch(patch)
    let restored = try String(contentsOf: fx.root.appendingPathComponent("src/a.txt"), encoding: .utf8)
    #expect(restored == "two\n")
}

@Test func fileSha256IsNilForMissingFile() async throws {
    let fx = try await GitFixture()
    #expect(fx.repo.fileSha256("nope.txt") == nil)
}

@Test func failingGitCommandThrowsCommandFailed() async throws {
    let fx = try await GitFixture()
    await #expect(throws: DetDocError.self) {
        _ = try await fx.repo.git(["rev-parse", "does-not-exist"])
    }
}
