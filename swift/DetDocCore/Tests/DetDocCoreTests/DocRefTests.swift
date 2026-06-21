import Foundation
import Testing
@testable import DetDocCore

@Test func scanFindsTokenAtStart() {
    let refs = DocRefScanner.scan("@a")
    #expect(refs.count == 1)
    #expect(refs[0].path == "a")
    #expect(refs[0].range == NSRange(location: 0, length: 2))
}

@Test func scanFindsTokenAfterSpace() {
    let s = "see @guides/setup x"
    let refs = DocRefScanner.scan(s)
    #expect(refs.count == 1)
    #expect(refs[0].path == "guides/setup")
    // range covers "@guides/setup" = 13 chars starting at offset 4
    #expect(refs[0].range == NSRange(location: 4, length: 13))
}

@Test func scanIgnoresAtNotAtWordBoundary() {
    let refs = DocRefScanner.scan("a@b")
    #expect(refs.isEmpty)
}

@Test func scanFindsMultipleTokens() {
    let refs = DocRefScanner.scan("@foo and @bar/baz")
    #expect(refs.count == 2)
    #expect(refs[0].path == "foo")
    #expect(refs[1].path == "bar/baz")
}

@Test func scanHandlesPathChars() {
    let refs = DocRefScanner.scan("@a-b/c_d.e")
    #expect(refs.count == 1)
    #expect(refs[0].path == "a-b/c_d.e")
}

@Test func scanBareAtAloneProducesNoToken() {
    let refs = DocRefScanner.scan("@ foo")
    #expect(refs.isEmpty)
}

@Test func scanCyrillicAfterSpaceTriggersToken() {
    // Cyrillic letters match \p{L} so "@страница" at start should be found
    let refs = DocRefScanner.scan(" @страница")
    #expect(refs.count == 1)
    #expect(refs[0].path == "страница")
}
