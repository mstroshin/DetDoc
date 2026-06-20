import Foundation

public enum PiHealth {
    public static func isAvailable() async -> Bool {
        guard let result = try? await ProcessRunner.run("pi", ["--version"], cwd: FileManager.default.temporaryDirectory) else {
            return false
        }
        return result.status == 0
    }
}
