import Foundation

public struct ImageRef: Equatable, Sendable {
    public let range: NSRange   // covers "@guides/assets/window.png" (includes the @)
    public let path: String     // docs-relative path WITH extension, e.g. "guides/assets/window.png"
    public init(range: NSRange, path: String) { self.range = range; self.path = path }
}

public enum ImageRefScanner {
    /// Image file extensions recognized as inline-image tokens (lowercased).
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp"]

    /// True if `path`'s extension is a recognized image extension (case-insensitive).
    public static func isImagePath(_ path: String) -> Bool {
        guard let dot = path.lastIndex(of: "."), dot < path.index(before: path.endIndex) else { return false }
        let ext = path[path.index(after: dot)...].lowercased()
        return imageExtensions.contains(ext)
    }

    /// Finds `@<path>` tokens whose path ends in a recognized image extension.
    public static func scan(_ text: String) -> [ImageRef] {
        AtTokenScanner.scan(text).compactMap { tok in
            guard isImagePath(tok.path) else { return nil }
            return ImageRef(range: tok.range, path: tok.path)
        }
    }
}
