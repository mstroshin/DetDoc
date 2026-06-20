import Foundation
@testable import DetDocCore

/// Sendable box for capturing the spawn args passed to a transport factory.
final class ArgsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [String] = []
    func set(_ args: [String]) { lock.lock(); value = args; lock.unlock() }
    var args: [String] { lock.lock(); defer { lock.unlock() }; return value }
}

/// Sendable box for collecting implementation progress callbacks.
final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [AgentImplementationProgress] = []
    func append(_ event: AgentImplementationProgress) { lock.lock(); collected.append(event); lock.unlock() }
    var events: [AgentImplementationProgress] { lock.lock(); defer { lock.unlock() }; return collected }
}

/// Build an `agent_end` JSONL line whose single assistant message carries `planJSON` as text.
func agentEndLine(planJSON: String, input: Int = 0, output: Int = 0) throws -> String {
    let content = try PiRpcCodec.encode([["type": "text", "text": planJSON]])
    return "{\"type\":\"agent_end\",\"messages\":[{\"role\":\"assistant\",\"content\":\(content),\"usage\":{\"input\":\(input),\"output\":\(output),\"cacheRead\":0,\"cacheWrite\":0}}]}"
}
