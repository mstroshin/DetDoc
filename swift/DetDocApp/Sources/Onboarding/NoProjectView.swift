import SwiftUI

struct NoProjectView: View {
    @Environment(AppCoordinator.self) private var coordinator
    var body: some View {
        ContentUnavailableView {
            Label("No project open", systemImage: "folder.badge.questionmark")
        } description: {
            Text("Choose a git repository to begin.")
        } actions: {
            Button("Select project folder…") { Task { await coordinator.chooseProject() } }
                .buttonStyle(.borderedProminent)
        }
    }
}
