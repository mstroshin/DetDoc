import Foundation
import Observation
import DetDocCore

@MainActor
@Observable
public final class DocsTreeViewModel {
    public private(set) var nodes: [DocTreeNode] = []
    public private(set) var error: DetDocError?

    private let docs: DocsService

    public init(root: URL, config: DetDocConfig) {
        self.docs = DocsService(root: root, config: config)
    }

    public func refresh() {
        let built = DocTreeBuilder.build(files: docs.list().map(\.path), directories: docs.listDirectories())
        // Unwrap the single "docs" root so the panel shows docs/ contents directly.
        if built.count == 1, built[0].id == "docs", built[0].isDirectory {
            nodes = built[0].children ?? []
        } else {
            nodes = built
        }
    }

    @discardableResult
    public func newFile(name: String, in directory: String) -> String? {
        let leaf = name.hasSuffix(".md") ? name : name + ".md"
        let path = directory.isEmpty ? leaf : "\(directory)/\(leaf)"
        let title = leaf.hasSuffix(".md") ? String(leaf.dropLast(3)) : leaf
        return run { try docs.create(path, "# \(title)\n"); return path }
    }

    @discardableResult
    public func newFolder(name: String, in directory: String) -> String? {
        let path = directory.isEmpty ? name : "\(directory)/\(name)"
        return run { try docs.createDirectory(path); return path }
    }

    @discardableResult
    public func rename(_ path: String, to newName: String) -> String? {
        let parent = Self.parentDirectory(of: path)
        let leaf = (!isDirectory(path) && !newName.hasSuffix(".md")) ? newName + ".md" : newName
        let newPath = parent.isEmpty ? leaf : "\(parent)/\(leaf)"
        return run { try docs.rename(path, to: newPath); return newPath }
    }

    public func delete(_ path: String) {
        _ = run { try docs.delete(path); return "" }
    }

    public func dismissError() { error = nil }

    public func isDirectory(_ id: String) -> Bool {
        Self.find(id, in: nodes)?.isDirectory ?? false
    }

    public func directoryForNewEntry(selection: String?) -> String {
        guard let selection, let node = Self.find(selection, in: nodes) else { return "docs" }
        return node.isDirectory ? node.id : Self.parentDirectory(of: node.id)
    }

    nonisolated public static func remapAfterRename(selection: String?, from: String, to: String) -> String? {
        guard let selection else { return nil }
        if selection == from { return to }
        if selection.hasPrefix(from + "/") { return to + String(selection.dropFirst(from.count)) }
        return selection
    }

    nonisolated public static func remapAfterDelete(selection: String?, deleted: String) -> String? {
        guard let selection else { return nil }
        if selection == deleted || selection.hasPrefix(deleted + "/") { return nil }
        return selection
    }

    // MARK: - Private

    private func run(_ op: () throws -> String) -> String? {
        do {
            let result = try op()
            error = nil
            refresh()
            return result
        } catch let e as DetDocError {
            error = e
            return nil
        } catch {
            self.error = DetDocError("DOC_OP_FAILED", "\(error)")
            return nil
        }
    }

    nonisolated static func parentDirectory(of path: String) -> String {
        var comps = path.split(separator: "/").map(String.init)
        comps.removeLast()
        return comps.joined(separator: "/")
    }

    nonisolated static func find(_ id: String, in nodes: [DocTreeNode]) -> DocTreeNode? {
        for n in nodes {
            if n.id == id { return n }
            if let c = n.children, let hit = find(id, in: c) { return hit }
        }
        return nil
    }
}
