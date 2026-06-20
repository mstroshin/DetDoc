public enum RunMode: String, Codable, Sendable, Equatable {
    case run
    case fix
}

public struct DocFile: Codable, Sendable, Equatable {
    public var path: String
    public var title: String
    public init(path: String, title: String) {
        self.path = path
        self.title = title
    }
}

public struct DirtyFile: Codable, Sendable, Equatable {
    public var status: String
    public var path: String
    public init(status: String, path: String) {
        self.status = status
        self.path = path
    }
}

public struct ProjectStatus: Codable, Sendable, Equatable {
    public var root: String
    public var initialized: Bool
    public var piAvailable: Bool
    public var dirtyFiles: [DirtyFile]
    public init(root: String, initialized: Bool, piAvailable: Bool, dirtyFiles: [DirtyFile]) {
        self.root = root
        self.initialized = initialized
        self.piAvailable = piAvailable
        self.dirtyFiles = dirtyFiles
    }
}

public struct RunSummary: Codable, Sendable, Equatable {
    public var runId: String
    public var hasPatch: Bool
    public var approvedTargets: [String]
    public init(runId: String, hasPatch: Bool, approvedTargets: [String]) {
        self.runId = runId
        self.hasPatch = hasPatch
        self.approvedTargets = approvedTargets
    }
}

public struct RunFlowResult: Codable, Sendable, Equatable {
    public var runId: String
    public var applied: Bool
    public var patch: String
    public init(runId: String, applied: Bool, patch: String) {
        self.runId = runId
        self.applied = applied
        self.patch = patch
    }
}

public struct TokenUsage: Codable, Sendable, Equatable {
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite: Int
    public var total: Int
    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0, total: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.total = total
    }
}
