import Foundation

public struct DocLinkResolver: Sendable {
    public struct Resolution: Equatable, Sendable {
        public let docsRelativePath: String
        public let docPath: String
        public let exists: Bool
        public init(docsRelativePath: String, docPath: String, exists: Bool) {
            self.docsRelativePath = docsRelativePath; self.docPath = docPath; self.exists = exists
        }
    }

    private let existing: Set<String>
    public init(candidates: Set<String>) { self.existing = candidates }

    public func resolve(_ tokenPath: String) -> Resolution? {
        let path = tokenPath.hasPrefix("/") ? String(tokenPath.dropFirst()) : tokenPath
        guard !path.isEmpty else { return nil }
        let trimmed = path.hasSuffix(".md") ? String(path.dropLast(3)) : path
        let docsRel = trimmed + ".md"
        return Resolution(docsRelativePath: docsRel, docPath: "docs/\(docsRel)", exists: existing.contains(docsRel))
    }
}
