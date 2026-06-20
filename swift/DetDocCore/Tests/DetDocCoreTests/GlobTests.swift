import Testing
@testable import DetDocCore

// Semantics match the Rust reference's globset defaults (literal_separator = false),
// empirically pinned against globset 0.4: `*` and `?` cross `/`; `**/` matches zero
// or more directory segments; a trailing `dir/**` requires the `dir/` prefix.

@Test func globStarStarMatchesAcrossAndZeroDirectories() {
    #expect(Glob("**/*.md").matches("a.md"))
    #expect(Glob("**/*.md").matches("docs/x/a.md"))
    #expect(!Glob("**/*.md").matches("a.txt"))
}

@Test func globSingleStarCrossesSlash() {
    // globset default: `*` matches across `/` (NOT picomatch/gitignore semantics).
    #expect(Glob("*.md").matches("a.md"))
    #expect(Glob("*.md").matches("docs/a.md"))
    #expect(Glob("*.md").matches("docs/deep/a.md"))
    #expect(!Glob("*.md").matches("a.txt"))
}

@Test func globQuestionMatchesAnySingleCharIncludingSlash() {
    // globset default: `?` matches any single character, including `/`.
    #expect(Glob("?.md").matches("a.md"))
    #expect(!Glob("?.md").matches("ab.md"))   // exactly one char before .md
    #expect(Glob("a?c").matches("abc"))
    #expect(Glob("a?c").matches("a/c"))        // `?` crosses `/`
}

@Test func globDirectorySuffixMatchesDescendants() {
    #expect(Glob(".detdoc/**").matches(".detdoc/config.yml"))
    #expect(Glob("node_modules/**").matches("node_modules/x/y.js"))
    #expect(!Glob("node_modules/**").matches("node_modules"))   // bare prefix not matched
}

@Test func globDotStarMatchesDottedSuffixAcrossSlash() {
    #expect(Glob(".env.*").matches(".env.local"))
    #expect(Glob(".env.*").matches(".env.config/leaked"))   // `*` crosses `/` (safety boundary)
    #expect(!Glob(".env.*").matches(".env"))
    #expect(Glob(".env").matches(".env"))
}

@Test func globMatchesGlobsetForCustomDenySafetyCases() {
    // A custom deny like `secrets/*` must block ALL descendants, matching the Rust deny check.
    #expect(Glob("secrets/*").matches("secrets/key.pem"))
    #expect(Glob("secrets/*").matches("secrets/sub/key.pem"))
}

@Test func globMatchesAnyAndInvalidNeverMatches() {
    #expect(Glob.matchesAny("src/a.ts", patterns: ["docs/**", "src/*.ts"]))
    #expect(!Glob.matchesAny("README", patterns: ["docs/**", "src/*.ts"]))
    #expect(!Glob("[").matches("anything"))
}
