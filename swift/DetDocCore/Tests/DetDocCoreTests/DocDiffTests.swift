import Foundation
import Testing
@testable import DetDocCore

@Test func normalizedDocDiffReturnsDocChangesAndIncludesUntracked() async throws {
    let fx = try await GitFixture()
    try fx.write("docs/idea.md", "old\n")
    try await fx.commitAll("init")
    try fx.write("docs/idea.md", "new line\n")       // tracked-modified doc
    try fx.write("docs/extra.md", "brand new\n")     // untracked doc
    let diff = try await DocDiff.normalized(fx.repo, config: .default)
    #expect(diff.contains("docs/idea.md"))
    #expect(diff.contains("docs/extra.md"))           // untracked picked up via add -N
}

@Test func normalizedDocDiffRejectsDirtyNonDoc() async throws {
    let fx = try await GitFixture()
    try fx.write("docs/idea.md", "x\n")
    try await fx.commitAll("init")
    try fx.write("src/app.swift", "code\n")
    await #expect { _ = try await DocDiff.normalized(fx.repo, config: .default) }
        throws: { ($0 as? DetDocError)?.code == "DIRTY_NON_DOC_CHANGES" }
}

@Test func normalizedDocDiffRequiresDocChanges() async throws {
    let fx = try await GitFixture()
    try fx.write("docs/idea.md", "x\n")
    try await fx.commitAll("init")
    await #expect { _ = try await DocDiff.normalized(fx.repo, config: .default) }
        throws: { ($0 as? DetDocError)?.code == "NO_DOC_CHANGES" }
}
