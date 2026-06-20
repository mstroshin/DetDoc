import Testing
@testable import DetDocCore

@Test func nonDocOffendersExcludeDocsDetdocAndGitignore() {
    let entries = [
        GitStatusEntry(status: " M", path: "docs/idea.md"),
        GitStatusEntry(status: " M", path: ".detdoc/config.yml"),
        GitStatusEntry(status: " M", path: ".gitignore"),
        GitStatusEntry(status: " M", path: "src/app.swift"),
    ]
    let offenders = DirtyPolicy.nonDocOffenders(entries, config: .default)
    #expect(offenders.map(\.path) == ["src/app.swift"])
}

@Test func assertCleanThrowsOnNonDocChanges() {
    let entries = [GitStatusEntry(status: " M", path: "src/app.swift")]
    #expect { try DirtyPolicy.assertClean(entries, config: .default, mode: .fix) }
        throws: { ($0 as? DetDocError)?.code == "DIRTY_NON_DOC_CHANGES" }
}
