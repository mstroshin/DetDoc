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

    public func resolve(_ destination: String) -> Resolution? {
        guard let target = DocLink.internalTarget(ofDestination: destination) else { return nil }
        return Resolution(docsRelativePath: target, docPath: "docs/\(target)", exists: existing.contains(target))
    }
}
