import Foundation
import Testing
@testable import DetDocCore

@Test func processTransportDrivesPlanThroughFakePi() async throws {
    let script = try #require(Bundle.module.url(forResource: "fake-pi", withExtension: "sh"))
    // Spawn the fake via bash so the resource's executable bit doesn't matter.
    let runner = PiAgentRunner(executable: "bash") { _, _, cwd in
        try PiProcessTransport(executable: "bash", arguments: [script.path], cwd: cwd)
    }
    let result = try await runner.plan(PlanRequest(mode: .run, input: "DIFF", config: .default,
                                                   cwd: FileManager.default.temporaryDirectory))
    #expect(result.plan.summary == "Fake plan")
    #expect(result.plan.changes.first?.targetFiles == ["src/app.swift"])
    #expect(result.usage.input == 10)
    #expect(result.usage.total == 15)
}
