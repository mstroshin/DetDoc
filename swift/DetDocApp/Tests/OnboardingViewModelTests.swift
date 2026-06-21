import Foundation
import Testing
@testable import DetDoc
@testable import DetDocCore

@MainActor
@Test func initializeCreatesDetdocConfig() async throws {
    let fx = try await VMGitFixture()
    let vm = OnboardingViewModel(root: fx.root)
    let ok = vm.initialize()
    #expect(ok)
    #expect(vm.error == nil)
    #expect(FileManager.default.fileExists(atPath: ConfigStore().configPath(root: fx.root).path))
}
