import Foundation
import Testing
@testable import DetDoc
@testable import DetDocCore

@MainActor
@Test func initializeCreatesDetdocConfig() async throws {
    let fx = try await VMGitFixture()
    let vm = OnboardingViewModel(root: fx.root)
    let ok = await vm.initialize()
    #expect(ok)
    #expect(vm.error == nil)
    #expect(FileManager.default.fileExists(atPath: ConfigStore().configPath(root: fx.root).path))
}

@MainActor
@Test func initializeCreatesGitRepoInEmptyFolder() async throws {
    // No git fixture: a bare temp folder, like the user creating a project from scratch.
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("detdoc-onb-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let ok = await OnboardingViewModel(root: root).initialize()
    #expect(ok)
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path))
    // HEAD resolves -> the initial commit exists, so runs/worktrees will work.
    let head = try await GitRepository(root).headCommit()
    #expect(head.count == 40)
}
