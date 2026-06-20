import Foundation

public struct TouchedFile: Codable, Sendable, Equatable {
    public var path: String
    public var before: String?
    public var after: String?
    public init(path: String, before: String?, after: String?) {
        self.path = path; self.before = before; self.after = after
    }
}

public struct RunManifest: Codable, Sendable, Equatable {
    public var runId: String
    public var mode: RunMode
    public var baseCommit: String
    public var approvedTargets: [String]
    public var touchedFiles: [TouchedFile]

    public init(runId: String, mode: RunMode, baseCommit: String, approvedTargets: [String] = [], touchedFiles: [TouchedFile] = []) {
        self.runId = runId; self.mode = mode; self.baseCommit = baseCommit
        self.approvedTargets = approvedTargets; self.touchedFiles = touchedFiles
    }

    enum CodingKeys: String, CodingKey { case runId, mode, baseCommit, approvedTargets, touchedFiles }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.runId = try c.decode(String.self, forKey: .runId)
        self.mode = try c.decode(RunMode.self, forKey: .mode)
        self.baseCommit = try c.decode(String.self, forKey: .baseCommit)
        self.approvedTargets = try c.decodeIfPresent([String].self, forKey: .approvedTargets) ?? []
        self.touchedFiles = try c.decodeIfPresent([TouchedFile].self, forKey: .touchedFiles) ?? []
    }

    public static func initial(mode: RunMode, baseCommit: String, now: Date = Date(), uuid: UUID = UUID()) -> RunManifest {
        RunManifest(runId: RunID.create(mode: mode, now: now, uuid: uuid), mode: mode, baseCommit: baseCommit)
    }
}
