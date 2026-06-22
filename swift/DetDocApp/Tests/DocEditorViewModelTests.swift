import Foundation
import Testing
@testable import DetDoc
@testable import DetDocCore

@MainActor
@Test func openEditSaveRoundTrips() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    let vm = DocEditorViewModel(root: fx.root, config: .default)

    vm.open("docs/idea.md")
    #expect(vm.selectedPath == "docs/idea.md")
    #expect(vm.isDirty == false)

    vm.edit("# Edited\n")
    #expect(vm.isDirty == false)   // autosaved on edit

    let onDisk = try String(contentsOf: fx.root.appendingPathComponent("docs/idea.md"), encoding: .utf8)
    #expect(onDisk == "# Edited\n")
}

@MainActor
@Test func previewRendersMarkdown() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    let vm = DocEditorViewModel(root: fx.root, config: .default)
    vm.edit("Hello **bold**")
    let preview = vm.previewMarkdown()
    #expect(String(preview.characters).contains("Hello"))
}

@MainActor
@Test func editAutosavesLeavingErrorNilAndIsDirtyFalse() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    let vm = DocEditorViewModel(root: fx.root, config: .default)
    vm.open("docs/idea.md")
    vm.edit("updated\n")
    #expect(vm.isDirty == false)
    #expect(vm.error == nil)
    let onDisk = try String(contentsOf: fx.root.appendingPathComponent("docs/idea.md"), encoding: .utf8)
    #expect(onDisk == "updated\n")
}

@MainActor
@Test func clearResetsEditorState() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    let vm = DocEditorViewModel(root: fx.root, config: .default)
    vm.open("docs/idea.md")
    vm.edit("changed\n")
    vm.clear()
    #expect(vm.selectedPath == nil)
    #expect(vm.source == "")
    #expect(vm.isDirty == false)
    #expect(vm.error == nil)
}
