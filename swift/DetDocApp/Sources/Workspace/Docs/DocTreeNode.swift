import Foundation

nonisolated public struct DocTreeNode: Identifiable, Hashable {
    public let id: String          // relative path: "docs/guide/intro.md" or "docs/guide"
    public let name: String        // last path component: "intro.md" / "guide"
    public let isDirectory: Bool
    public var children: [DocTreeNode]?   // nil for files; [] for an empty directory
}

nonisolated public enum DocTreeBuilder {
    public static func build(files: [String], directories: [String]) -> [DocTreeNode] {
        let fileSet = Set(files)
        var dirSet = Set<String>()

        func addAncestors(of path: String) {
            var comps = path.split(separator: "/").map(String.init)
            comps.removeLast()
            var acc: [String] = []
            for c in comps {
                acc.append(c)
                dirSet.insert(acc.joined(separator: "/"))
            }
        }
        for f in fileSet { addAncestors(of: f) }
        for d in directories {
            dirSet.insert(d)
            addAncestors(of: d)
        }

        func parent(of path: String) -> String {
            var comps = path.split(separator: "/").map(String.init)
            comps.removeLast()
            return comps.joined(separator: "/")
        }
        var childrenByParent: [String: [String]] = [:]
        for d in dirSet { childrenByParent[parent(of: d), default: []].append(d) }
        for f in fileSet { childrenByParent[parent(of: f), default: []].append(f) }

        func name(of path: String) -> String { String(path.split(separator: "/").last ?? "") }

        func node(for path: String) -> DocTreeNode {
            if dirSet.contains(path) {
                let kids = (childrenByParent[path] ?? []).map(node(for:))
                return DocTreeNode(id: path, name: name(of: path), isDirectory: true, children: sortNodes(kids))
            }
            return DocTreeNode(id: path, name: name(of: path), isDirectory: false, children: nil)
        }

        let roots = (childrenByParent[""] ?? []).map(node(for:))
        return sortNodes(roots)
    }

    private static func sortNodes(_ nodes: [DocTreeNode]) -> [DocTreeNode] {
        nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}
