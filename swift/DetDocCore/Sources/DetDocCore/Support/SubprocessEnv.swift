import Foundation

/// GUI apps launched from Finder/Dock inherit a minimal PATH (`/usr/bin:/bin:/usr/sbin:/sbin`)
/// with no Homebrew. DetDoc's tools (pi, tuist, xcsift) live in `/opt/homebrew/bin`, so every
/// subprocess we spawn via `/usr/bin/env` would fail with exit 127 / "env: pi: No such file".
/// We prepend the standard CLI install dirs to the inherited PATH for all spawns.
/// ponytail: static dir list covers Homebrew (Apple Silicon + Intel); query the login shell
/// only if users start keeping tools somewhere exotic.
enum SubprocessEnv {
    static let extraPaths = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/sbin"]

    /// Inherited environment with `PATH` prepended by `extraPaths` (skipping dirs already present).
    static func augmenting(_ base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        let existing = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let existingDirs = Set(existing.split(separator: ":").map(String.init))
        let prefix = extraPaths.filter { !existingDirs.contains($0) }
        env["PATH"] = (prefix + [existing]).joined(separator: ":")
        return env
    }
}
