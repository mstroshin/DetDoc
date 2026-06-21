import Foundation

public enum MarkdownSpanKind: Equatable, Sendable {
    case heading(level: Int)
    case bold
    case italic
    case link(destination: String, textRange: NSRange)
}

public struct MarkdownSpan: Equatable, Sendable {
    public let range: NSRange
    public let kind: MarkdownSpanKind
    public init(range: NSRange, kind: MarkdownSpanKind) { self.range = range; self.kind = kind }
}

public enum MarkdownStyleScanner {
    public static func scan(_ source: String) -> [MarkdownSpan] {
        let ns = source as NSString
        var spans: [MarkdownSpan] = []
        spans.append(contentsOf: headings(ns))
        spans.append(contentsOf: matches(ns, #"\*\*(?:[^*]|\*(?!\*))+\*\*"#, kind: .bold))
        spans.append(contentsOf: matches(ns, #"(?<!\*)\*(?!\*)[^*\n]+\*(?!\*)"#, kind: .italic))
        spans.append(contentsOf: links(ns))
        return spans
    }

    private static func headings(_ ns: NSString) -> [MarkdownSpan] {
        regex(#"(?m)^(#{1,6})[ \t].*$"#).matches(in: ns as String, range: NSRange(location: 0, length: ns.length)).map {
            let hashes = ns.substring(with: $0.range(at: 1)).count
            return MarkdownSpan(range: $0.range, kind: .heading(level: hashes))
        }
    }

    private static func matches(_ ns: NSString, _ pattern: String, kind: MarkdownSpanKind) -> [MarkdownSpan] {
        regex(pattern).matches(in: ns as String, range: NSRange(location: 0, length: ns.length))
            .map { MarkdownSpan(range: $0.range, kind: kind) }
    }

    private static func links(_ ns: NSString) -> [MarkdownSpan] {
        // [text](dest) not preceded by '!' (which would be an image)
        regex(#"(?<!\!)\[([^\]]*)\]\(([^)\s]+)\)"#)
            .matches(in: ns as String, range: NSRange(location: 0, length: ns.length))
            .map {
                let dest = ns.substring(with: $0.range(at: 2))
                return MarkdownSpan(range: $0.range, kind: .link(destination: dest, textRange: $0.range(at: 1)))
            }
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are static and known-valid; force-try is acceptable here.
        try! NSRegularExpression(pattern: pattern)
    }
}
