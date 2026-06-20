public struct PathPolicy: Sendable {
    private let config: DetDocConfig

    public init(config: DetDocConfig) {
        self.config = config
    }

    public func isDenied(_ path: String) -> Bool {
        Glob.matchesAny(path, patterns: config.paths.deny)
    }

    public func isDoc(_ path: String) -> Bool {
        Glob.matchesAny(path, patterns: config.docs.include)
            && !Glob.matchesAny(path, patterns: config.docs.exclude)
    }
}
