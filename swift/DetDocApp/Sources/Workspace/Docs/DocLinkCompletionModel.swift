import Foundation
import Observation
import DetDocCore

@MainActor
@Observable
public final class DocLinkCompletionModel {
    public private(set) var isActive = false
    public private(set) var query = ""
    public private(set) var items: [DocCandidate] = []
    public private(set) var selectedIndex = 0
    public private(set) var caretRect: CGRect = .zero
    private var replaceRange = NSRange(location: 0, length: 0)

    public struct Insertion: Equatable {
        public let text: String
        public let range: NSRange
    }

    public init() {}

    public func begin(query: ActiveQuery, caretRect: CGRect, candidates: [DocCandidate]) {
        isActive = true
        selectedIndex = 0
        update(query: query, caretRect: caretRect, candidates: candidates)
    }

    public func update(query q: ActiveQuery, caretRect: CGRect, candidates: [DocCandidate]) {
        query = q.query
        replaceRange = q.range
        self.caretRect = caretRect
        items = DocLinkCompletion.suggestions(query: q.query, candidates: candidates)
        if selectedIndex >= items.count { selectedIndex = max(0, items.count - 1) }
    }

    public func moveUp() { if !items.isEmpty { selectedIndex = (selectedIndex - 1 + items.count) % items.count } }
    public func moveDown() { if !items.isEmpty { selectedIndex = (selectedIndex + 1) % items.count } }

    public func selectByTap(_ i: Int) { if items.indices.contains(i) { selectedIndex = i } }

    public func cancel() { isActive = false; items = []; query = "" }

    public func commit() -> Insertion? {
        guard isActive, items.indices.contains(selectedIndex) else { return nil }
        let c = items[selectedIndex]
        isActive = false
        return Insertion(text: DocLink.make(name: c.name, docsRelativePath: c.docsRelativePath), range: replaceRange)
    }
}
