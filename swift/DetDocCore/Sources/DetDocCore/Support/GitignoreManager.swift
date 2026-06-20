import Foundation

public enum GitignoreManager {
    public static let managedEntries = [".DS_Store", ".detdoc/runs/*", "!.detdoc/runs/.gitkeep", ".worktrees/"]

    public static func ensureManagedEntries(root: URL) throws {
        let url = root.appendingPathComponent(".gitignore")
        var content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        for entry in managedEntries where !content.split(separator: "\n", omittingEmptySubsequences: false)
            .contains(where: { $0.trimmingCharacters(in: .whitespaces) == entry }) {
            if !content.isEmpty && !content.hasSuffix("\n") { content += "\n" }
            content += entry + "\n"
        }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw DetDocError("GITIGNORE_WRITE_FAILED", "\(error)")
        }
    }
}
