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

@Test func noAgentEndErrorIncludesDiagnosticsAndLastEvent() async {
    // pi emits an error event then exits without agent_end; the runner must surface the
    // transport diagnostics (exit status + stderr) and the last stdout line it saw.
    let transport = FakePiTransport(
        scriptLines: ["{\"type\":\"response\",\"command\":\"prompt\",\"success\":true}",
                      "{\"type\":\"error\",\"message\":\"rate limited\"}"],
        diagnostics: "pi exited with status 1\npi stderr: quota exceeded")
    let runner = PiAgentRunner(executable: "pi") { _, _, _ in transport }
    await #expect {
        _ = try await runner.plan(PlanRequest(mode: .run, input: "x", config: .default, cwd: URL(fileURLWithPath: "/tmp")))
    } throws: { error in
        guard let e = error as? DetDocError, e.code == "PI_RPC_NO_RESULT" else { return false }
        return e.message.contains("status 1")
            && e.message.contains("quota exceeded")
            && e.message.contains("rate limited")
    }
}

@Test func processTransportFlushesUnterminatedFinalRecordOnEOF() async throws {
    // pi's last write (agent_end) can reach EOF without a trailing newline; the transport
    // must still deliver that record instead of dropping it (which caused PI_RPC_NO_RESULT).
    let line = "{\"type\":\"agent_end\",\"messages\":[]}"
    let transport = try PiProcessTransport(executable: "printf", arguments: ["%s", line],
                                           cwd: URL(fileURLWithPath: "/tmp"))
    var received: [String] = []
    for try await record in transport.events() { received.append(record) }
    #expect(received == [line])
}

@Test func processTransportDiagnosticsReportExitStatusAndStderr() async throws {
    let transport = try PiProcessTransport(executable: "sh", arguments: ["-c", "echo boom >&2; exit 3"],
                                           cwd: URL(fileURLWithPath: "/tmp"))
    for try await _ in transport.events() {}  // drain to EOF
    await transport.finish()
    let diag = await transport.diagnostics()
    #expect(diag.contains("status 3"))
    #expect(diag.contains("boom"))
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

private func approvedPlan() -> ProposedPlan {
    ProposedPlan(summary: "S", changes: [PlanChange(reason: "doc-diff:docs/a.md:L1", targetFiles: ["src/app.swift"], kind: "modify", rationale: "r")], risk: "low")
}

@Test func implementSendsImplementationPromptAndReportsProgress() async throws {
    let script = [
        "{\"type\":\"response\",\"command\":\"prompt\",\"success\":true}",
        "{\"type\":\"tool_execution_start\",\"toolName\":\"write\",\"args\":{\"path\":\"src/app.swift\"}}",
        "{\"type\":\"tool_execution_start\",\"toolName\":\"bash\",\"args\":{\"command\":\"swift build\"}}",
        try agentEndLine(planJSON: "{}", input: 1, output: 1),
    ]
    let transport = FakePiTransport(scriptLines: script)
    let progress = ProgressBox()
    let runner = PiAgentRunner(executable: "pi") { _, args, _ in
        #expect(args.contains("read,grep,find,ls,bash,edit,write"))  // implementation tool set
        return transport
    }
    let request = ImplementRequest(mode: .run, input: "IN", config: .default, cwd: URL(fileURLWithPath: "/tmp"),
                                   approvedPlan: approvedPlan(), approvedTargets: ["src/app.swift"],
                                   progress: { progress.append($0) })
    let result = try await runner.implement(request)

    #expect(result.usage.input == 1)
    #expect(transport.sentLines.contains { $0.contains("DetDoc implementation phase") })
    #expect(progress.events.contains { if case .write(let p) = $0 { return p == "src/app.swift" } else { return false } })
    #expect(progress.events.contains { if case .bash(let c) = $0 { return c == "swift build" } else { return false } })
}

@Test func repairValidationSendsRepairPrompt() async throws {
    let transport = FakePiTransport(scriptLines: [
        "{\"type\":\"response\",\"command\":\"prompt\",\"success\":true}",
        "{\"type\":\"agent_end\",\"messages\":[]}",
    ])
    let runner = PiAgentRunner(executable: "pi") { _, _, _ in transport }
    let base = ImplementRequest(mode: .run, input: "IN", config: .default, cwd: URL(fileURLWithPath: "/tmp"),
                                approvedPlan: approvedPlan(), approvedTargets: ["src/app.swift"], progress: nil)
    _ = try await runner.repairValidation(RepairRequest(base: base, validationLog: "FAILED: grep", attempt: 1))
    #expect(transport.sentLines.contains { $0.contains("DetDoc validation repair phase") })
    #expect(transport.sentLines.contains { $0.contains("FAILED: grep") })
}
