public struct DocsConfig: Codable, Sendable, Equatable {
    public var include: [String]
    public var exclude: [String]
    public init(include: [String], exclude: [String]) {
        self.include = include
        self.exclude = exclude
    }
    enum CodingKeys: String, CodingKey { case include, exclude }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.include = try c.decodeIfPresent([String].self, forKey: .include) ?? ["**/*.md"]
        self.exclude = try c.decodeIfPresent([String].self, forKey: .exclude) ?? [".detdoc/**", "node_modules/**"]
    }
}

public struct PathsConfig: Codable, Sendable, Equatable {
    public var deny: [String]
    public init(deny: [String]) { self.deny = deny }
    enum CodingKeys: String, CodingKey { case deny }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.deny = try c.decodeIfPresent([String].self, forKey: .deny) ?? [".env", ".env.*", "node_modules/**", ".git/**"]
    }
}

public struct ValidationCommand: Codable, Sendable, Equatable {
    public var name: String
    public var run: String
    public init(name: String, run: String) {
        self.name = name
        self.run = run
    }
    enum CodingKeys: String, CodingKey { case name, run, command, cmd }
    public init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let raw = try? single.decode(String.self) {
            self.name = raw
            self.run = raw
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let run = try c.decodeIfPresent(String.self, forKey: .run)
            ?? c.decodeIfPresent(String.self, forKey: .command)
            ?? c.decode(String.self, forKey: .cmd)
        self.run = run
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? run
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(run, forKey: .run)
    }
}

public struct ValidationConfig: Codable, Sendable, Equatable {
    public var commands: [ValidationCommand]
    public init(commands: [ValidationCommand]) { self.commands = commands }
    enum CodingKeys: String, CodingKey { case commands }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.commands = try c.decodeIfPresent([ValidationCommand].self, forKey: .commands) ?? []
    }
}

public struct AgentConfig: Codable, Sendable, Equatable {
    public var provider: String
    public var model: String?
    public var thinking: String
    public init(provider: String, model: String?, thinking: String) {
        self.provider = provider
        self.model = model
        self.thinking = thinking
    }
    enum CodingKeys: String, CodingKey { case provider, model, thinking }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? "pi-rpc"
        self.model = try c.decodeIfPresent(String.self, forKey: .model)
        self.thinking = try c.decodeIfPresent(String.self, forKey: .thinking) ?? "high"
    }
}

public struct WorktreeConfig: Codable, Sendable, Equatable {
    public var keepOnFailure: Bool
    public init(keepOnFailure: Bool) { self.keepOnFailure = keepOnFailure }
    enum CodingKeys: String, CodingKey { case keepOnFailure }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.keepOnFailure = try c.decodeIfPresent(Bool.self, forKey: .keepOnFailure) ?? true
    }
}

public struct ApplyConfig: Codable, Sendable, Equatable {
    public var autoCommit: Bool
    public init(autoCommit: Bool) { self.autoCommit = autoCommit }
    enum CodingKeys: String, CodingKey { case autoCommit }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.autoCommit = try c.decodeIfPresent(Bool.self, forKey: .autoCommit) ?? true
    }
}

public struct DetDocConfig: Codable, Sendable, Equatable {
    public var docs: DocsConfig
    public var paths: PathsConfig
    public var validation: ValidationConfig
    public var agent: AgentConfig
    public var worktree: WorktreeConfig
    public var apply: ApplyConfig

    public init(
        docs: DocsConfig,
        paths: PathsConfig,
        validation: ValidationConfig,
        agent: AgentConfig,
        worktree: WorktreeConfig,
        apply: ApplyConfig
    ) {
        self.docs = docs
        self.paths = paths
        self.validation = validation
        self.agent = agent
        self.worktree = worktree
        self.apply = apply
    }

    enum CodingKeys: String, CodingKey { case docs, paths, validation, agent, worktree, apply }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.docs = try c.decodeIfPresent(DocsConfig.self, forKey: .docs) ?? DetDocConfig.default.docs
        self.paths = try c.decodeIfPresent(PathsConfig.self, forKey: .paths) ?? DetDocConfig.default.paths
        self.validation = try c.decodeIfPresent(ValidationConfig.self, forKey: .validation) ?? DetDocConfig.default.validation
        self.agent = try c.decodeIfPresent(AgentConfig.self, forKey: .agent) ?? DetDocConfig.default.agent
        self.worktree = try c.decodeIfPresent(WorktreeConfig.self, forKey: .worktree) ?? DetDocConfig.default.worktree
        self.apply = try c.decodeIfPresent(ApplyConfig.self, forKey: .apply) ?? DetDocConfig.default.apply
    }

    public static let `default` = DetDocConfig(
        docs: DocsConfig(include: ["**/*.md"], exclude: [".detdoc/**", "node_modules/**"]),
        paths: PathsConfig(deny: [".env", ".env.*", "node_modules/**", ".git/**"]),
        validation: ValidationConfig(commands: []),
        agent: AgentConfig(provider: "pi-rpc", model: nil, thinking: "high"),
        worktree: WorktreeConfig(keepOnFailure: true),
        apply: ApplyConfig(autoCommit: true)
    )
}
