import Testing
@testable import DetDoc

@Test func buildEmptyInputReturnsEmpty() {
    #expect(DocTreeBuilder.build(files: [], directories: []).isEmpty)
}

@Test func buildNestsFilesUnderDocsRoot() throws {
    let nodes = DocTreeBuilder.build(
        files: ["docs/idea.md", "docs/features/_guide.md", "docs/features/x/brief.md"],
        directories: []
    )
    // Single "docs" root folder.
    #expect(nodes.count == 1)
    let docs = try #require(nodes.first)
    #expect(docs.id == "docs")
    #expect(docs.isDirectory)
    let docsChildren = try #require(docs.children)
    // Directory "features" sorts before file "idea.md".
    #expect(docsChildren.map(\.name) == ["features", "idea.md"])
    let features = try #require(docsChildren.first { $0.name == "features" })
    #expect(features.children?.map(\.name) == ["x", "_guide.md"])
    // Files are leaves.
    let idea = try #require(docsChildren.first { $0.name == "idea.md" })
    #expect(idea.isDirectory == false)
    #expect(idea.children == nil)
}

@Test func buildIncludesEmptyDirectories() throws {
    let nodes = DocTreeBuilder.build(files: ["docs/a.md"], directories: ["docs/empty"])
    let docs = try #require(nodes.first)
    let empty = try #require(docs.children?.first { $0.name == "empty" })
    #expect(empty.isDirectory)
    #expect(empty.children == [])
}

@Test func buildSortsCaseInsensitively() throws {
    let nodes = DocTreeBuilder.build(files: ["docs/Zebra.md", "docs/apple.md"], directories: [])
    let docs = try #require(nodes.first)
    #expect(docs.children?.map(\.name) == ["apple.md", "Zebra.md"])
}
