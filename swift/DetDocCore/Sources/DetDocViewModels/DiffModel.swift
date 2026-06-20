public enum DiffLineKind: Sendable, Equatable {
    case header, hunk, addition, deletion, context
}

public struct DiffLine: Sendable, Equatable {
    public let kind: DiffLineKind
    public let text: String
    public init(kind: DiffLineKind, text: String) {
        self.kind = kind
        self.text = text
    }
}

public struct DiffFile: Sendable, Equatable {
    public let path: String
    public let lines: [DiffLine]
    public init(path: String, lines: [DiffLine]) {
        self.path = path
        self.lines = lines
    }
}

public enum DiffModel {
    public static func parse(_ patch: String) -> [DiffFile] {
        var files: [DiffFile] = []
        var currentPath: String?
        var currentLines: [DiffLine] = []

        func flush() {
            if let path = currentPath {
                files.append(DiffFile(path: path, lines: currentLines))
            }
            currentLines = []
            currentPath = nil
        }

        for raw in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("diff --git ") {
                flush()
                if let last = line.split(separator: " ").last.map(String.init) {
                    currentPath = last.hasPrefix("b/") ? String(last.dropFirst(2)) : last
                }
            }
            let kind: DiffLineKind
            if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") || line.hasPrefix("index ") {
                kind = .header
                if line.hasPrefix("+++ b/") { currentPath = String(line.dropFirst(6)) }
            } else if line.hasPrefix("@@") {
                kind = .hunk
            } else if line.hasPrefix("+") {
                kind = .addition
            } else if line.hasPrefix("-") {
                kind = .deletion
            } else {
                kind = .context
            }
            if currentPath != nil { currentLines.append(DiffLine(kind: kind, text: line)) }
        }
        flush()
        return files
    }
}
