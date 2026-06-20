import SwiftUI
import DetDocViewModels

struct WorkspaceView: View {
    let root: URL
    var body: some View { Text("Workspace: \(root.lastPathComponent)") }
}
