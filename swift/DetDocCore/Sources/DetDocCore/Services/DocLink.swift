import Foundation

public enum DocLink {
    public static func make(name: String, docsRelativePath: String) -> String {
        "[\(name)](\(docsRelativePath))"
    }

    public static func internalTarget(ofDestination destination: String) -> String? {
        let d = destination.trimmingCharacters(in: .whitespaces)
        guard !d.isEmpty, !d.hasPrefix("#") else { return nil }
        guard !d.contains("://"), !d.hasPrefix("mailto:") else { return nil }
        let path = String(d.split(separator: "#", maxSplits: 1).first ?? "")
        let normalized = path.hasPrefix("./") ? String(path.dropFirst(2)) : path
        guard normalized.hasSuffix(".md") else { return nil }
        return normalized
    }
}
