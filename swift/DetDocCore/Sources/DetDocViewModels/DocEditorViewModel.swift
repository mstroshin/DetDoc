import Foundation
import Observation
import DetDocCore

@MainActor
@Observable
public final class DocEditorViewModel {
    public private(set) var selectedPath: String?
    public private(set) var source: String = ""
    public private(set) var isDirty: Bool = false

    private let root: URL
    private let docs: DocsService

    public init(root: URL, config: DetDocConfig) {
        self.root = root
        self.docs = DocsService(root: root, config: config)
    }

    public func open(_ path: String) {
        selectedPath = path
        source = (try? docs.read(path)) ?? ""
        isDirty = false
    }

    public func edit(_ text: String) {
        source = text
        isDirty = true
    }

    public func save() {
        guard let path = selectedPath else { return }
        try? docs.write(path, source)
        isDirty = false
    }

    public func previewMarkdown() -> AttributedString {
        (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(source)
    }
}
