import SwiftUI

struct RootView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        content
            .task {
                guard case .noProject = coordinator.route else { return }
                // Dev/automation affordance: open a project directly via env var,
                // bypassing the folder picker. No effect when unset.
                if let path = ProcessInfo.processInfo.environment["DETDOC_PROJECT"], !path.isEmpty {
                    coordinator.open(root: URL(filePath: path))
                } else {
                    coordinator.restoreLastProject()
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
