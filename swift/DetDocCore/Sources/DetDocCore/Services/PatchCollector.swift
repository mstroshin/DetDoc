public enum PatchCollector {
    public static func collect(_ repo: GitRepository, approvedTargets: [String]) async throws -> String {
        if approvedTargets.isEmpty {
            throw DetDocError("NO_APPROVED_TARGETS", "Approved plan contains no target files.")
        }
        _ = try? await repo.git(["add", "-N", "--"] + approvedTargets)
        let patch = try await repo.diffPaths(approvedTargets)
        if patch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DetDocError("EMPTY_PATCH", "Agent produced no code changes for approved target files.")
        }
        return patch.hasSuffix("\n") ? patch : patch + "\n"
    }
}
