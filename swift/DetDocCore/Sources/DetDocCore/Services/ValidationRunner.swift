import Foundation

public struct ValidationRunner: Sendable {
    public init() {}

    public func run(commands: [ValidationCommand], cwd: URL) async throws -> String {
        var log = ""
        for command in commands {
            log += "\n# \(command.name)\n$ \(command.run)\n"
            let result = try await ProcessRunner.run("/bin/sh", ["-c", command.run], cwd: cwd)
            log += result.stdoutString
            log += result.stderrString
            if result.status != 0 {
                throw DetDocError("VALIDATION_FAILED", "Validation command failed: \(command.name)\n\(log)")
            }
        }
        return String(log.drop { $0 == "\n" || $0 == " " || $0 == "\t" })
    }
}
