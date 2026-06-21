import SwiftUI
import DetDocCore

struct DocEditorScreen: View {
    @Bindable var editor: DocEditorViewModel
    var resolver: DocLinkResolver
    var onFollowLink: (String) -> Void

    var body: some View {
        Group {
            if editor.selectedPath == nil {
                ContentUnavailableView("Select a document", systemImage: "doc.text", description: Text("Pick a Markdown file from the sidebar."))
            } else {
                LivePreviewTextView(editor: editor, resolver: resolver, onFollowLink: onFollowLink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toolbar {
                        ToolbarItem(placement: .principal) { Text(editor.selectedPath ?? "").font(.headline) }
                        ToolbarItem { Button("Save") { editor.save() }.disabled(!editor.isDirty) }
                    }
            }
        }
    }
}
