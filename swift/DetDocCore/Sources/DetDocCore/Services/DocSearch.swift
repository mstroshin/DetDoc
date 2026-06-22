import Foundation

/// A single line match from a full-text search over the docs corpus.
public struct DocContentHit: Equatable, Sendable, Identifiable {
    public let path: String       // project-root relative, e.g. "docs/guides/setup.md"
    public let line: Int          // 1-based
    public let lineText: String   // trimmed (and truncated) matching line
    public let match: String      // the query, kept for highlighting
    public var id: String { "\(path):\(line)" }
    public init(path: String, line: Int, lineText: String, match: String) {
        self.path = path
        self.line = line
        self.lineText = lineText
        self.match = match
    }
}

/// Search over the `docs/` markdown corpus. Two modes:
/// - file names/titles via `candidates()` + `DocLinkCompletion.suggestions`
/// - full text via `content()`.
public struct DocSearch: Sendable {
    private let docs: DocsService

    public init(root: URL, config: DetDocConfig) {
        self.docs = DocsService(root: root, config: config)
    }

    /// All docs as ranking candidates. Reads each file once (for its heading), so
    /// callers should cache the result rather than call it per keystroke.
    public func candidates() -> [DocCandidate] { docs.candidates() }

    // ponytail: greps every doc on each call. Fine for a markdown docs/ tree;
    // swap in a cached index if a corpus ever grows big enough to lag.
    public func content(query: String, limit: Int = 200) -> [DocContentHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 2 else { return [] }
        var hits: [DocContentHit] = []
        for file in docs.list() {
            guard let text = try? docs.read(file.path) else { continue }
            var lineNo = 0
            for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
                lineNo += 1
                guard raw.lowercased().contains(q) else { continue }
                let line = raw.trimmingCharacters(in: .whitespaces)
                hits.append(DocContentHit(path: file.path, line: lineNo, lineText: snippet(line, around: q), match: query))
                if hits.count >= limit { return hits }
            }
        }
        return hits
    }

    /// A one-line excerpt that keeps the match visible: window the line around the
    /// first occurrence of `q` (lowercased) so a match late in a long line isn't
    /// truncated off the end by the UI.
    private func snippet(_ line: String, around q: String, window: Int = 80, pad: Int = 24) -> String {
        guard line.count > window, let r = line.range(of: q, options: .caseInsensitive) else {
            return line.count > 400 ? String(line.prefix(400)) + "…" : line
        }
        let matchStart = line.distance(from: line.startIndex, to: r.lowerBound)
        let from = max(0, matchStart - pad)
        let start = line.index(line.startIndex, offsetBy: from)
        let body = String(line[start...].prefix(window))
        return (from > 0 ? "…" : "") + body + "…"
    }
}
