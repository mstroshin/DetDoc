import Testing
@testable import DetDocCore

@Test func globStarStarMatchesAcrossAndZeroDirectories() {
    #expect(Glob("**/*.md").matches("a.md"))
    #expect(Glob("**/*.md").matches("docs/x/a.md"))
    #expect(!Glob("**/*.md").matches("a.txt"))
}

@Test func globSingleStarDoesNotCrossSlash() {
    #expect(Glob("*.md").matches("a.md"))
    #expect(!Glob("*.md").matches("docs/a.md"))
}

@Test func globDirectorySuffixMatchesDescendants() {
    #expect(Glob(".detdoc/**").matches(".detdoc/config.yml"))
    #expect(Glob("node_modules/**").matches("node_modules/x/y.js"))
    #expect(!Glob("node_modules/**").matches("node_modules"))
}

@Test func globDotStarMatchesDottedSuffix() {
    #expect(Glob(".env.*").matches(".env.local"))
    #expect(!Glob(".env.*").matches(".env"))
    #expect(Glob(".env").matches(".env"))
}

@Test func globMatchesAnyAndInvalidNeverMatches() {
    #expect(Glob.matchesAny("src/a.ts", patterns: ["docs/**", "src/*.ts"]))
    #expect(!Glob.matchesAny("README", patterns: ["docs/**", "src/*.ts"]))
    #expect(!Glob("[").matches("anything"))
}
