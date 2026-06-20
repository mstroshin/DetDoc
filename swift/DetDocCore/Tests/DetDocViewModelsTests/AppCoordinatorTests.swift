import Foundation
import Testing
@testable import DetDocViewModels
@testable import DetDocCore

private struct StubPicker: FolderPicking {
    let url: URL?
    func pickFolder() async -> URL? { url }
}

@MainActor
@Test func openRoutesToOnboardingWhenNotInitialized() async throws {
    let fx = try await VMGitFixture()
    let coordinator = AppCoordinator(picker: StubPicker(url: fx.root))
    coordinator.open(root: fx.root)
    #expect(coordinator.route == .onboarding(root: fx.root))
}

@MainActor
@Test func openRoutesToWorkspaceWhenInitialized() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    let coordinator = AppCoordinator(picker: StubPicker(url: fx.root))
    coordinator.open(root: fx.root)
    #expect(coordinator.route == .workspace(root: fx.root))
}

@MainActor
@Test func chooseProjectUsesPickerThenRoutes() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    let coordinator = AppCoordinator(picker: StubPicker(url: fx.root))
    await coordinator.chooseProject()
    #expect(coordinator.route == .workspace(root: fx.root))
}

@MainActor
@Test func chooseProjectStaysNoProjectWhenCancelled() async {
    let coordinator = AppCoordinator(picker: StubPicker(url: nil))
    await coordinator.chooseProject()
    #expect(coordinator.route == .noProject)
}
