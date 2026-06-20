import Foundation
import Testing
@testable import DetDocCore

@Test func processRunnerCapturesStdoutAndStatus() async throws {
    let result = try await ProcessRunner.run("/bin/sh", ["-c", "printf hello"], cwd: FileManager.default.temporaryDirectory)
    #expect(result.status == 0)
    #expect(result.stdoutString == "hello")
}

@Test func processRunnerCapturesNonZeroStatusAndStderr() async throws {
    let result = try await ProcessRunner.run("/bin/sh", ["-c", "printf oops 1>&2; exit 3"], cwd: FileManager.default.temporaryDirectory)
    #expect(result.status == 3)
    #expect(result.stderrString == "oops")
}

@Test func processRunnerWritesStdin() async throws {
    let result = try await ProcessRunner.run("/bin/sh", ["-c", "cat"], cwd: FileManager.default.temporaryDirectory, stdin: "piped")
    #expect(result.stdoutString == "piped")
}
