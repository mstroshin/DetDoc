import Foundation

/// Imports dragged/pasted images into the `assets/` folder next to a document and
/// resolves image tokens back to absolute file URLs for rendering.
public struct DocImageImporter: Sendable {
    private let root: URL
    public init(root: URL) { self.root = root }

    /// Copies the file at `sourceURL` into `<docDir>/assets/` (deduping the name)
    /// and returns the docs-relative token path, e.g. "guides/assets/window.png".
    public func importFile(at sourceURL: URL, forDoc docPath: String) throws -> String {
        let (dir, tokenPrefix) = assetsDir(forDoc: docPath)
        let name = uniqueName(sourceURL.lastPathComponent, in: dir)
        let dest = dir.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: dest)
        } catch {
            throw DetDocError("IMAGE_IMPORT_FAILED", "\(sourceURL.lastPathComponent): \(error)")
        }
        return "\(tokenPrefix)/\(name)"
    }

    /// Writes `data` into `<docDir>/assets/<basename>.<ext>` (deduping) and returns
    /// the docs-relative token path. The caller supplies `basename` (e.g. a timestamp)
    /// so the clock stays out of core.
    public func importData(_ data: Data, basename: String, ext: String = "png",
                           forDoc docPath: String) throws -> String {
        let (dir, tokenPrefix) = assetsDir(forDoc: docPath)
        let name = uniqueName("\(basename).\(ext)", in: dir)
        let dest = dir.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dest)
        } catch {
            throw DetDocError("IMAGE_IMPORT_FAILED", "\(basename).\(ext): \(error)")
        }
        return "\(tokenPrefix)/\(name)"
    }

    /// Returns the absolute file URL for an image token path iff the file exists.
    public func resolve(_ tokenPath: String) -> URL? {
        let clean = tokenPath.hasPrefix("/") ? String(tokenPath.dropFirst()) : tokenPath
        guard !clean.isEmpty else { return nil }
        // Keep resolution bounded to the docs subtree — reject path traversal.
        guard !clean.split(separator: "/").contains("..") else { return nil }
        let url = root.appendingPathComponent("docs").appendingPathComponent(clean)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Helpers

    /// The absolute assets directory and its docs-relative token prefix for `docPath`.
    /// `docPath` is root-relative incl. "docs/" (e.g. "docs/guides/setup.md").
    func assetsDir(forDoc docPath: String) -> (dir: URL, tokenPrefix: String) {
        let docsRel = docPath.hasPrefix("docs/") ? String(docPath.dropFirst("docs/".count)) : docPath
        let comps = docsRel.split(separator: "/").map(String.init)
        let prefixComps = comps.dropLast() + ["assets"]   // doc's directory + assets
        let tokenPrefix = prefixComps.joined(separator: "/")
        let dir = root.appendingPathComponent("docs").appendingPathComponent(tokenPrefix)
        return (dir, tokenPrefix)
    }

    private func uniqueName(_ filename: String, in dir: URL) -> String {
        let ext = (filename as NSString).pathExtension
        let stem = (filename as NSString).deletingPathExtension
        var candidate = filename
        var i = 1
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(stem)-\(i)" : "\(stem)-\(i).\(ext)"
            i += 1
        }
        return candidate
    }
}
