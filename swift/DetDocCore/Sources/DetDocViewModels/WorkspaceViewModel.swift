import Foundation
import Observation
import DetDocCore

@MainActor
@Observable
public final class WorkspaceViewModel {
    public private(set) var status: ProjectStatus?
    public private(set) var docs: [DocFile] = []
    public private(set) var runs: [RunSummary] = []

    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func refresh() async {
        let repo = GitRepository(root)
        let initialized = FileManager.default.fileExists(atPath: ConfigStore().configPath(root: root).path)
        let dirty = (try? await repo.statusPorcelain()) ?? []
        let piAvailable = await PiHealth.isAvailable()
        status = ProjectStatus(
            root: root.path,
            initialized: initialized,
            piAvailable: piAvailable,
            dirtyFiles: dirty.map { DirtyFile(status: $0.status, path: $0.path) }
        )
        guard initialized, let config = try? ConfigStore().load(root: root) else {
            docs = []
            runs = []
            return
        }
        docs = DocsService(root: root, config: config).list()
        runs = loadRuns()
    }

    private func loadRuns() -> [RunSummary] {
        let store = ArtifactStore(projectRoot: root)
        let runsDir = root.appendingPathComponent(".detdoc/runs")
        guard let entries = try? FileManager.default.contentsOfDirectory(at: runsDir, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        var summaries: [RunSummary] = []
        for entry in entries {
            let runId = entry.lastPathComponent
            guard let manifest: RunManifest = try? store.readJSON(RunManifest.self, runId, "manifest.json") else { continue }
            let hasPatch = FileManager.default.fileExists(atPath: entry.appendingPathComponent("changes.patch").path)
            summaries.append(RunSummary(runId: runId, hasPatch: hasPatch, approvedTargets: manifest.approvedTargets))
        }
        return summaries.sorted { $0.runId > $1.runId }
    }
}
