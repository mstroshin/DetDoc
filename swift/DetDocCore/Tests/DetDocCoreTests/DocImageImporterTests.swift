import Foundation
import Testing
@testable import DetDocCore

@Test func importFileCopiesAndReturnsTokenPath() throws {
    let tmp = TempDir()
    let importer = DocImageImporter(root: tmp.url)
    let src = tmp.url.appendingPathComponent("window.png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: src)

    let token = try importer.importFile(at: src, forDoc: "docs/guides/setup.md")
    #expect(token == "guides/assets/window.png")
    let dest = tmp.url.appendingPathComponent("docs/guides/assets/window.png")
    #expect(FileManager.default.fileExists(atPath: dest.path))
}

@Test func importFileDedupesOnCollision() throws {
    let tmp = TempDir()
    let importer = DocImageImporter(root: tmp.url)
    let src = tmp.url.appendingPathComponent("window.png")
    try Data([0x89]).write(to: src)

    let t1 = try importer.importFile(at: src, forDoc: "docs/guides/setup.md")
    let t2 = try importer.importFile(at: src, forDoc: "docs/guides/setup.md")
    #expect(t1 == "guides/assets/window.png")
    #expect(t2 == "guides/assets/window-1.png")
}

@Test func importFileForRootDocUsesDocsAssets() throws {
    let tmp = TempDir()
    let importer = DocImageImporter(root: tmp.url)
    let src = tmp.url.appendingPathComponent("a.png")
    try Data([0x89]).write(to: src)

    let token = try importer.importFile(at: src, forDoc: "docs/idea.md")
    #expect(token == "assets/a.png")
}

@Test func importDataWritesPng() throws {
    let tmp = TempDir()
    let importer = DocImageImporter(root: tmp.url)
    let token = try importer.importData(Data([0x89, 0x50]), basename: "image-20260621-143000",
                                        forDoc: "docs/features/auth/brief.md")
    #expect(token == "features/auth/assets/image-20260621-143000.png")
    let dest = tmp.url.appendingPathComponent("docs/features/auth/assets/image-20260621-143000.png")
    #expect(FileManager.default.fileExists(atPath: dest.path))
}

@Test func resolveReturnsURLWhenPresentNilWhenMissing() throws {
    let tmp = TempDir()
    let importer = DocImageImporter(root: tmp.url)
    #expect(importer.resolve("guides/assets/window.png") == nil)

    let src = tmp.url.appendingPathComponent("window.png")
    try Data([0x89]).write(to: src)
    let token = try importer.importFile(at: src, forDoc: "docs/guides/setup.md")
    let url = importer.resolve(token)
    #expect(url != nil)
    #expect(url?.lastPathComponent == "window.png")
}
