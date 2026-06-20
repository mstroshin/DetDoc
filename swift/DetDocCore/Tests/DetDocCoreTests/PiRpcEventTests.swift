import Foundation
import Testing
@testable import DetDocCore

@Test func decodesAgentEndWithAssistantTextAndUsage() throws {
    let line = "{\"type\":\"agent_end\",\"messages\":[{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}],\"usage\":{\"input\":10,\"output\":5,\"cacheRead\":1,\"cacheWrite\":2}}]}"
    guard case .agentEnd(let messages) = try PiRpcEvent.decode(line) else {
        Issue.record("expected .agentEnd"); return
    }
    #expect(messages.count == 1)
    #expect(messages[0].role == "assistant")
    #expect(messages[0].text == "hi")
    #expect(messages[0].usage == PiRpcUsage(input: 10, output: 5, cacheRead: 1, cacheWrite: 2))
}

@Test func decodesStringContentMessages() throws {
    let line = "{\"type\":\"agent_end\",\"messages\":[{\"role\":\"assistant\",\"content\":\"plain\"}]}"
    guard case .agentEnd(let messages) = try PiRpcEvent.decode(line) else {
        Issue.record("expected .agentEnd"); return
    }
    #expect(messages[0].text == "plain")
    #expect(messages[0].usage == nil)
}

@Test func decodesPromptFailureResponse() throws {
    let event = try PiRpcEvent.decode("{\"type\":\"response\",\"command\":\"prompt\",\"success\":false,\"error\":\"boom\"}")
    #expect(event == .response(command: "prompt", success: false, error: "boom"))
}

@Test func decodesToolExecutionStart() throws {
    let event = try PiRpcEvent.decode("{\"type\":\"tool_execution_start\",\"toolName\":\"write\",\"args\":{\"path\":\"src/app.swift\"}}")
    #expect(event == .toolExecutionStart(toolName: "write", path: "src/app.swift", command: nil))
}

@Test func decodesUnknownEventAsOther() throws {
    #expect(try PiRpcEvent.decode("{\"type\":\"turn_start\"}") == .other(type: "turn_start"))
}
