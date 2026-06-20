import Foundation
import Testing
@testable import DetDocViewModels
@testable import DetDocCore

@MainActor
@Test func loadEditSavePersistsConfig() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    let vm = SettingsViewModel(root: fx.root)
    vm.load()
    #expect(vm.config.apply.autoCommit == true)

    vm.config.apply = ApplyConfig(autoCommit: false)
    vm.config.validation = ValidationConfig(commands: [ValidationCommand(name: "test", run: "swift test")])
    vm.save()
    #expect(vm.error == nil)

    let reloaded = try ConfigStore().load(root: fx.root)
    #expect(reloaded.apply.autoCommit == false)
    #expect(reloaded.validation.commands == [ValidationCommand(name: "test", run: "swift test")])
}
