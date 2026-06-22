import Foundation
import Observation
import DetDocCore

public enum AppRoute: Equatable, Sendable {
    case noProject
    case onboarding(root: URL)
    case workspace(root: URL)
}

public protocol FolderPicking: Sendable {
    func pickFolder() async -> URL?
}

@MainActor
@Observable
public final class AppCoordinator {
    public private(set) var route: AppRoute = .noProject
    private let picker: any FolderPicking
    private let defaults: UserDefaults
    private static let lastProjectKey = "detdoc.lastProjectPath"

    public init(picker: any FolderPicking, defaults: UserDefaults = .standard) {
        self.picker = picker
        self.defaults = defaults
    }

    public func chooseProject() async {
        guard let url = await picker.pickFolder() else { return }
        open(root: url)
    }

    public func open(root: URL) {
        defaults.set(root.path, forKey: Self.lastProjectKey)
        let configPath = ConfigStore().configPath(root: root)
        if FileManager.default.fileExists(atPath: configPath.path) {
            DetDocLog.app.notice("open → workspace: \(root.path, privacy: .public)")
            route = .workspace(root: root)
        } else {
            DetDocLog.app.notice("open → onboarding (no config): \(root.path, privacy: .public)")
            route = .onboarding(root: root)
        }
    }

    /// Reopen the last project on launch, if the folder still exists.
    public func restoreLastProject() {
        guard case .noProject = route,
              let path = defaults.string(forKey: Self.lastProjectKey),
              FileManager.default.fileExists(atPath: path) else { return }
        open(root: URL(filePath: path))
    }

    public func initialized(root: URL) {
        route = .workspace(root: root)
    }
}
