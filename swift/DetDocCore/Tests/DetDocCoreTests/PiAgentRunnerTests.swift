import Foundation
import Testing
@testable import DetDocCore

private let planJSON = "{\"summary\":\"S\",\"changes\":[{\"reason\":\"doc-diff:docs/a.md:L1\",\"targetFiles\":[\"src/app.swift\"],\"kind\":\"modify\",\"rationale\":\"r\"}],\"questions\":[],\"risk\":\"low\"}"

@Test func planSendsThinkingThenPromptAndReturnsParsedPlan() async throws {
    let script = [
        "{\"type\":\"response\",\"command\":\"set_thinking_level\",\"success\":true}",
        "{\"type\":\"response\",\"command\":\"prompt\",\"success\":true}",
        "{\"type\":\"agent_start\"}",
        try agentEndLine(planJSON: planJSON, input: 10, output: 5),
    ]
    let transport = FakePiTransport(scriptLines: script)
    let argsBox = ArgsBox()
    let runner = PiAgentRunner(executable: "pi") { _, args, _ in argsBox.set(args); return transport }

    let result = try await runner.plan(PlanRequest(mode: .run, input: "DIFF", config: .default, cwd: URL(fileURLWithPath: "/tmp")))

    #expect(result.plan.summary == "S")
    #expect(result.plan.changes.first?.targetFiles == ["src/app.swift"])
    #expect(result.usage.input == 10)
    #expect(result.usage.total == 15)
    #expect(transport.sentLines.contains { $0.contains("\"type\":\"set_thinking_level\"") })
    #expect(transport.sentLines.contains { $0.contains("\"type\":\"prompt\"") })
    #expect(argsBox.args.contains("--mode"))
    #expect(argsBox.args.contains("rpc"))
    #expect(argsBox.args.contains("--no-session"))
    #expect(argsBox.args.contains("read,grep,find,ls"))  // planning tool set
}

@Test func planThrowsWhenPromptRejected() async {
    let script = ["{\"type\":\"response\",\"command\":\"prompt\",\"success\":false,\"error\":\"bad\"}"]
    let transport = FakePiTransport(scriptLines: script)
    let runner = PiAgentRunner(executable: "pi") { _, _, _ in transport }
    await #expect {
        _ = try await runner.plan(PlanRequest(mode: .run, input: "x", config: .default, cwd: URL(fileURLWithPath: "/tmp")))
    } throws: { ($0 as? DetDocError)?.code == "PI_RPC_COMMAND_FAILED" }
}

@Test func planThrowsWhenNoAgentEnd() async {
    let script = ["{\"type\":\"response\",\"command\":\"prompt\",\"success\":true}", "{\"type\":\"agent_start\"}"]
    let transport = FakePiTransport(scriptLines: script)
    let runner = PiAgentRunner(executable: "pi") { _, _, _ in transport }
    await #expect {
        _ = try await runner.plan(PlanRequest(mode: .run, input: "x", config: .default, cwd: URL(fileURLWithPath: "/tmp")))
    } throws: { ($0 as? DetDocError)?.code == "PI_RPC_NO_RESULT" }
}

@Test func passesModelArgWhenConfigured() async throws {
    var config = DetDocConfig.default
    config.agent.model = "anthropic/claude-opus"
    let transport = FakePiTransport(scriptLines: [
        "{\"type\":\"response\",\"command\":\"prompt\",\"success\":true}",
        try agentEndLine(planJSON: planJSON),
    ])
    let argsBox = ArgsBox()
    let runner = PiAgentRunner(executable: "pi") { _, args, _ in argsBox.set(args); return transport }
    _ = try await runner.plan(PlanRequest(mode: .run, input: "x", config: config, cwd: URL(fileURLWithPath: "/tmp")))
    #expect(argsBox.args.contains("--model"))
    #expect(argsBox.args.contains("anthropic/claude-opus"))
}
