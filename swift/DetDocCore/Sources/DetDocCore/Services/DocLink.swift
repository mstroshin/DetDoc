import Foundation

public enum DocLink {
    /// Build the stored link token for a docs-relative path: "@" + path without ".md".
    /// e.g. "guides/setup.md" -> "@guides/setup"
    public static func make(docsRelativePath: String) -> String {
        let noExt = docsRelativePath.hasSuffix(".md") ? String(docsRelativePath.dropLast(3)) : docsRelativePath
        return "@\(noExt)"
    }
}
