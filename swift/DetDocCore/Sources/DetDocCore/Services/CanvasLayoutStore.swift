import Foundation

/// Loads/saves user-dragged canvas positions to `.detdoc/canvas-layout.json` (local, gitignored).
/// Best-effort: never throws into the UI; a missing/corrupt file is treated as no saved layout.
public struct CanvasLayoutStore: Sendable {
    private let root: URL
    public init(root: URL) { self.root = root }

    private var fileURL: URL {
        root.appendingPathComponent(".detdoc").appendingPathComponent("canvas-layout.json")
    }

    public func load() -> [String: DocGraphPoint] {
        guard let data = try? Data(contentsOf: fileURL),
              let map = try? JSONDecoder().decode([String: DocGraphPoint].self, from: data)
        else { return [:] }
        return map
    }

    public func save(_ positions: [String: DocGraphPoint]) {
        guard let data = try? JSONEncoder().encode(positions) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
