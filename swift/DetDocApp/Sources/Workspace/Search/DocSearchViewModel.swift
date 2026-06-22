import Foundation
import Observation
import DetDocCore

@MainActor
@Observable
final class DocSearchViewModel {
    var query = ""
    var fileResults: [DocCandidate] = []       // name/title matches, shown first
    var contentResults: [DocContentHit] = []   // in-document line matches, shown below
    var selectedIndex = 0                       // spans files then content

    private let search: DocSearch
    private var candidates: [DocCandidate] = []

    init(root: URL, config: DetDocConfig) {
        self.search = DocSearch(root: root, config: config)
    }

    var resultCount: Int { fileResults.count + contentResults.count }

    /// Reset to a clean slate; called when the palette opens.
    func present() {
        query = ""
        selectedIndex = 0
        contentResults = []
        // ponytail: candidates() reads every doc once (for headings) — cheap for a
        // markdown tree, and we cache so keystrokes only re-rank, never re-read.
        candidates = search.candidates()
        fileResults = candidates
    }

    func reload() {
        selectedIndex = 0
        let q = query
        fileResults = DocLinkCompletion.suggestions(query: q, candidates: candidates)
        // ponytail: synchronous grep — the docs/ tree is small markdown, so reading
        // it per keystroke is instant. Content search needs 2+ chars; file ranking
        // always runs so the palette doubles as a doc browser when empty.
        contentResults = q.trimmingCharacters(in: .whitespaces).count >= 2 ? search.content(query: q) : []
    }

    func move(_ delta: Int) {
        let n = resultCount
        guard n > 0 else { return }
        selectedIndex = (selectedIndex + delta + n) % n
    }

    /// Project-root-relative path ("docs/…") of the highlighted row. Indices below
    /// `fileResults.count` are file matches; the rest are content matches.
    func selectedPath() -> String? {
        guard selectedIndex >= 0, selectedIndex < resultCount else { return nil }
        if selectedIndex < fileResults.count {
            return "docs/" + fileResults[selectedIndex].docsRelativePath
        }
        return contentResults[selectedIndex - fileResults.count].path
    }
}
