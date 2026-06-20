import SwiftUI
import DetDocViewModels

struct DocEditorScreen: View {
    @Bindable var editor: DocEditorViewModel

    private var sourceBinding: Binding<String> {
        Binding(get: { editor.source }, set: { editor.edit($0) })
    }

    var body: some View {
        if editor.selectedPath == nil {
            ContentUnavailableView("Select a document", systemImage: "doc.text", description: Text("Pick a Markdown file from the sidebar."))
        } else {
            HSplitView {
                TextEditor(text: sourceBinding)
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 280)
                ScrollView {
                    Text(editor.previewMarkdown())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
                .frame(minWidth: 280)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(editor.selectedPath ?? "").font(.headline)
                }
                ToolbarItem {
                    Button("Save") { editor.save() }
                        .disabled(!editor.isDirty)
                }
            }
        }
    }
}
