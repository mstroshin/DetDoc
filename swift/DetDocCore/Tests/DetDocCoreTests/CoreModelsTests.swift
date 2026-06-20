import Foundation
import Testing
@testable import DetDocCore

@Test func runModeEncodesAsLowercaseRawValue() throws {
    let data = try JSONEncoder().encode([RunMode.run, RunMode.fix])
    #expect(String(decoding: data, as: UTF8.self) == #"["run","fix"]"#)
}

@Test func projectStatusRoundTripsThroughJSON() throws {
    let status = ProjectStatus(
        root: "/repo",
        initialized: true,
        piAvailable: false,
        dirtyFiles: [DirtyFile(status: " M", path: "docs/idea.md")]
    )
    let data = try JSONEncoder().encode(status)
    let decoded = try JSONDecoder().decode(ProjectStatus.self, from: data)
    #expect(decoded == status)
}
