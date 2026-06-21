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

    public init(picker: any FolderPicking) {
        self.picker = picker
    }

    public func chooseProject() async {
        guard let url = await picker.pickFolder() else { return }
        open(root: url)
    }

    public func open(root: URL) {
        let configPath = ConfigStore().configPath(root: root)
        if FileManager.default.fileExists(atPath: configPath.path) {
            route = .workspace(root: root)
        } else {
            route = .onboarding(root: root)
        }
    }

    public func initialized(root: URL) {
        route = .workspace(root: root)
    }
}
