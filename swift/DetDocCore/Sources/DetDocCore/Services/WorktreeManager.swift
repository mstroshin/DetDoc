import Foundation

public struct WorktreeHandle: Sendable {
    public let path: URL
    public let branchName: String
    public var repo: GitRepository { GitRepository(path) }
    public init(path: URL, branchName: String) {
        self.path = path; self.branchName = branchName
    }
}

public struct WorktreeManager: Sendable {
    public init() {}

    public func createFromHead(_ repo: GitRepository, runId: String) async throws -> WorktreeHandle {
        let worktreesDir = repo.cwd.appendingPathComponent(".worktrees")
        do {
            try FileManager.default.createDirectory(at: worktreesDir, withIntermediateDirectories: true)
        } catch {
            throw DetDocError("WORKTREE_DIR_FAILED", "\(error)")
        }
        let path = worktreesDir.appendingPathComponent(runId)
        let base = try await repo.headCommit()
        _ = try await repo.git(["worktree", "add", "-b", runId, path.path, base])
        return WorktreeHandle(path: path, branchName: runId)
    }

    public func cleanup(_ repo: GitRepository, _ handle: WorktreeHandle) async throws {
        if FileManager.default.fileExists(atPath: handle.path.path) {
            _ = try await repo.git(["worktree", "remove", "--force", handle.path.path])
        }
        _ = try await repo.git(["branch", "-D", handle.branchName])
    }
}
