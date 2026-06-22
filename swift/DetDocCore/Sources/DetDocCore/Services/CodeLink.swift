import Foundation

public struct CodeLink: Sendable, Equatable {
    public let docPath: String   // repo-relative .md the link belongs to ("" when parsed in-file)
    public let heading: String   // exact heading text incl. leading '#'s, e.g. "## Plan approval"
    public let refs: [String]    // "Path.ext#symbol" entries
    public init(docPath: String, heading: String, refs: [String]) {
        self.docPath = docPath; self.heading = heading; self.refs = refs
    }
}

/// Reads/writes the trailing block of `<!-- detdoc:link "<heading>" <refs…> -->`
/// comments inside a single Markdown document.
public enum CodeLinkBlock {
    public static func isLinkLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("<!--") && t.hasSuffix("-->") && t.contains("detdoc:link")
    }

    public static func serializeLine(_ link: CodeLink) -> String {
        "<!-- detdoc:link \"\(link.heading)\" \(link.refs.joined(separator: " ")) -->"
    }

    /// Idempotent: strips every existing link line + trailing blanks, then appends a
    /// fresh block (blank line + one comment per link + trailing newline). Empty
    /// `links` just strips. Prose above the block is preserved verbatim.
    public static func apply(to markdown: String, links: [CodeLink]) -> String {
        var lines = markdown.components(separatedBy: "\n").filter { !isLinkLine($0) }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        let body = lines.joined(separator: "\n")
        if links.isEmpty { return body.isEmpty ? "" : body + "\n" }
        let block = links.map(serializeLine).joined(separator: "\n")
        return body + "\n\n" + block + "\n"
    }
}

/// Finds full `<!-- detdoc:link … -->` spans inside one paragraph (for the viewer).
public enum CodeLinkScanner {
    public static func scan(_ text: String) -> [NSRange] {
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map(\.range)
    }
    // Pattern is static and known-valid; force-try is acceptable here (mirrors MarkdownStyleScanner).
    private static let regex = try! NSRegularExpression(pattern: #"<!--\s*detdoc:link\s+"[^"]*"[^>]*-->"#)
}
