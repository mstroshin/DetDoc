public enum PatchValidator {
    public static func validatePaths(_ patch: String, approvedTargets: [String], config: DetDocConfig) throws {
        let policy = PathPolicy(config: config)
        for line in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            guard text.hasPrefix("+++ b/") || text.hasPrefix("--- a/") else { continue }
            let path = String(text.dropFirst(6))
            if path == "/dev/null" { continue }
            if policy.isDenied(path) { throw DetDocError("PATCH_DENIED_PATH", path) }
            if policy.isDoc(path) { throw DetDocError("PATCH_DOC_PATH", path) }
            if !approvedTargets.contains(path) { throw DetDocError("PATCH_UNAPPROVED_PATH", path) }
        }
    }
}
