import SwiftUI
import DetDocViewModels

struct OnboardingScreen: View {
    let root: URL
    var body: some View { Text("Onboarding: \(root.lastPathComponent)") }
}
