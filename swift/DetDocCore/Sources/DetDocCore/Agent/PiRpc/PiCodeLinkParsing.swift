import Foundation

/// Extracts the optional `detdoc-links` fenced block pi emits at the end of an
/// implement/repair turn. Each line: `<docPath> <heading…> -> <ref>[, <ref>…]`.
public enum PiCodeLinkParsing {
    public static func parseCodeLinks(fromAssistantText text: String) -> [CodeLink] {
        guard let block = fencedBlock(text, lang: "detdoc-links") else { return [] }
        return block.split(separator: "\n").compactMap { raw -> CodeLink? in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let halves = line.components(separatedBy: " -> ")
            guard halves.count == 2 else { return nil }
            let left = halves[0].split(separator: " ", maxSplits: 1).map(String.init)
            guard left.count == 2 else { return nil }
            let docPath = left[0]
            let heading = left[1].trimmingCharacters(in: .whitespaces)
            let refs = halves[1].split(whereSeparator: { $0 == "," || $0 == " " })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !heading.isEmpty, !refs.isEmpty else { return nil }
            return CodeLink(docPath: docPath, heading: heading, refs: refs)
        }
    }

    /// Returns the contents between ```<lang> and the next ``` fence, or nil.
    static func fencedBlock(_ text: String, lang: String) -> String? {
        let ns = text as NSString
        let pattern = "```\(lang)\\n([\\s\\S]*?)```"
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}
