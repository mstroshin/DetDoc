import SwiftUI
import DetDocViewModels

struct DocEditorScreen: View {
    @Bindable var editor: DocEditorViewModel
    var body: some View { Text(editor.selectedPath ?? "No document") }
}
