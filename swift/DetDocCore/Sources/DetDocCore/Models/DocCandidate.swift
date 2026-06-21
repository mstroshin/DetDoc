import Foundation

public struct DocCandidate: Equatable, Sendable {
    public let name: String              // file name without ".md": "setup"
    public let docsRelativePath: String  // "guides/setup.md"
    public let title: String?            // first ATX heading, if any
    public init(name: String, docsRelativePath: String, title: String?) {
        self.name = name
        self.docsRelativePath = docsRelativePath
        self.title = title
    }
}
