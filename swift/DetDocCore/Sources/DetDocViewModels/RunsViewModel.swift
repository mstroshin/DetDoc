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
        runs = ArtifactStore(projectRoot: root).listRuns()
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
