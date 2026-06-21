import Foundation

public struct DocRef: Equatable, Sendable {
    public let range: NSRange   // covers "@guides/setup" (includes the @)
    public let path: String     // docs-relative path WITHOUT .md, e.g. "guides/setup"
    public init(range: NSRange, path: String) { self.range = range; self.path = path }
}

public enum DocRefScanner {
    /// Finds `@<path>` tokens where `@` is at a word boundary (start of text or
    /// preceded by whitespace) and is followed by >=1 path char
    /// (letters, digits, and / - _ .). The path excludes the leading `@`.
    public static func scan(_ text: String) -> [DocRef] {
        let ns = text as NSString
        let re = try! NSRegularExpression(pattern: #"(?<![^\s])@([\p{L}\p{N}/_.\-]+)"#)
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            DocRef(range: $0.range, path: ns.substring(with: $0.range(at: 1)))
        }
    }
}
