import Foundation
import Testing
@testable import DetDocCore

@Test func augmentedPathPrependsHomebrewDirsAndKeepsExistingAndOtherVars() {
    let env = SubprocessEnv.augmenting(["PATH": "/usr/bin:/bin", "HOME": "/x"])
    let path = env["PATH"]!
    #expect(path.hasPrefix("/opt/homebrew/bin:"))  // Homebrew first so pi/tuist resolve
    #expect(path.contains("/usr/bin"))             // inherited entries retained
    #expect(path.hasSuffix("/usr/bin:/bin"))
    #expect(env["HOME"] == "/x")                   // non-PATH vars preserved
}

@Test func augmentedPathDoesNotDuplicateDirsAlreadyPresent() {
    let env = SubprocessEnv.augmenting(["PATH": "/opt/homebrew/bin:/usr/bin"])
    #expect(env["PATH"]!.components(separatedBy: "/opt/homebrew/bin").count - 1 == 1)
}

@Test func augmentedPathFallsBackWhenNoPathSet() {
    let env = SubprocessEnv.augmenting([:])
    #expect(env["PATH"]!.contains("/opt/homebrew/bin"))
    #expect(env["PATH"]!.contains("/usr/bin"))  // sane default tail
}
