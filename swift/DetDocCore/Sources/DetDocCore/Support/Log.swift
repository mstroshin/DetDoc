import os

/// Shared OSLog loggers. One subsystem groups every DetDoc log; filter by category in
/// Xcode's console or Console.app. Subsystem: `com.detdoc`.
///
/// Interpolations are marked `.public` at call sites because this is a local developer
/// tool — without it OSLog redacts dynamic values as `<private>` and the logs read blank.
public enum DetDocLog {
    private static let subsystem = "com.detdoc"
    public static let engine = Logger(subsystem: subsystem, category: "engine")
    public static let agent = Logger(subsystem: subsystem, category: "agent")
    /// Full prompts sent to the agent. Separate category so it can be filtered out
    /// (Xcode/Console: hide category `prompt`) — prompts are verbose.
    public static let prompt = Logger(subsystem: subsystem, category: "prompt")
    public static let process = Logger(subsystem: subsystem, category: "process")
    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let run = Logger(subsystem: subsystem, category: "run")
}
