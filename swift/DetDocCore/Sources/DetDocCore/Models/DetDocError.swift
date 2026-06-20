public struct DetDocError: Error, Sendable, Equatable, CustomStringConvertible {
    public let code: String
    public let message: String
    public var details: String?
    public var phase: String?
    public var runId: String?
    public var path: String?
    public var command: String?
    public var suggestedAction: String?

    public init(
        code: String,
        message: String,
        details: String? = nil,
        phase: String? = nil,
        runId: String? = nil,
        path: String? = nil,
        command: String? = nil,
        suggestedAction: String? = nil
    ) {
        self.code = code
        self.message = message
        self.details = details
        self.phase = phase
        self.runId = runId
        self.path = path
        self.command = command
        self.suggestedAction = suggestedAction
    }

    public init(_ code: String, _ message: String) {
        self.init(code: code, message: message)
    }

    public var description: String { "\(code): \(message)" }
}
