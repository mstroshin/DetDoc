import Foundation
import Testing
@testable import DetDocCore

@Test func runFlowWritesCodeLinkBlockIntoInputDoc() async throws {
    let fx = try await GitFixture()
    try ConfigStore().initFiles(root: fx.root)
    try await fx.commitAll("detdoc init")
    try fx.write("docs/idea.md", "# Idea\n\nDo the thing.\n")   // dirty doc drives the run

    let links = [CodeLink(docPath: "docs/idea.md", heading: "# Idea", refs: ["src/app.swift#run"])]
    let engine = DetDocEngine(root: fx.root,
                              agent: FakeAgentRunner(target: "src/app.swift", content: "let v = 1\n", codeLinks: links))

    let stream = await engine.start(mode: .run, message: nil)
    var applied = false
    for try await event in stream {
        switch event {
        case .planReady: await engine.submitPlanDecision(.approve)
        case .patchReady: await engine.submitApplyDecision(.apply)
        case .complete(let r): applied = r.applied
        default: break
        }
    }
    #expect(applied)

    let doc = try String(contentsOf: fx.root.appendingPathComponent("docs/idea.md"), encoding: .utf8)
    #expect(doc.contains(##"<!-- detdoc:link "# Idea" src/app.swift#run -->"##))
    #expect(doc.hasPrefix("# Idea\n\nDo the thing.\n"))   // prose preserved

    let status = try await fx.repo.statusPorcelain()
    #expect(status.isEmpty)   // links committed; tree clean
}

@Test func runFlowDropsLinksForDocsNotInInput() async throws {
    let fx = try await GitFixture()
    try ConfigStore().initFiles(root: fx.root)
    try fx.write("docs/other.md", "# Other\n")
    try await fx.commitAll("detdoc init")            // other.md committed, NOT dirty
    try fx.write("docs/idea.md", "# Idea\n")          // only idea.md drives the run

    let links = [CodeLink(docPath: "docs/other.md", heading: "# Other", refs: ["src/app.swift#run"])]
    let engine = DetDocEngine(root: fx.root,
                              agent: FakeAgentRunner(target: "src/app.swift", content: "x\n", codeLinks: links))
    let stream = await engine.start(mode: .run, message: nil)
    for try await event in stream {
        switch event {
        case .planReady: await engine.submitPlanDecision(.approve)
        case .patchReady: await engine.submitApplyDecision(.apply)
        default: break
        }
    }
    let other = try String(contentsOf: fx.root.appendingPathComponent("docs/other.md"), encoding: .utf8)
    #expect(!other.contains("detdoc:link"))   // not in input diff → untouched
}
