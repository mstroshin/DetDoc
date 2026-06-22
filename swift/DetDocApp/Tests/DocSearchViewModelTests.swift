import Foundation
import Testing
@testable import DetDoc
@testable import DetDocCore

@MainActor
private func makeVM() async throws -> (VMGitFixture, DocSearchViewModel) {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    try fx.write("docs/a.md", "Sidebar with sections:\nUse this folder for planning.\n")
    let vm = DocSearchViewModel(root: fx.root, config: .default)
    vm.present()
    return (fx, vm)
}

@MainActor
@Test func contentResultsTrackTheCurrentQuery() async throws {
    let (fx, vm) = try await makeVM()

    vm.query = "se"
    vm.reload()
    #expect(!vm.contentResults.isEmpty)              // matches "sections"/"Use"

    // Growing the query past the earlier match must NOT leave stale results behind.
    vm.query = "settings"
    vm.reload()
    #expect(vm.contentResults.isEmpty)               // no line contains "settings"
    withExtendedLifetime(fx) {}
}

@MainActor
@Test func filesRankAboveContentAndSelectionSpansBothGroups() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    try fx.write("docs/settings.md", "# Settings\nconfigure the app here.\n")
    try fx.write("docs/other.md", "open the settings page for details.\n")
    let vm = DocSearchViewModel(root: fx.root, config: .default)
    vm.present()

    vm.query = "settings"
    vm.reload()
    #expect(vm.fileResults.contains { $0.docsRelativePath == "settings.md" })   // name match -> top
    #expect(!vm.contentResults.isEmpty)                                          // line match -> below

    // Index 0 resolves to a file; the first index past the files resolves to content.
    vm.selectedIndex = 0
    #expect(vm.selectedPath() == "docs/settings.md")
    vm.selectedIndex = vm.fileResults.count
    #expect(vm.selectedPath() == vm.contentResults.first?.path)
    withExtendedLifetime(fx) {}
}

@MainActor
@Test func emptyQueryListsAllFilesAndNoContent() async throws {
    let (fx, vm) = try await makeVM()
    #expect(!vm.fileResults.isEmpty)     // present() seeds all docs
    #expect(vm.contentResults.isEmpty)   // content needs 2+ chars
    withExtendedLifetime(fx) {}
}
