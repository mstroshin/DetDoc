import Foundation

public struct ActiveQuery: Equatable, Sendable {
    public let range: NSRange
    public let query: String
    public init(range: NSRange, query: String) { self.range = range; self.query = query }
}

public enum DocLinkCompletion {
    public static func activeQuery(in source: String, cursorUTF16Offset: Int) -> ActiveQuery? {
        let ns = source as NSString
        let cursor = max(0, min(cursorUTF16Offset, ns.length))
        var i = cursor
        while i > 0 {
            let c = ns.character(at: i - 1)
            if c == unichar(UInt16(UInt8(ascii: "@"))) {
                let at = i - 1
                let boundary = at == 0 || isWhitespace(ns.character(at: at - 1))
                guard boundary else { return nil }
                let query = ns.substring(with: NSRange(location: i, length: cursor - i))
                return ActiveQuery(range: NSRange(location: at, length: cursor - at), query: query)
            }
            guard isQueryChar(c) else { return nil }
            i -= 1
        }
        return nil
    }

    private static func isQueryChar(_ c: unichar) -> Bool {
        guard let s = Unicode.Scalar(c) else { return false }
        let ch = Character(s)
        return ch.isLetter || ch.isNumber || "/-_.".contains(ch)
    }
    private static func isWhitespace(_ c: unichar) -> Bool {
        guard let s = Unicode.Scalar(c) else { return false }
        return Character(s).isWhitespace
    }
}

extension DocLinkCompletion {
    public static func suggestions(query: String, candidates: [DocCandidate]) -> [DocCandidate] {
        let q = query.lowercased()
        guard !q.isEmpty else { return candidates }
        let ranked: [(DocCandidate, Int)] = candidates.compactMap { c in
            let path = c.docsRelativePath.lowercased()
            if let r = path.range(of: q) {
                let isPrefix = path.hasPrefix(q) || c.name.lowercased().hasPrefix(q)
                let offset = path.distance(from: path.startIndex, to: r.lowerBound)
                return (c, isPrefix ? 0 : 1 + offset)
            }
            if (c.title ?? "").lowercased().contains(q) { return (c, 1000) }
            return nil
        }
        return ranked.sorted {
            $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.docsRelativePath < $1.0.docsRelativePath
        }.map(\.0)
    }
}
