import Foundation
import Testing
@testable import DetDoc
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

@MainActor
@Test func restoreLastProjectReopensRememberedFolder() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    let defaults = UserDefaults(suiteName: "detdoc.test.\(UUID().uuidString)")!

    // First coordinator opens the project (which persists it)...
    AppCoordinator(picker: StubPicker(url: nil), defaults: defaults).open(root: fx.root)
    // ...a fresh launch restores it.
    let next = AppCoordinator(picker: StubPicker(url: nil), defaults: defaults)
    next.restoreLastProject()
    guard case .workspace(let restored) = next.route else {
        Issue.record("expected workspace route, got \(next.route)"); return
    }
    #expect(restored.path == fx.root.path)
}

@MainActor
@Test func restoreLastProjectIgnoresDeletedFolder() async {
    let defaults = UserDefaults(suiteName: "detdoc.test.\(UUID().uuidString)")!
    defaults.set("/nonexistent/detdoc-\(UUID().uuidString)", forKey: "detdoc.lastProjectPath")
    let coordinator = AppCoordinator(picker: StubPicker(url: nil), defaults: defaults)
    coordinator.restoreLastProject()
    #expect(coordinator.route == .noProject)
}
