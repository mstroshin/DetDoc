import Foundation

/// Translates a globset-compatible glob into an anchored regex, matching the
/// Rust reference's globset defaults (literal_separator = false): `*` and `?`
/// both match across `/`; a `**/` segment matches zero or more directories.
public struct Glob: Sendable {
    private let regex: NSRegularExpression?

    public init(_ pattern: String) {
        self.regex = Glob.compile(pattern)
    }

    public func matches(_ path: String) -> Bool {
        guard let regex else { return false }
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        return regex.firstMatch(in: path, options: [], range: range) != nil
    }

    public static func matchesAny(_ path: String, patterns: [String]) -> Bool {
        patterns.contains { Glob($0).matches(path) }
    }

    private static func compile(_ pattern: String) -> NSRegularExpression? {
        let chars = Array(pattern)
        var out = "^"
        var i = 0
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "*":
                if i + 1 < chars.count, chars[i + 1] == "*" {
                    if i + 2 < chars.count, chars[i + 2] == "/" {
                        out += "(?:.*/)?"   // `**/` — zero or more directory segments
                        i += 3
                    } else {
                        out += ".*"         // `**` — any chars incl. `/`
                        i += 2
                    }
                } else {
                    out += ".*"            // `*` — any chars incl. `/` (globset default)
                    i += 1
                }
            case "?":
                out += "."                // `?` — any single char incl. `/` (globset default)
                i += 1
            case ".", "^", "$", "+", "(", ")", "[", "]", "{", "}", "|", "\\":
                out += "\\" + String(c)
                i += 1
            default:
                out += String(c)
                i += 1
            }
        }
        out += "$"
        return try? NSRegularExpression(pattern: out, options: [])
    }
}
