import Foundation
import Observation
import DetDocCore

@MainActor
@Observable
public final class SettingsViewModel {
    public var config: DetDocConfig = .default
    public private(set) var piAvailable: Bool = false
    public private(set) var error: DetDocError?

    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func load() {
        config = (try? ConfigStore().load(root: root)) ?? .default
    }

    public func save() {
        error = nil
        do {
            try ConfigStore().write(config, root: root)
        } catch let e as DetDocError {
            error = e
        } catch {
            self.error = DetDocError("CONFIG_WRITE_FAILED", "\(error)")
        }
    }

    public func refreshPiHealth() async {
        piAvailable = await PiHealth.isAvailable()
    }
}
