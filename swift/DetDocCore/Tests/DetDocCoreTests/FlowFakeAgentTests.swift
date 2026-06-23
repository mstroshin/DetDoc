import Foundation
import Testing
@testable import DetDocCore

/// Drive the engine to completion, auto-answering both gates.
private func drive(_ engine: DetDocEngine, mode: RunMode, message: String? = nil,
                   plan: PlanDecision, apply: ApplyDecision) async throws -> RunFlowResult? {
    let stream = await engine.start(mode: mode, message: message)
    var result: RunFlowResult?
    for try await event in stream {
        switch event {
        case .inputReady: await engine.submitInputDecision(.confirm)
        case .planReady: await engine.submitPlanDecision(plan)
        case .patchReady: await engine.submitApplyDecision(apply)
        case .complete(let r): result = r
        default: break
        }
    }
    return result
}

private func detdocRepo() async throws -> GitFixture {
    let fx = try await GitFixture()
    try ConfigStore().initFiles(root: fx.root)
    try await fx.commitAll("detdoc init")
    return fx
}

@Test func runFlowAppliesAndCommitsWithFakeAgent() async throws {
    let fx = try await detdocRepo()
    try fx.write("docs/idea.md", "changed idea\n")   // dirty doc drives the run
    let engine = DetDocEngine(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "let v = 2\n"))
    let result = try await drive(engine, mode: .run, plan: .approve, apply: .apply)
    #expect(result?.applied == true)
    #expect(FileManager.default.fileExists(atPath: fx.root.appendingPathComponent("src/app.swift").path))
    let log = try await fx.repo.git(["log", "--oneline", "-1"])
    #expect(log.contains("DetDoc apply"))
}

@Test func runFlowStopsWhenApplyDiscarded() async throws {
    let fx = try await detdocRepo()
    try fx.write("docs/idea.md", "changed\n")
    let engine = DetDocEngine(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "let v = 3\n"))
    let result = try await drive(engine, mode: .run, plan: .approve, apply: .discard)
    #expect(result?.applied == false)
    // patch saved, not applied to main
    #expect(!FileManager.default.fileExists(atPath: fx.root.appendingPathComponent("src/app.swift").path))
}

@Test func runFlowRejectsWhenPlanRejected() async throws {
    let fx = try await detdocRepo()
    try fx.write("docs/idea.md", "changed\n")
    let engine = DetDocEngine(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "x\n"))
    await #expect { _ = try await drive(engine, mode: .run, plan: .reject, apply: .apply) }
        throws: { ($0 as? DetDocError)?.code == "PLAN_NOT_APPROVED" }
}

@Test func fixFlowRequiresNonEmptyMessage() async throws {
    let fx = try await detdocRepo()
    let engine = DetDocEngine(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "x\n"))
    await #expect { _ = try await drive(engine, mode: .fix, message: "   ", plan: .approve, apply: .apply) }
        throws: { ($0 as? DetDocError)?.code == "EMPTY_FIX_MESSAGE" }
}

/// FIX 4(a): a test-only agent that fails validation on the first attempt then repairs it.
/// `implement` writes the approved target WITHOUT the marker the validation command requires;
/// `repairValidation` rewrites the same target WITH the marker. Because the target is an
/// approved file it is part of the applied patch, so the marker also satisfies post-apply
/// validation in the main repo (keeping the test deterministic end-to-end).
private struct RepairingAgent: AgentRunner {
    let target: String
    static let marker = "VALIDATION_OK"
    var supportsRepair: Bool { true }

    func plan(_ request: PlanRequest) async throws -> AgentPlanResult {
        let change = PlanChange(reason: "doc-diff:docs/technical-spec.md:L1-L2", targetFiles: [target],
                                kind: "modify", rationale: "Repairing agent writes target")
        return AgentPlanResult(plan: ProposedPlan(summary: "Repair plan", changes: [change], risk: "low"))
    }

    func implement(_ request: ImplementRequest) async throws -> AgentRunResult {
        // First pass: write the target without the required marker → validation fails.
        try write("let v = 5\n", to: target, in: request.cwd)
        return AgentRunResult()
    }

