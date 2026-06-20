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
        try await commitOrStage(repo: repo, approvedTargets: manifest.approvedTargets, runId: runId, autoCommit: autoCommit, store: store)
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

    func commitOrStage(repo: GitRepository, approvedTargets: [String], runId: String, autoCommit: Bool, store: ArtifactStore) async throws {
        try GitignoreManager.ensureManagedEntries(root: repo.cwd)
        _ = try await repo.git(["add", "--"] + approvedTargets)
        if autoCommit {
            _ = try await repo.git(["commit", "-m", "DetDoc apply \(runId)"])
            try store.deleteRun(runId)
        }
    }
}
