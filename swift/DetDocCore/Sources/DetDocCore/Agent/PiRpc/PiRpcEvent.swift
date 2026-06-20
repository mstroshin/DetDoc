import Foundation

/// A minimal decoded view of the pi RPC event/response stream — only the fields DetDoc needs.
public enum PiRpcEvent: Sendable, Equatable {
    case agentEnd(messages: [PiRpcMessage])
    case toolExecutionStart(toolName: String, path: String?, command: String?)
    case response(command: String, success: Bool, error: String?)
    case other(type: String)

    public static func decode(_ line: String) throws -> PiRpcEvent {
        guard let data = line.data(using: .utf8) else {
            throw DetDocError("PI_RPC_UTF8_INVALID", "pi RPC line was not valid UTF-8")
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        switch envelope.type {
        case "agent_end":
            return .agentEnd(messages: envelope.messages ?? [])
        case "tool_execution_start":
            return .toolExecutionStart(toolName: envelope.toolName ?? "",
                                       path: envelope.args?.path,
                                       command: envelope.args?.command)
        case "response":
            return .response(command: envelope.command ?? "",
                             success: envelope.success ?? false,
                             error: envelope.error)
        default:
            return .other(type: envelope.type)
        }
    }

    private struct Envelope: Decodable {
        let type: String
        let messages: [PiRpcMessage]?
        let toolName: String?
        let args: ToolArgs?
        let command: String?
        let success: Bool?
        let error: String?
    }

    private struct ToolArgs: Decodable {
        let path: String?
        let command: String?
    }
}

/// An assistant/user/tool message as carried in `agent_end`. `content` (string or block array)
/// is flattened to concatenated text; only assistant `usage` is relevant to DetDoc.
public struct PiRpcMessage: Sendable, Equatable {
    public let role: String?
    public let text: String
    public let usage: PiRpcUsage?

    public init(role: String?, text: String, usage: PiRpcUsage?) {
        self.role = role
        self.text = text
        self.usage = usage
    }
}

extension PiRpcMessage: Decodable {
    enum CodingKeys: String, CodingKey { case role, content, usage }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        usage = try container.decodeIfPresent(PiRpcUsage.self, forKey: .usage)
        if let string = try? container.decode(String.self, forKey: .content) {
            text = string
        } else if let blocks = try? container.decode([ContentBlock].self, forKey: .content) {
            text = blocks.compactMap(\.text).joined()
        } else {
            text = ""
        }
    }

    private struct ContentBlock: Decodable {
        let type: String?
        let text: String?
    }
}

/// Token usage as reported on an assistant message's `usage` field (the wire has no `total`).
public struct PiRpcUsage: Sendable, Equatable {
    public let input: Int
    public let output: Int
    public let cacheRead: Int
    public let cacheWrite: Int

    public init(input: Int, output: Int, cacheRead: Int, cacheWrite: Int) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }
}

extension PiRpcUsage: Decodable {
    enum CodingKeys: String, CodingKey { case input, output, cacheRead, cacheWrite }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = try container.decodeIfPresent(Int.self, forKey: .input) ?? 0
        output = try container.decodeIfPresent(Int.self, forKey: .output) ?? 0
        cacheRead = try container.decodeIfPresent(Int.self, forKey: .cacheRead) ?? 0
        cacheWrite = try container.decodeIfPresent(Int.self, forKey: .cacheWrite) ?? 0
    }
}
