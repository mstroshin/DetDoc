public enum DocDiff {
    public static func normalized(_ repo: GitRepository, config: DetDocConfig) async throws -> String {
        let entries = try await repo.statusPorcelain()
        try DirtyPolicy.assertClean(entries, config: config, mode: .run)
        let policy = PathPolicy(config: config)
        let docPaths = entries.filter { policy.isDoc($0.path) }.map(\.path)
        if docPaths.isEmpty {
            throw DetDocError("NO_DOC_CHANGES", "No documentation changes found")
        }
        _ = try? await repo.git(["add", "-N", "--"] + docPaths)  // include untracked docs
        return try await repo.diffPaths(docPaths)
    }
}
