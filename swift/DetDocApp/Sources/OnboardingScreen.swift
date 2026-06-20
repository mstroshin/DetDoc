import SwiftUI
import DetDocViewModels

struct OnboardingScreen: View {
    let root: URL
    @Environment(AppCoordinator.self) private var coordinator
    @State private var onboarding: OnboardingViewModel

    init(root: URL) {
        self.root = root
        _onboarding = State(initialValue: OnboardingViewModel(root: root))
    }

    var body: some View {
        ContentUnavailableView {
            Label("Not a DetDoc project yet", systemImage: "sparkles")
        } description: {
            Text(root.path).font(.caption).monospaced()
        } actions: {
            Button("Initialize DetDoc") {
                if onboarding.initialize() { coordinator.initialized(root: root) }
            }.buttonStyle(.borderedProminent)
            Button("Choose a different folder…") { Task { await coordinator.chooseProject() } }
            if let error = onboarding.error {
                Text("\(error.code): \(error.message)").font(.caption).foregroundStyle(.red)
            }
        }
    }
}
