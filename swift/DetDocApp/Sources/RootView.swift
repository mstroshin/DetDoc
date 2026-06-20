import SwiftUI
import DetDocViewModels

struct RootView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        content
            .task {
                // Dev/automation affordance: open a project directly via env var,
                // bypassing the folder picker. No effect when unset.
                if case .noProject = coordinator.route,
                   let path = ProcessInfo.processInfo.environment["DETDOC_PROJECT"], !path.isEmpty {
                    coordinator.open(root: URL(filePath: path))
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch coordinator.route {
        case .noProject:
            NoProjectView()
        case .onboarding(let root):
            OnboardingScreen(root: root)
        case .workspace(let root):
            WorkspaceView(root: root)
        }
    }
}
