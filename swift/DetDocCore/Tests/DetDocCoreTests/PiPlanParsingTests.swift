import Foundation
import Testing
@testable import DetDocCore

@Test func parsesPlainPlanJSON() throws {
    let text = "{\"summary\":\"S\",\"changes\":[{\"reason\":\"doc-diff:docs/a.md:L1\",\"targetFiles\":[\"src/a.swift\"],\"kind\":\"modify\",\"rationale\":\"r\"}],\"questions\":[],\"risk\":\"low\"}"
    let plan = try PiPlanParsing.parsePlan(fromAssistantText: text)
    #expect(plan.summary == "S")
    #expect(plan.changes.first?.targetFiles == ["src/a.swift"])
}

@Test func parsesPlanJSONWrappedInProseAndFences() throws {
    let text = "Here is the plan:\n```json\n{\"summary\":\"S\",\"changes\":[{\"reason\":\"intent:fix\",\"targetFiles\":[\"src/a.swift\"],\"kind\":\"modify\",\"rationale\":\"r\"}],\"risk\":\"low\"}\n```\n"
    let plan = try PiPlanParsing.parsePlan(fromAssistantText: text)
    #expect(plan.risk == "low")
    #expect(plan.questions == [])  // ProposedPlan defaults questions
}

@Test func parsePlanThrowsForNonJSON() {
    #expect(throws: DetDocError.self) { _ = try PiPlanParsing.parsePlan(fromAssistantText: "no json here") }
}

@Test func lastAssistantTextPicksLatestAssistant() {
    let messages = [
        PiRpcMessage(role: "user", text: "u", usage: nil),
        PiRpcMessage(role: "assistant", text: "first", usage: nil),
        PiRpcMessage(role: "assistant", text: "second", usage: nil),
    ]
    #expect(PiPlanParsing.lastAssistantText(messages) == "second")
}

@Test func tokenUsageSumsAssistantMessagesAndComputesTotal() {
    let messages = [
        PiRpcMessage(role: "assistant", text: "", usage: PiRpcUsage(input: 10, output: 5, cacheRead: 1, cacheWrite: 2)),
        PiRpcMessage(role: "user", text: "", usage: nil),
        PiRpcMessage(role: "assistant", text: "", usage: PiRpcUsage(input: 3, output: 4, cacheRead: 0, cacheWrite: 0)),
    ]
    let usage = PiPlanParsing.tokenUsage(messages)
    #expect(usage.input == 13)
    #expect(usage.output == 9)
    #expect(usage.cacheRead == 1)
    #expect(usage.cacheWrite == 2)
    #expect(usage.total == 13 + 9 + 1 + 2)
}
