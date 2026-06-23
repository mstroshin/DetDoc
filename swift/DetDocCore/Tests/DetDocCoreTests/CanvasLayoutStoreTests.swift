import Foundation
import Testing
@testable import DetDocCore

@Test func savesAndLoadsRoundTrip() {
    let tmp = TempDir()
    let store = CanvasLayoutStore(root: tmp.url)
    store.save(["a.md": DocGraphPoint(x: 12, y: -3.5)])
    #expect(store.load() == ["a.md": DocGraphPoint(x: 12, y: -3.5)])
}

@Test func loadMissingFileReturnsEmpty() {
    let tmp = TempDir()
    #expect(CanvasLayoutStore(root: tmp.url).load().isEmpty)
}

@Test func gitignoreCoversLayoutFile() {
    #expect(GitignoreManager.managedEntries.contains(".detdoc/canvas-layout.json"))
}

@Test func loadCorruptFileReturnsEmpty() throws {
    let tmp = TempDir()
    let store = CanvasLayoutStore(root: tmp.url)
    let dir = tmp.url.appendingPathComponent(".detdoc")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: dir.appendingPathComponent("canvas-layout.json"))
    #expect(store.load().isEmpty)
}
