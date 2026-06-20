import Foundation

public struct ArtifactStore: Sendable {
    private let root: URL

    public init(projectRoot: URL) {
        self.root = projectRoot.appendingPathComponent(".detdoc/runs")
    }

    public func runDir(_ runId: String) -> URL {
        root.appendingPathComponent(runId)
    }

    public func createRun(_ manifest: RunManifest) throws {
        do {
            try FileManager.default.createDirectory(at: runDir(manifest.runId), withIntermediateDirectories: true)
        } catch {
            throw DetDocError("ARTIFACT_DIR_FAILED", "\(error)")
        }
        try writeJSON(manifest.runId, "manifest.json", manifest)
    }

    public func writeJSON<T: Encodable>(_ runId: String, _ name: String, _ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw DetDocError("ARTIFACT_JSON_FAILED", "\(error)")
        }
        let text = String(decoding: data, as: UTF8.self) + "\n"
        try writeText(runId, name, text)
    }

    public func readJSON<T: Decodable>(_ type: T.Type, _ runId: String, _ name: String) throws -> T {
        let text = try readText(runId, name)
        do {
            return try JSONDecoder().decode(T.self, from: Data(text.utf8))
        } catch {
            throw DetDocError("ARTIFACT_PARSE_FAILED", "\(error)")
        }
    }

    public func writeText(_ runId: String, _ name: String, _ content: String) throws {
        let url = runDir(runId).appendingPathComponent(name)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw DetDocError("ARTIFACT_WRITE_FAILED", "\(error)")
        }
    }

    public func readText(_ runId: String, _ name: String) throws -> String {
        let url = runDir(runId).appendingPathComponent(name)
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw DetDocError("ARTIFACT_READ_FAILED", "\(error)")
        }
    }

    public func listRuns() -> [RunSummary] {
        let runsDir = root  // ArtifactStore.root is already <project>/.detdoc/runs
        guard let entries = try? FileManager.default.contentsOfDirectory(at: runsDir, includingPropertiesForKeys: nil) else { return [] }
        var summaries: [RunSummary] = []
        for entry in entries {
            let runId = entry.lastPathComponent
            guard let manifest: RunManifest = try? readJSON(RunManifest.self, runId, "manifest.json") else { continue }
            let hasPatch = FileManager.default.fileExists(atPath: entry.appendingPathComponent("changes.patch").path)
            summaries.append(RunSummary(runId: runId, hasPatch: hasPatch, approvedTargets: manifest.approvedTargets))
        }
        return summaries.sorted { $0.runId > $1.runId }
    }

    public func deleteRun(_ runId: String) throws {
        do {
            try FileManager.default.removeItem(at: runDir(runId))
        } catch {
            throw DetDocError("ARTIFACT_DELETE_FAILED", "\(error)")
        }
    }
}
