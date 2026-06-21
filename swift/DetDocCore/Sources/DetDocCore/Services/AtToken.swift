import Foundation

/// A raw `@<path>` token found in text, before classification into doc-ref vs image-ref.
struct AtToken: Equatable {
    let range: NSRange   // covers "@path" including the leading @
    let path: String     // path without the @, trailing "./-_" punctuation trimmed
}

enum AtTokenScanner {
    /// Finds `@<path>` tokens where `@` is at a word boundary (start of text or
    /// preceded by whitespace) and is followed by >=1 path char (letters, digits,
    /// and `/ - _ .`). Trailing `./-_` punctuation is trimmed from the path.
    static func scan(_ text: String) -> [AtToken] {
        let ns = text as NSString
        let re = try! NSRegularExpression(pattern: #"(?<![^\s])@([\p{L}\p{N}/_.\-]+)"#)
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let full = m.range
            var path = ns.substring(with: m.range(at: 1))
            var len = full.length
            while let last = path.last, "./-_".contains(last) { path.removeLast(); len -= 1 }
            guard !path.isEmpty else { return nil }
            return AtToken(range: NSRange(location: full.location, length: len), path: path)
        }
    }
}
