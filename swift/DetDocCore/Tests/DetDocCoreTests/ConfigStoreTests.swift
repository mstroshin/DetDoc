import Foundation
import Testing
@testable import DetDocCore

@Test func loadMissingConfigThrowsReadFailed() {
    let tmp = TempDir()
    #expect(throws: DetDocError.self) {
        try ConfigStore().load(root: tmp.url)
    }
}

@Test func initFilesWritesConfigGitkeepStarterDocsAndGitignore() throws {
    let tmp = TempDir()
    let store = ConfigStore()
    try store.initFiles(root: tmp.url)

    let fm = FileManager.default
    #expect(fm.fileExists(atPath: tmp.url.appendingPathComponent(".detdoc/config.yml").path))
    #expect(fm.fileExists(atPath: tmp.url.appendingPathComponent(".detdoc/runs/.gitkeep").path))
    #expect(fm.fileExists(atPath: tmp.url.appendingPathComponent("docs/idea.md").path))
    #expect(fm.fileExists(atPath: tmp.url.appendingPathComponent("docs/features/example-feature/brief.md").path))

    // config round-trips to defaults
    let loaded = try store.load(root: tmp.url)
    #expect(loaded == DetDocConfig.default)

    // gitignore contains the managed entries
    let gitignore = try String(contentsOf: tmp.url.appendingPathComponent(".gitignore"), encoding: .utf8)
    for entry in [".DS_Store", ".detdoc/runs/*", "!.detdoc/runs/.gitkeep", ".worktrees/"] {
        #expect(gitignore.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == entry })
    }
}

@Test func initFilesIsIdempotentAndPreservesEditedDocs() throws {
    let tmp = TempDir()
    let store = ConfigStore()
    try store.initFiles(root: tmp.url)
    let ideaURL = tmp.url.appendingPathComponent("docs/idea.md")
    try "EDITED".write(to: ideaURL, atomically: true, encoding: .utf8)

    try store.initFiles(root: tmp.url)  // second init must not overwrite
    let idea = try String(contentsOf: ideaURL, encoding: .utf8)
    #expect(idea == "EDITED")
}
