import SwiftUI
import DetDocCore

struct DocEditorScreen: View {
    @Bindable var editor: DocEditorViewModel
    var resolver: DocLinkResolver
    var imageImporter: DocImageImporter
    /// Driven by the shared central-block header in WorkspaceView.
    var showCodeLinks: Bool
    var candidatesProvider: () -> [DocCandidate]
    var onFollowLink: (String) -> Void

    var body: some View {
        Group {
            if editor.selectedPath == nil {
                ContentUnavailableView("Select a document", systemImage: "doc.text",
                                       description: Text("Pick a Markdown file from the sidebar."))
                    .accessibilityIdentifier("doc-editor-empty")
            } else {
                LivePreviewTextView(editor: editor, resolver: resolver,
                                    imageImporter: imageImporter,
                                    candidatesProvider: candidatesProvider,
                                    onFollowLink: onFollowLink,
                                    showCodeLinks: showCodeLinks)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("doc-editor-live-preview")
            }
        }
    }
}

@MainActor private func previewScreen(showLinks: Bool) -> some View {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("detdoc-preview-\(showLinks)", isDirectory: true)
    let docs = dir.appendingPathComponent("docs", isDirectory: true)
    try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
    let md = "# Idea\n\nDo the thing.\n\n<!-- detdoc:link \"# Idea\" src/app.swift#run -->\n"
    try? md.write(to: docs.appendingPathComponent("idea.md"), atomically: true, encoding: .utf8)
    let editor = DocEditorViewModel(root: dir, config: .default)
    editor.open("docs/idea.md")
    return DocEditorScreen(editor: editor,
                           resolver: DocLinkResolver(candidates: []),
                           imageImporter: DocImageImporter(root: dir),
                           showCodeLinks: showLinks,
                           candidatesProvider: { [] },
                           onFollowLink: { _ in })
        .frame(width: 600, height: 400)
}

#Preview("Code links hidden") { previewScreen(showLinks: false) }
#Preview("Code links shown")  { previewScreen(showLinks: true) }
