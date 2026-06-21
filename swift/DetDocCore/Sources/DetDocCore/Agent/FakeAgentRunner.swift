import Foundation

public struct FakeAgentRunner: AgentRunner {
    private let target: String
    private let content: String

    public init(target: String, content: String) {
        self.target = target
        self.content = content
    }

    public var supportsRepair: Bool { true }

    public func plan(_ request: PlanRequest) async throws -> AgentPlanResult {
        let reason = request.mode == .run ? "doc-diff:docs/technical-spec.md:L1-L2" : "intent:fix"
        let change = PlanChange(reason: reason, targetFiles: [target], kind: "modify", rationale: "Fake agent writes target")
        return AgentPlanResult(plan: ProposedPlan(summary: "Fake plan", changes: [change], risk: "low"))
    }

    public func implement(_ request: ImplementRequest) async throws -> AgentRunResult {
        guard request.approvedTargets.contains(target) else {
            throw DetDocError("FAKE_UNAPPROVED_WRITE", "FakeAgentRunner attempted unapproved write: \(target)")
        }
        try writeTarget(into: request.cwd)
        request.progress?(.write(path: target))
        return AgentRunResult()
    }

    public func repairValidation(_ request: RepairRequest) async throws -> AgentRunResult {
        try writeTarget(into: request.base.cwd)
        return AgentRunResult()
    }

    private func writeTarget(into cwd: URL) throws {
        let url = cwd.appendingPathComponent(target)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
