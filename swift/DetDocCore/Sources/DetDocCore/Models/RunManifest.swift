public struct RunManifest: Codable, Sendable, Equatable {
    public var runId: String
    public var mode: RunMode
    public var baseCommit: String
    public var approvedTargets: [String]
    public var preImageHashes: [String: String]

    public init(
        runId: String,
        mode: RunMode,
        baseCommit: String,
        approvedTargets: [String] = [],
        preImageHashes: [String: String] = [:]
    ) {
        self.runId = runId
        self.mode = mode
        self.baseCommit = baseCommit
        self.approvedTargets = approvedTargets
        self.preImageHashes = preImageHashes
    }

    enum CodingKeys: String, CodingKey { case runId, mode, baseCommit, approvedTargets, preImageHashes }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.runId = try c.decode(String.self, forKey: .runId)
        self.mode = try c.decode(RunMode.self, forKey: .mode)
        self.baseCommit = try c.decode(String.self, forKey: .baseCommit)
        self.approvedTargets = try c.decodeIfPresent([String].self, forKey: .approvedTargets) ?? []
        self.preImageHashes = try c.decodeIfPresent([String: String].self, forKey: .preImageHashes) ?? [:]
    }
}
