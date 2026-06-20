import Foundation
import Observation
import DetDocCore

@MainActor
@Observable
public final class RunsViewModel {
    public private(set) var runs: [RunSummary] = []
    public private(set) var error: DetDocError?

    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func refresh() {
        let store = ArtifactStore(projectRoot: root)
        let runsDir = root.appendingPathComponent(".detdoc/runs")
        let entries = (try? FileManager.default.contentsOfDirectory(at: runsDir, includingPropertiesForKeys: nil)) ?? []
        var summaries: [RunSummary] = []
        for entry in entries {
            let runId = entry.lastPathComponent
            guard let manifest: RunManifest = try? store.readJSON(RunManifest.self, runId, "manifest.json") else { continue }
            let hasPatch = FileManager.default.fileExists(atPath: entry.appendingPathComponent("changes.patch").path)
            summaries.append(RunSummary(runId: runId, hasPatch: hasPatch, approvedTargets: manifest.approvedTargets))
        }
        runs = summaries.sorted { $0.runId > $1.runId }
    }

    public func apply(_ runId: String) async {
        error = nil
        do {
            let config = try ConfigStore().load(root: root)
            _ = try await RunApplier().apply(root: root, runId: runId, autoCommit: config.apply.autoCommit)
            refresh()
        } catch let e as DetDocError {
            error = e
        } catch {
            self.error = DetDocError("APPLY_FAILED", "\(error)")
        }
    }
}
