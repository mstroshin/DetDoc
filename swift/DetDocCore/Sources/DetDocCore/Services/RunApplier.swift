import Foundation

public struct RunApplier: Sendable {
    public init() {}

    public func apply(root: URL, runId: String, autoCommit: Bool) async throws -> RunFlowResult {
        let store = ArtifactStore(projectRoot: root)
        let manifest: RunManifest = try store.readJSON(RunManifest.self, runId, "manifest.json")
        let patch = try store.readText(runId, "changes.patch")
        let repo = GitRepository(root)

        let head = try await repo.headCommit()
        if head != manifest.baseCommit {
            throw DetDocError("APPLY_BASE_MISMATCH", "HEAD (\(head)) does not match the saved run base commit (\(manifest.baseCommit))")
        }
        for file in manifest.touchedFiles where repo.fileSha256(file.path) != file.before {
            throw DetDocError("APPLY_PREIMAGE_MISMATCH", "preimage hash mismatch for \(file.path)")
        }

        try await repo.applyPatch(patch)
        try await runPostApplyValidation(root: root, store: store, runId: runId)
        try await commitOrStage(repo: repo, runId: runId, autoCommit: autoCommit, store: store)
        return RunFlowResult(runId: runId, applied: true, patch: patch)
    }

    func runPostApplyValidation(root: URL, store: ArtifactStore, runId: String) async throws {
        let config: DetDocConfig
        do {
            config = try ConfigStore().load(root: root)
        } catch let err as DetDocError where err.code == "CONFIG_READ_FAILED" {
            return  // no config — skip post-apply validation
        }
        guard !config.validation.commands.isEmpty else { return }
        let log = try await ValidationRunner().run(commands: config.validation.commands, cwd: root)
        try store.writeText(runId, "post-apply-validation.log", log)
    }

    func commitOrStage(repo: GitRepository, runId: String, autoCommit: Bool, store: ArtifactStore) async throws {
        try GitignoreManager.ensureManagedEntries(root: repo.cwd)
        // Stage the whole tree so the commit captures the managed `.gitignore` and any files
        // touched by post-apply validation, not just the approved targets.
        _ = try await repo.git(["add", "-A", "--", "."])
        if autoCommit {
            _ = try await repo.git(["commit", "-m", "DetDoc apply \(runId)"])
            let dirty = try await repo.statusPorcelain()
            if !dirty.isEmpty {
                let detail = dirty.map { "\($0.status) \($0.path)" }.joined(separator: ", ")
                throw DetDocError("GIT_NOT_CLEAN_AFTER_APPLY", "Git working tree is not clean after DetDoc apply: \(detail)")
            }
            try store.deleteRun(runId)
        }
    }
}
