import SwiftUI
import DetDocViewModels

struct RootView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
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
