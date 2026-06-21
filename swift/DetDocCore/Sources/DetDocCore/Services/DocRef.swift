import Foundation

public struct DocRef: Equatable, Sendable {
    public let range: NSRange   // covers "@guides/setup" (includes the @)
    public let path: String     // docs-relative path WITHOUT .md, e.g. "guides/setup"
    public init(range: NSRange, path: String) { self.range = range; self.path = path }
}

public enum DocRefScanner {
    /// Finds `@<path>` doc-link tokens. Tokens whose path ends in a recognized image
    /// extension are owned by `ImageRefScanner` and excluded here.
    public static func scan(_ text: String) -> [DocRef] {
        AtTokenScanner.scan(text).compactMap { tok in
            guard !ImageRefScanner.isImagePath(tok.path) else { return nil }
            return DocRef(range: tok.range, path: tok.path)
        }
    }
}
