import Foundation
import Testing
@testable import DetDocCore

@Test func validationRunnerConcatenatesCommandLogs() async throws {
    let log = try await ValidationRunner().run(
        commands: [ValidationCommand(name: "echo", run: "printf done")],
        cwd: FileManager.default.temporaryDirectory
    )
    #expect(log.contains("# echo"))
    #expect(log.contains("done"))
}

@Test func validationRunnerThrowsValidationFailedOnNonZeroExit() async throws {
    await #expect {
        _ = try await ValidationRunner().run(
            commands: [ValidationCommand(name: "boom", run: "exit 1")],
            cwd: FileManager.default.temporaryDirectory
        )
    } throws: { ($0 as? DetDocError)?.code == "VALIDATION_FAILED" }
}
