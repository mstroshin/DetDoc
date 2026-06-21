import Foundation
import Testing
@testable import DetDoc
@testable import DetDocCore

@MainActor
private func makeVM() async throws -> (VMGitFixture, DocsTreeViewModel) {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    let vm = DocsTreeViewModel(root: fx.root, config: .default)
    vm.refresh()
    return (fx, vm)
}

@MainActor
@Test func refreshExposesDocsContentsAtTopLevel() async throws {
    let (_, vm) = try await makeVM()
    // The single "docs" root is unwrapped: starter docs/ contents are top-level.
    #expect(vm.nodes.contains { $0.name == "idea.md" })
    #expect(vm.nodes.contains { $0.name == "features" && $0.isDirectory })
}

@MainActor
@Test func newFileCreatesMarkdownAndAppearsInTree() async throws {
    let (fx, vm) = try await makeVM()
    let path = vm.newFile(name: "notes", in: "docs")
    #expect(path == "docs/notes.md")
    #expect(try String(contentsOf: fx.root.appendingPathComponent("docs/notes.md"), encoding: .utf8).contains("notes"))
    #expect(vm.nodes.contains { $0.name == "notes.md" })
    #expect(vm.error == nil)
}

@MainActor
@Test func newFileInSubfolderLandsThere() async throws {
    let (_, vm) = try await makeVM()
    let path = vm.newFile(name: "todo.md", in: "docs/features")
    #expect(path == "docs/features/todo.md")
}

@MainActor
@Test func newFolderCreatesEmptyDirectoryNode() async throws {
    let (_, vm) = try await makeVM()
    let path = vm.newFolder(name: "drafts", in: "docs")
    #expect(path == "docs/drafts")
    let drafts = try #require(vm.nodes.first { $0.name == "drafts" })
    #expect(drafts.isDirectory)
    #expect(drafts.children == [])
}

@MainActor
@Test func duplicateCreateSetsError() async throws {
    let (_, vm) = try await makeVM()
    let path = vm.newFile(name: "idea", in: "docs")   // docs/idea.md already exists
    #expect(path == nil)
    #expect(vm.error?.code == "DOC_ALREADY_EXISTS")
    vm.dismissError()
    #expect(vm.error == nil)
}

@MainActor
@Test func renameFileKeepsParentAndReturnsNewPath() async throws {
    let (_, vm) = try await makeVM()
    let newPath = vm.rename("docs/idea.md", to: "concept")
    #expect(newPath == "docs/concept.md")
    #expect(vm.nodes.contains { $0.name == "concept.md" })
    #expect(vm.nodes.contains { $0.name == "idea.md" } == false)
}

@MainActor
@Test func renameDirectoryReturnsNewPath() async throws {
    let (_, vm) = try await makeVM()
    let newPath = vm.rename("docs/features", to: "specs")
    #expect(newPath == "docs/specs")
    #expect(vm.isDirectory("docs/specs"))
}

@MainActor
@Test func deleteRemovesNode() async throws {
    let (_, vm) = try await makeVM()
    vm.delete("docs/idea.md")
    #expect(vm.nodes.contains { $0.name == "idea.md" } == false)
    #expect(vm.error == nil)
}

@MainActor
@Test func directoryForNewEntryResolvesFromSelection() async throws {
    let (_, vm) = try await makeVM()
    #expect(vm.directoryForNewEntry(selection: nil) == "docs")
    #expect(vm.directoryForNewEntry(selection: "docs/features") == "docs/features")     // directory selected
    #expect(vm.directoryForNewEntry(selection: "docs/idea.md") == "docs")               // file -> its parent
}

@Test func remapAfterRenameHandlesSelfAndDescendants() {
    #expect(DocsTreeViewModel.remapAfterRename(selection: "docs/idea.md", from: "docs/idea.md", to: "docs/concept.md") == "docs/concept.md")
    #expect(DocsTreeViewModel.remapAfterRename(selection: "docs/features/brief.md", from: "docs/features", to: "docs/specs") == "docs/specs/brief.md")
    #expect(DocsTreeViewModel.remapAfterRename(selection: "docs/other.md", from: "docs/features", to: "docs/specs") == "docs/other.md")
    #expect(DocsTreeViewModel.remapAfterRename(selection: nil, from: "a", to: "b") == nil)
}

@Test func remapAfterDeleteClearsSelfAndDescendants() {
    #expect(DocsTreeViewModel.remapAfterDelete(selection: "docs/idea.md", deleted: "docs/idea.md") == nil)
    #expect(DocsTreeViewModel.remapAfterDelete(selection: "docs/features/brief.md", deleted: "docs/features") == nil)
    #expect(DocsTreeViewModel.remapAfterDelete(selection: "docs/other.md", deleted: "docs/features") == "docs/other.md")
}
