import Foundation

/// Extracts the structured plan and token usage from pi's `agent_end` messages.
/// Ports `extractLastAssistantText` / `extractSessionTokenUsage` from the TS reference.
public enum PiPlanParsing {
    /// Decode the plan JSON object embedded in the agent's final assistant text. Tolerant of
    /// surrounding prose / code fences: slices from the first `{` to the last `}`.
    public static func parsePlan(fromAssistantText text: String) throws -> ProposedPlan {
        let json = extractJSONObject(from: text)
        guard let data = json.data(using: .utf8) else {
            throw DetDocError("PI_PLAN_PARSE_FAILED", "pi plan output was not valid UTF-8")
        }
        do {
            return try JSONDecoder().decode(ProposedPlan.self, from: data)
        } catch {
            throw DetDocError("PI_PLAN_PARSE_FAILED", "pi did not return a valid plan JSON object: \(error)")
        }
    }

    /// The concatenated text of the most recent assistant message (empty if none).
    public static func lastAssistantText(_ messages: [PiRpcMessage]) -> String {
        for message in messages.reversed() where message.role == "assistant" {
            return message.text
        }
        return ""
    }

    /// Sum token usage across assistant messages; `total` is computed (the wire has no total).
    public static func tokenUsage(_ messages: [PiRpcMessage]) -> TokenUsage {
        var input = 0, output = 0, cacheRead = 0, cacheWrite = 0
        for message in messages where message.role == "assistant" {
            guard let usage = message.usage else { continue }
            input += usage.input
            output += usage.output
            cacheRead += usage.cacheRead
            cacheWrite += usage.cacheWrite
        }
        return TokenUsage(input: input, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite,
                          total: input + output + cacheRead + cacheWrite)
    }

    /// Return the substring from the first `{` to the last `}`, trimming surrounding text.
    static func extractJSONObject(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let open = trimmed.firstIndex(of: "{"),
              let close = trimmed.lastIndex(of: "}"),
              open <= close else {
            return trimmed
        }
        return String(trimmed[open...close])
    }
}
