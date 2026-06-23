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
