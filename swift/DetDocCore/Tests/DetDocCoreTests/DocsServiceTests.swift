import Foundation
import Testing
@testable import DetDocCore

private func docsService() -> (TempDir, DocsService) {
    let tmp = TempDir()
    return (tmp, DocsService(root: tmp.url, config: .default))
}

@Test func listReturnsOnlyMarkdownDocsSorted() throws {
    let (tmp, svc) = docsService()
    try FileManager.default.createDirectory(at: tmp.url.appendingPathComponent("docs/sub"), withIntermediateDirectories: true)
    try "a".write(to: tmp.url.appendingPathComponent("docs/b.md"), atomically: true, encoding: .utf8)
    try "a".write(to: tmp.url.appendingPathComponent("docs/sub/a.md"), atomically: true, encoding: .utf8)
    try "a".write(to: tmp.url.appendingPathComponent("docs/notes.txt"), atomically: true, encoding: .utf8)
    let docs = svc.list()
    #expect(docs.map(\.path) == ["docs/b.md", "docs/sub/a.md"])
    #expect(docs.first?.title == "b")
}

@Test func writeReadCreateRenameDelete() throws {
    let (_, svc) = docsService()
    try svc.create("docs/x.md", "# X\n")
    #expect(try svc.read("docs/x.md") == "# X\n")
    #expect(throws: DetDocError.self) { try svc.create("docs/x.md", "dup") }
    try svc.write("docs/x.md", "# X2\n")
    #expect(try svc.read("docs/x.md") == "# X2\n")
    try svc.rename("docs/x.md", to: "docs/y.md")
    #expect(svc.list().map(\.path) == ["docs/y.md"])
    try svc.delete("docs/y.md")
    #expect(svc.list().isEmpty)
}

@Test func listDirectoriesReturnsSubdirsSorted() throws {
    let (tmp, svc) = docsService()
    try FileManager.default.createDirectory(at: tmp.url.appendingPathComponent("docs/b/c"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: tmp.url.appendingPathComponent("docs/a"), withIntermediateDirectories: true)
    try "x".write(to: tmp.url.appendingPathComponent("docs/a/f.md"), atomically: true, encoding: .utf8)
    #expect(svc.listDirectories() == ["docs/a", "docs/b", "docs/b/c"])
}

@Test func listDirectoriesEmptyWhenNoDocs() throws {
    let (_, svc) = docsService()
    #expect(svc.listDirectories().isEmpty)
}

@Test func createDirectoryMakesDirAndRejectsDuplicate() throws {
    let (tmp, svc) = docsService()
    try svc.createDirectory("docs/new")
    var isDir: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: tmp.url.appendingPathComponent("docs/new").path, isDirectory: &isDir))
    #expect(isDir.boolValue)
    #expect(throws: DetDocError.self) { try svc.createDirectory("docs/new") }
}

@Test func createDirectoryReportsWriteFailedWhenFileAtPath() throws {
    let (tmp, svc) = docsService()
    try FileManager.default.createDirectory(at: tmp.url.appendingPathComponent("docs"), withIntermediateDirectories: true)
    try "x".write(to: tmp.url.appendingPathComponent("docs/thing"), atomically: true, encoding: .utf8)
    var caughtError: DetDocError? = nil
    do {
        try svc.createDirectory("docs/thing")
    } catch let error as DetDocError {
        caughtError = error
    }
    let error = try #require(caughtError)
    #expect(error.code == "DOC_WRITE_FAILED")
}
