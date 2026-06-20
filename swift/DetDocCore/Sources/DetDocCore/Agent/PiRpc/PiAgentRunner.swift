import Foundation

/// `AgentRunner` that drives the installed `pi` binary as a subprocess over JSONL.
/// Pure logic is in PiRpcCodec/PiRpcEvent/PiAgentPrompts/PiPlanParsing; I/O is in the
/// injected `PiRpcTransport` (default: a live `pi --mode rpc` process).
public struct PiAgentRunner: AgentRunner {
    public typealias TransportFactory =
        @Sendable (_ executable: String, _ args: [String], _ cwd: URL) throws -> any PiRpcTransport

    let executable: String
    let makeTransport: TransportFactory

    public init(executable: String = "pi",
                makeTransport: @escaping TransportFactory = { executable, args, cwd in
                    try PiProcessTransport(executable: executable, arguments: args, cwd: cwd)
                }) {
        self.executable = executable
        self.makeTransport = makeTransport
    }

    public var supportsRepair: Bool { true }

    static let planningTools = ["read", "grep", "find", "ls"]
    static let implementationTools = ["read", "grep", "find", "ls", "bash", "edit", "write"]

    public func plan(_ request: PlanRequest) async throws -> AgentPlanResult {
        let args = Self.spawnArgs(model: request.config.agent.model, tools: Self.planningTools)
        let transport = try makeTransport(executable, args, request.cwd)
        let messages = try await drive(transport,
                                       thinking: request.config.agent.thinking,
                                       prompt: PiAgentPrompts.planningPrompt(request),
                                       progress: nil)
        let plan = try PiPlanParsing.parsePlan(fromAssistantText: PiPlanParsing.lastAssistantText(messages))
        return AgentPlanResult(plan: plan, usage: PiPlanParsing.tokenUsage(messages))
    }

    public func implement(_ request: ImplementRequest) async throws -> AgentRunResult {
        AgentRunResult()
    }

    static func spawnArgs(model: String?, tools: [String]) -> [String] {
        var args = ["--mode", "rpc", "--no-session", "--tools", tools.joined(separator: ",")]
        if let model, !model.isEmpty { args += ["--model", model] }
        return args
    }

    /// Send the thinking level + prompt, then consume events until `agent_end`, returning that
    /// event's messages. Maps `tool_execution_start` → `progress` when a callback is supplied.
    func drive(_ transport: any PiRpcTransport,
               thinking: String,
               prompt: String,
               progress: (@Sendable (AgentImplementationProgress) -> Void)?) async throws -> [PiRpcMessage] {
        let stream = transport.events()
        try await transport.send(PiRpcCodec.encode(SetThinkingLevelCommand(level: thinking)))
        try await transport.send(PiRpcCodec.encode(PromptCommand(message: prompt)))

        var messages: [PiRpcMessage]?
        do {
            for try await line in stream {
                switch try PiRpcEvent.decode(line) {
                case .response(let command, let success, let error):
                    if command == "prompt" && !success {
                        throw DetDocError("PI_RPC_COMMAND_FAILED", "pi rejected the prompt: \(error ?? "unknown error")")
                    }
                case .toolExecutionStart(let toolName, let path, let command):
                    if let progress {
                        Self.emitProgress(toolName: toolName, path: path, command: command, progress: progress)
                    }
                case .agentEnd(let endMessages):
                    messages = endMessages
                case .other:
                    break
                }
                if messages != nil { break }
            }
        } catch {
            await transport.finish()
            throw error
        }
        await transport.finish()
        guard let messages else {
            throw DetDocError("PI_RPC_NO_RESULT", "pi ended without an agent_end event")
        }
        return messages
    }

    static func emitProgress(toolName: String, path: String?, command: String?,
                             progress: @Sendable (AgentImplementationProgress) -> Void) {
        switch toolName {
        case "edit": if let path { progress(.edit(path: path)) }
        case "write": if let path { progress(.write(path: path)) }
        case "bash": if let command { progress(.bash(command: command)) }
        default: break
        }
    }
}

struct SetThinkingLevelCommand: Encodable {
    let type = "set_thinking_level"
    let level: String
}

struct PromptCommand: Encodable {
    let type = "prompt"
    let message: String
}
