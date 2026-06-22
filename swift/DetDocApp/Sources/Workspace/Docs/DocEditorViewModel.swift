import Foundation
import Observation
import DetDocCore

@MainActor
@Observable
public final class DocEditorViewModel {
    public private(set) var selectedPath: String?
    public private(set) var source: String = ""
    public private(set) var isDirty: Bool = false
    public private(set) var error: DetDocError?

    private let root: URL
    private let docs: DocsService

    public init(root: URL, config: DetDocConfig) {
        self.root = root
        self.docs = DocsService(root: root, config: config)
    }

    public func open(_ path: String) {
        selectedPath = path
        do {
            source = try docs.read(path)
            error = nil
        } catch let e as DetDocError {
            error = e
            source = ""
        } catch {
            self.error = DetDocError("DOC_READ_FAILED", "\(error)")
            source = ""
        }
        isDirty = false
    }

    public func clear() {
        selectedPath = nil
        source = ""
        isDirty = false
        error = nil
    }

    public func edit(_ text: String) {
        source = text
        isDirty = true
        save()   // autosave; isDirty stays true only if the write fails
        // ponytail: writes the whole doc on every keystroke — fine for markdown.
        // Add debouncing if large docs ever lag.
    }

    public func save() {
        guard let path = selectedPath else { return }
        do {
            try docs.write(path, source)
            isDirty = false
            error = nil
        } catch let e as DetDocError {
            error = e
        } catch {
            self.error = DetDocError("DOC_WRITE_FAILED", "\(error)")
        }
    }

    public func previewMarkdown() -> AttributedString {
        (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(source)
    }
}
