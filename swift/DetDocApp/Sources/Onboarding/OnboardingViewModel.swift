import Foundation
import Observation
import DetDocCore

@MainActor
@Observable
public final class OnboardingViewModel {
    public private(set) var error: DetDocError?
    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    @discardableResult
    public func initialize() async -> Bool {
        error = nil
        do {
            try ConfigStore().initFiles(root: root)
            try await GitRepository(root).ensureInitialized()
            return true
        } catch let e as DetDocError {
            error = e
            return false
        } catch {
            self.error = DetDocError("INIT_FAILED", "\(error)")
            return false
        }
    }
}