    func repairValidation(_ request: RepairRequest) async throws -> AgentRunResult {
        // Repair: add the marker so the validation `grep` passes on the next attempt.
        try write("let v = 5 // \(Self.marker)\n", to: target, in: request.base.cwd)
        return AgentRunResult()
    }

    private func write(_ text: String, to path: String, in cwd: URL) throws {
        let url = cwd.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

@Test func runFlowRepairsValidationFailureThenApplies() async throws {
    let fx = try await detdocRepo()
    // Validation fails until the repaired target contains the marker. Config is committed so the
    // worktree (created from HEAD) inherits it; the marker rides the patch into main too.
    // autoCommit:false retains run artifacts so the failure log survives for the assertion.
    try fx.write(".detdoc/config.yml",
                 "apply:\n  autoCommit: false\nvalidation:\n  commands:\n    - name: marker\n      run: grep -q \(RepairingAgent.marker) src/app.swift\n")
    try await fx.commitAll("configure repair validation")
    try fx.write("docs/idea.md", "changed idea\n")

    let engine = DetDocEngine(root: fx.root, agent: RepairingAgent(target: "src/app.swift"))
    let result = try await drive(engine, mode: .run, plan: .approve, apply: .apply)
    #expect(result?.applied == true)

    // The first validation attempt failed, so a failure log must have been written.
    let store = ArtifactStore(projectRoot: fx.root)
    let runId = try #require(result?.runId)
    let logPath = store.runDir(runId).appendingPathComponent("validation-failure-1.log").path
    #expect(FileManager.default.fileExists(atPath: logPath),
            "expected validation-failure-1.log artifact from the first failed validation attempt")
}

/// FIX 1 regression: cancelling the stream consumer while the flow is suspended at the
/// `.planReady` gate must unwind the flow Task promptly. The flow Task is internal to the
/// engine, so we observe it indirectly: with `keepOnFailure == false`, proper cancellation
/// drives `runFlow`'s catch path, which removes the isolated worktree. Before the fix the
/// gate continuation leaks, the flow Task suspends forever, and the worktree is orphaned —
/// which this test detects (worktree never disappears) rather than hanging the suite.
@Test func runFlowCancelsCleanlyAtPlanGate() async throws {
    let fx = try await detdocRepo()
    // Disable keep-on-failure so a cancelled flow removes its worktree (observable signal).
    try fx.write(".detdoc/config.yml", "worktree:\n  keepOnFailure: false\napply:\n  autoCommit: true\n")
    try await fx.commitAll("disable keepOnFailure")
    try fx.write("docs/idea.md", "changed idea\n")
    let engine = DetDocEngine(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "let v = 9\n"))

    // Consume the stream and signal (via a continuation) the moment the plan gate is reached,
    // WITHOUT submitting a decision — so the flow Task suspends at the gate. We then cancel the
    // consumer, which terminates the stream and must unwind the suspended flow Task.
    let worktreesDir = fx.root.appendingPathComponent(".worktrees")
    let reachedGate = AsyncStream<Void>.makeStream()
    let consumer = Task {
        let stream = await engine.start(mode: .run)
        for try await event in stream {
            // Confirm the input gate so the flow advances to the plan gate.
            if case .inputReady = event { await engine.submitInputDecision(.confirm) }
            // Signal the gate but keep iterating (never submit a decision) so the flow Task
            // stays suspended at the gate and the stream stays alive until we cancel below.
            if case .planReady = event { reachedGate.continuation.yield(()) }
        }
    }

    // Wait until the flow has actually reached the gate (worktree created, agent planned).
    var gateIterator = reachedGate.stream.makeAsyncIterator()
    _ = await gateIterator.next()

    let worktreesAtGate = (try? FileManager.default.contentsOfDirectory(atPath: worktreesDir.path)) ?? []
    #expect(!worktreesAtGate.isEmpty, "expected a worktree to exist while suspended at the plan gate")

    consumer.cancel()

    // Poll (bounded) for the worktree to be cleaned up. If the flow Task leaked, it never is.
    var cleaned = false
    for _ in 0..<60 {  // up to ~3s
        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: worktreesDir.path)) ?? []
        if remaining.isEmpty { cleaned = true; break }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    #expect(cleaned, "flow Task did not unwind (worktree orphaned) after consumer cancellation at the plan gate")
}
