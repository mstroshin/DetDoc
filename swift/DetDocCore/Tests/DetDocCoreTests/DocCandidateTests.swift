import Foundation
import Testing
@testable import DetDocCore

@Test func candidatesStripDocsPrefixAndReadH1() throws {
    let tmp = TempDir()
    let svc = DocsService(root: tmp.url, config: .default)
    try FileManager.default.createDirectory(at: tmp.url.appendingPathComponent("docs/guides"), withIntermediateDirectories: true)
    try "# Setup Guide\n\nbody".write(to: tmp.url.appendingPathComponent("docs/guides/setup.md"), atomically: true, encoding: .utf8)
    try "no heading".write(to: tmp.url.appendingPathComponent("docs/plain.md"), atomically: true, encoding: .utf8)

    let cands = svc.candidates()
    #expect(cands.contains(DocCandidate(name: "setup", docsRelativePath: "guides/setup.md", title: "Setup Guide")))
    #expect(cands.contains(DocCandidate(name: "plain", docsRelativePath: "plain.md", title: nil)))
}
