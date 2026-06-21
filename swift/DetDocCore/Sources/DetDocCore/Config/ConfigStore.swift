import Foundation
import Yams

public struct ConfigStore: Sendable {
    public init() {}

    public func configPath(root: URL) -> URL {
        root.appendingPathComponent(".detdoc").appendingPathComponent("config.yml")
    }

    public func defaultConfigYAML() throws -> String {
        do {
            return try YAMLEncoder().encode(DetDocConfig.default)
        } catch {
            throw DetDocError("CONFIG_SERIALIZE_FAILED", "\(error)")
        }
    }

    public func load(root: URL) throws -> DetDocConfig {
        let path = configPath(root: root)
        let content: String
        do {
            content = try String(contentsOf: path, encoding: .utf8)
        } catch {
            throw DetDocError("CONFIG_READ_FAILED", "\(path.path): \(error)")
        }
        do {
            return try YAMLDecoder().decode(DetDocConfig.self, from: content)
        } catch {
            throw DetDocError("CONFIG_PARSE_FAILED", "\(error)")
        }
    }

    public func write(_ config: DetDocConfig, root: URL) throws {
        let yaml: String
        do {
            yaml = try Yams.YAMLEncoder().encode(config)
        } catch {
            throw DetDocError("CONFIG_SERIALIZE_FAILED", "\(error)")
        }
        let path = configPath(root: root)
        do {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try yaml.write(to: path, atomically: true, encoding: .utf8)
        } catch {
            throw DetDocError("CONFIG_WRITE_FAILED", "\(error)")
        }
    }

    public func initFiles(root: URL) throws {
        try writeIfMissing(configPath(root: root), try defaultConfigYAML())
        try writeIfMissing(root.appendingPathComponent(".detdoc/runs/.gitkeep"), "")
        for (relativePath, content) in Self.starterDocs {
            try writeIfMissing(root.appendingPathComponent(relativePath), content)
        }
        try GitignoreManager.ensureManagedEntries(root: root)
    }

    static let starterDocs: [(String, String)] = [
        ("docs/idea.md", "# Project Idea\n\nDescribe the product in plain language.\n"),
        ("docs/technical-spec.md", "# Technical Specification\n\nKeep durable technical decisions here.\n"),
        ("docs/features/_guide.md", "# Feature Planning Guide\n\nUse this folder for free-form feature planning.\n"),
        ("docs/features/example-feature/brief.md", "# Example Feature Brief\n\n## Goal\n\nDescribe the user-visible behavior.\n"),
        ("docs/features/example-feature/plan.md", "# Example Feature Plan\n\nUse this file for free-form implementation planning.\n"),
        ("docs/features/example-feature/notes.md", "# Example Feature Notes\n\nUse this file for decisions and examples.\n"),
    ]

    private func writeIfMissing(_ url: URL, _ content: String) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { return }
        let parent = url.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            throw DetDocError("WRITE_DIR_FAILED", "\(error)")
        }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw DetDocError("WRITE_FILE_FAILED", "\(url.path): \(error)")
        }
    }

}
