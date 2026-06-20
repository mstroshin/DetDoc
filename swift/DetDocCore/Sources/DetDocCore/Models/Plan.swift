public struct PlanChange: Codable, Sendable, Equatable {
    public var reason: String
    public var targetFiles: [String]
    public var kind: String
    public var rationale: String
    public init(reason: String, targetFiles: [String], kind: String, rationale: String) {
        self.reason = reason
        self.targetFiles = targetFiles
        self.kind = kind
        self.rationale = rationale
    }
}

public struct ProposedPlan: Codable, Sendable, Equatable {
    public var summary: String
    public var changes: [PlanChange]
    public var questions: [String]
    public var risk: String

    public init(summary: String, changes: [PlanChange], questions: [String] = [], risk: String) {
        self.summary = summary
        self.changes = changes
        self.questions = questions
        self.risk = risk
    }

    enum CodingKeys: String, CodingKey { case summary, changes, questions, risk }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.summary = try c.decode(String.self, forKey: .summary)
        self.changes = try c.decode([PlanChange].self, forKey: .changes)
        self.questions = try c.decodeIfPresent([String].self, forKey: .questions) ?? []
        self.risk = try c.decode(String.self, forKey: .risk)
    }
}
