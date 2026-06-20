import SwiftUI
import DetDocCore

struct DocsExplorerView: View {
    let docs: [DocFile]
    @Binding var selection: String?
    var body: some View { Text("\(docs.count) docs") }
}
