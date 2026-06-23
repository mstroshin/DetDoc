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
        case .inputReady: await engine.submitInputDecision(.confirm)
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

@Test func rerunAfterHumanEditReplacesLinkBlock() async throws {
    // Run #1: annotate docs/idea.md with "# Idea" link.
    let fx = try await GitFixture()
    try ConfigStore().initFiles(root: fx.root)
    try await fx.commitAll("detdoc init")
    try fx.write("docs/idea.md", "# Idea\n\nDo the thing.\n")   // dirty → drives run #1

    let links1 = [CodeLink(docPath: "docs/idea.md", heading: "# Idea", refs: ["src/app.swift#run"])]
    let engine1 = DetDocEngine(root: fx.root,
                               agent: FakeAgentRunner(target: "src/app.swift", content: "let v = 1\n", codeLinks: links1))
    let stream1 = await engine1.start(mode: .run, message: nil)
    for try await event in stream1 {
        switch event {
        case .inputReady: await engine1.submitInputDecision(.confirm)
        case .planReady: await engine1.submitPlanDecision(.approve)
        case .patchReady: await engine1.submitApplyDecision(.apply)
        default: break
        }
    }
    // autoCommit → tree is clean; docs/idea.md has the # Idea link block committed.
    let afterRun1 = try String(contentsOf: fx.root.appendingPathComponent("docs/idea.md"), encoding: .utf8)
    #expect(afterRun1.contains("detdoc:link"))

    // Simulate human edit: overwrite the whole file with renamed heading, no link line.
    try fx.write("docs/idea.md", "# Concept\n\nDo the thing differently.\n")

    // Run #2: fresh engine, links keyed to the new "# Concept" heading.
    let links2 = [CodeLink(docPath: "docs/idea.md", heading: "# Concept", refs: ["src/app.swift#run"])]
    let engine2 = DetDocEngine(root: fx.root,
                               agent: FakeAgentRunner(target: "src/app.swift", content: "let v = 2\n", codeLinks: links2))
    let stream2 = await engine2.start(mode: .run, message: nil)
    var applied2 = false
    for try await event in stream2 {
        switch event {
        case .inputReady: await engine2.submitInputDecision(.confirm)
        case .planReady: await engine2.submitPlanDecision(.approve)
        case .patchReady: await engine2.submitApplyDecision(.apply)
        case .complete(let r): applied2 = r.applied
        default: break
        }
    }
    #expect(applied2)

    let doc = try String(contentsOf: fx.root.appendingPathComponent("docs/idea.md"), encoding: .utf8)
    // New heading link present.
    #expect(doc.contains("<!-- detdoc:link \"# Concept\" src/app.swift#run -->"))
    // Old heading link absent.
    #expect(!doc.contains("# Idea"))
    // Exactly one detdoc:link line (no duplication).
    let occurrences = doc.components(separatedBy: "detdoc:link").count - 1
    #expect(occurrences == 1)
    // Tree is clean after autoCommit.
    let status = try await fx.repo.statusPorcelain()
    #expect(status.isEmpty)
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
        case .inputReady: await engine.submitInputDecision(.confirm)
        case .planReady: await engine.submitPlanDecision(.approve)
        case .patchReady: await engine.submitApplyDecision(.apply)
        default: break
        }
    }
    let other = try String(contentsOf: fx.root.appendingPathComponent("docs/other.md"), encoding: .utf8)
    #expect(!other.contains("detdoc:link"))   // not in input diff → untouched
}
