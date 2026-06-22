import Foundation

public enum AgentImplementationProgress: Sendable {
    case edit(path: String)
    case write(path: String)
    case bash(command: String)
}

public struct PlanRequest: Sendable {
    public let mode: RunMode
    public let input: String
    public let config: DetDocConfig
    public let cwd: URL
    public init(mode: RunMode, input: String, config: DetDocConfig, cwd: URL) {
        self.mode = mode; self.input = input; self.config = config; self.cwd = cwd
    }
}

public struct ImplementRequest: Sendable {
    public let mode: RunMode
    public let input: String
    public let config: DetDocConfig
    public let cwd: URL
    public let approvedPlan: ProposedPlan
    public let approvedTargets: [String]
    public let progress: (@Sendable (AgentImplementationProgress) -> Void)?
    public init(mode: RunMode, input: String, config: DetDocConfig, cwd: URL, approvedPlan: ProposedPlan, approvedTargets: [String], progress: (@Sendable (AgentImplementationProgress) -> Void)?) {
        self.mode = mode; self.input = input; self.config = config; self.cwd = cwd
        self.approvedPlan = approvedPlan; self.approvedTargets = approvedTargets; self.progress = progress
    }
}

public struct RepairRequest: Sendable {
    public let base: ImplementRequest
    public let validationLog: String
    public let attempt: Int
    public init(base: ImplementRequest, validationLog: String, attempt: Int) {
        self.base = base; self.validationLog = validationLog; self.attempt = attempt
    }
}

public struct AgentPlanResult: Sendable {
    public let plan: ProposedPlan
    public let usage: TokenUsage
    public init(plan: ProposedPlan, usage: TokenUsage = TokenUsage()) {
        self.plan = plan; self.usage = usage
    }
}

public struct AgentRunResult: Sendable {
    public let usage: TokenUsage
    public let codeLinks: [CodeLink]
    public init(usage: TokenUsage = TokenUsage(), codeLinks: [CodeLink] = []) {
        self.usage = usage
        self.codeLinks = codeLinks
    }
}

public protocol AgentRunner: Sendable {
    var supportsRepair: Bool { get }
    func plan(_ request: PlanRequest) async throws -> AgentPlanResult
    func implement(_ request: ImplementRequest) async throws -> AgentRunResult
    func repairValidation(_ request: RepairRequest) async throws -> AgentRunResult
}

public extension AgentRunner {
    var supportsRepair: Bool { false }
    func repairValidation(_ request: RepairRequest) async throws -> AgentRunResult { AgentRunResult() }
}

public extension TokenUsage {
    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            total: lhs.total + rhs.total
        )
    }
}
