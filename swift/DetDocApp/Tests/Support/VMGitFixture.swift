import Foundation
@testable import DetDocCore

final class VMGitFixture {
    let root: URL
    let repo: GitRepository
    init() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("detdoc-vm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        repo = GitRepository(root)
        _ = try await repo.git(["init", "-q", "-b", "main"])
        _ = try await repo.git(["config", "user.email", "t@detdoc.local"])
        _ = try await repo.git(["config", "user.name", "DetDoc Test"])
        _ = try await repo.git(["config", "commit.gpgsign", "false"])
    }
    func write(_ path: String, _ contents: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
    func commitAll(_ message: String) async throws {
        _ = try await repo.git(["add", "-A", "--", "."])
        _ = try await repo.git(["commit", "-q", "-m", message])
    }
    func detdocInit() async throws {
        try ConfigStore().initFiles(root: root)
        try await commitAll("detdoc init")
    }
    deinit { try? FileManager.default.removeItem(at: root) }
}
