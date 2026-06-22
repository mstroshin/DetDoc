import Foundation
import Testing
@testable import DetDocCore

private func seedDocs() throws -> TempDir {
    let tmp = TempDir()
    try FileManager.default.createDirectory(at: tmp.url.appendingPathComponent("docs"), withIntermediateDirectories: true)
    try "intro\nSet a hard Deadline here\ntail".write(to: tmp.url.appendingPathComponent("docs/a.md"), atomically: true, encoding: .utf8)
    try "no match\nanother DEADLINE line".write(to: tmp.url.appendingPathComponent("docs/b.md"), atomically: true, encoding: .utf8)
    return tmp
}

@Test func contentSearchFindsLineMatchesCaseInsensitively() throws {
    let tmp = try seedDocs()
    let hits = DocSearch(root: tmp.url, config: .default).content(query: "deadline")
    #expect(hits.count == 2)
    #expect(hits.contains { $0.path == "docs/a.md" && $0.line == 2 })
    #expect(hits.contains { $0.path == "docs/b.md" && $0.line == 2 })
}

@Test func contentSearchIgnoresShortQueries() throws {
    let tmp = try seedDocs()
    #expect(DocSearch(root: tmp.url, config: .default).content(query: "d").isEmpty)
}
