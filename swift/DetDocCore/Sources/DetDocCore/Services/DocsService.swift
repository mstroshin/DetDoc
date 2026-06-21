import Foundation

public struct DocsService: Sendable {
    private let root: URL
    private let config: DetDocConfig
    private var policy: PathPolicy { PathPolicy(config: config) }

    public init(root: URL, config: DetDocConfig) {
        self.root = root
        self.config = config
    }

    public func list() -> [DocFile] {
        let docsDir = root.appendingPathComponent("docs")
        guard let enumerator = FileManager.default.enumerator(at: docsDir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        var docs: [DocFile] = []
        for case let url as URL in enumerator where url.pathExtension == "md" {
            let relative = relativePath(url)
            guard policy.isDoc(relative) else { continue }
            docs.append(DocFile(path: relative, title: url.deletingPathExtension().lastPathComponent))
        }
        return docs.sorted { $0.path < $1.path }
    }

    public func read(_ path: String) throws -> String {
        do {
            return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        } catch {
            throw DetDocError("DOC_READ_FAILED", "\(path): \(error)")
        }
    }

    public func write(_ path: String, _ markdown: String) throws {
        let url = root.appendingPathComponent(path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try markdown.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw DetDocError("DOC_WRITE_FAILED", "\(path): \(error)")
        }
    }

    public func create(_ path: String, _ markdown: String) throws {
        if FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) {
            throw DetDocError("DOC_ALREADY_EXISTS", path)
        }
        try write(path, markdown)
    }

    public func rename(_ from: String, to: String) throws {
        let toURL = root.appendingPathComponent(to)
        do {
            try FileManager.default.createDirectory(at: toURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: root.appendingPathComponent(from), to: toURL)
        } catch {
            throw DetDocError("DOC_RENAME_FAILED", "\(from) -> \(to): \(error)")
        }
    }

    public func delete(_ path: String) throws {
        do {
            try FileManager.default.removeItem(at: root.appendingPathComponent(path))
        } catch {
            throw DetDocError("DOC_DELETE_FAILED", "\(path): \(error)")
        }
    }

    public func listDirectories() -> [String] {
        let docsDir = root.appendingPathComponent("docs")
        guard let enumerator = FileManager.default.enumerator(at: docsDir, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        var dirs: [String] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                dirs.append(relativePath(url))
            }
        }
        return dirs.sorted()
    }

    public func createDirectory(_ path: String) throws {
        let url = root.appendingPathComponent(path)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            throw DetDocError("DOC_ALREADY_EXISTS", path)
        }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw DetDocError("DOC_WRITE_FAILED", "\(path): \(error)")
        }
    }

    private func relativePath(_ url: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        return urlComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }
}
