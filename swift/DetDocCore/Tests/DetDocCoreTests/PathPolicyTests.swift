import Testing
@testable import DetDocCore

@Test func deniedPathsMatchDenyGlobs() {
    let policy = PathPolicy(config: .default)
    #expect(policy.isDenied(".env"))
    #expect(policy.isDenied(".env.local"))
    #expect(policy.isDenied("node_modules/react/index.js"))
    #expect(policy.isDenied(".git/config"))
    #expect(!policy.isDenied("src/app.ts"))
}

@Test func docPathsAreIncludedAndNotExcluded() {
    let policy = PathPolicy(config: .default)
    #expect(policy.isDoc("docs/idea.md"))
    #expect(policy.isDoc("README.md"))
    #expect(!policy.isDoc(".detdoc/notes.md"))    // excluded by .detdoc/**
    #expect(!policy.isDoc("src/app.ts"))           // not a .md
    #expect(!policy.isDoc(".detdoc/config.yml"))   // not a .md, allowed as a target
}
