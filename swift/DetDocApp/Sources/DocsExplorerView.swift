import SwiftUI
import DetDocCore

struct DocsExplorerView: View {
    let docs: [DocFile]
    @Binding var selection: String?

    var body: some View {
        List(selection: $selection) {
            ForEach(docs, id: \.path) { doc in
                Label(doc.path, systemImage: "doc.text")
                    .tag(doc.path)
            }
        }
        .overlay {
            if docs.isEmpty {
                ContentUnavailableView("No documents", systemImage: "doc", description: Text("Markdown files under docs/ appear here."))
            }
        }
    }
}
