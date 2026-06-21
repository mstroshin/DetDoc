public enum DirtyPolicy {
    public static func nonDocOffenders(_ entries: [GitStatusEntry], config: DetDocConfig) -> [GitStatusEntry] {
        let policy = PathPolicy(config: config)
        return entries.filter { entry in
            !entry.path.hasPrefix(".detdoc/") && entry.path != ".gitignore" && !policy.isDoc(entry.path)
        }
    }

    public static func assertClean(_ entries: [GitStatusEntry], config: DetDocConfig) throws {
        let offenders = nonDocOffenders(entries, config: config)
        if !offenders.isEmpty {
            throw DetDocError("DIRTY_NON_DOC_CHANGES", offenders.map(\.path).joined(separator: ", "))
        }
    }
}
