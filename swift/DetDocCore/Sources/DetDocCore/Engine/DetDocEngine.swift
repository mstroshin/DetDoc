import Foundation

public actor DetDocEngine {
    private let root: URL
    private let agent: any AgentRunner
    private let maxRepairAttempts = 2

    private var pendingInput: CheckedContinuation<InputDecision, Error>?
    private var pendingPlan: CheckedContinuation<PlanDecision, Error>?
    private var pendingApply: CheckedContinuation<ApplyDecision, Error>?

    public init(root: URL, agent: any AgentRunner) {
        self.root = root
        self.agent = agent
    }

    public func submitInputDecision(_ decision: InputDecision) {
        pendingInput?.resume(returning: decision)
        pendingInput = nil
    }

    public func submitPlanDecision(_ decision: PlanDecision) {
        pendingPlan?.resume(returning: decision)
        pendingPlan = nil
    }

    public func submitApplyDecision(_ decision: ApplyDecision) {
        pendingApply?.resume(returning: decision)
        pendingApply = nil
    }

    private func awaitInputDecision() async throws -> InputDecision {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<InputDecision, Error>) in
                self.pendingInput = c
            }
        } onCancel: {
            Task { await self.failPendingInput() }
        }
    }

    private func failPendingInput() {
        pendingInput?.resume(throwing: CancellationError())
        pendingInput = nil
    }

    /// Suspends at the plan-approval gate until a decision is submitted, or fails with
    /// `CancellationError` if the surrounding Task is cancelled. Without cancellation
    /// awareness a cancelled flow would suspend here forever and orphan its worktree.
    private func awaitPlanDecision() async throws -> PlanDecision {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<PlanDecision, Error>) in
                self.pendingPlan = c
            }
        } onCancel: {
            Task { await self.failPendingPlan() }
        }
    }

    private func awaitApplyDecision() async throws -> ApplyDecision {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<ApplyDecision, Error>) in
                self.pendingApply = c
            }
        } onCancel: {
            Task { await self.failPendingApply() }
        }
    }

    private func failPendingPlan() {
        pendingPlan?.resume(throwing: CancellationError())
        pendingPlan = nil
    }

    private func failPendingApply() {
        pendingApply?.resume(throwing: CancellationError())
        pendingApply = nil
    }

    public func start(mode: RunMode, message: String? = nil) -> AsyncThrowingStream<RunEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                DetDocLog.engine.notice("run start mode=\(mode.rawValue, privacy: .public)")
                do {
                    let result = try await self.runFlow(mode: mode, message: message) { event in
                        DetDocLog.engine.info("\(event.logLine, privacy: .public)")
                        continuation.yield(event)
                    }
                    DetDocLog.engine.notice("run finished run=\(result.runId, privacy: .public) applied=\(result.applied, privacy: .public)")
                    continuation.yield(.complete(result))
                    continuation.finish()
                } catch let error as DetDocError {
                    DetDocLog.engine.error("run failed code=\(error.code, privacy: .public) \(error.message, privacy: .public)")
                    continuation.yield(.error(error))
                    continuation.finish(throwing: error)
                } catch is CancellationError {
                    DetDocLog.engine.notice("run cancelled")
                    let wrapped = DetDocError("ENGINE_CANCELLED", "Run was cancelled.")
                    continuation.yield(.error(wrapped))
                    continuation.finish(throwing: wrapped)
                } catch {
                    DetDocLog.engine.error("run failed unexpectedly: \(error.localizedDescription, privacy: .public)")
                    let wrapped = DetDocError("ENGINE_FAILED", "\(error)")
                    continuation.yield(.error(wrapped))
                    continuation.finish(throwing: wrapped)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Outcome of running the flow inside the worktree, carrying back state the
    /// caller needs after the worktree closure returns (avoids `inout` across `await`).
    private struct WorktreeOutcome {
        var result: RunFlowResult
        var keepWorktree: Bool
    }

    private func runFlow(mode: RunMode, message: String?, emit: @Sendable @escaping (RunEvent) -> Void) async throws -> RunFlowResult {
        emit(.progress(phase: .loadConfig, message: "Loading DetDoc config"))
        let config = try ConfigStore().load(root: root)
        let mainRepo = GitRepository(root)

        emit(.progress(phase: .collectInput, message: mode == .run ? "Collecting documentation changes" : "Collecting fix intent"))
        let taskInput: String
        if mode == .run {
            taskInput = try await DocDiff.normalized(mainRepo, config: config)
        } else {
            try DirtyPolicy.assertClean(try await mainRepo.statusPorcelain(), config: config)
            let msg = message ?? ""
            if msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw DetDocError("EMPTY_FIX_MESSAGE", "detdoc fix requires a non-empty message.")
            }
            taskInput = msg
        }

        if mode == .run {
            emit(.progress(phase: .reviewInput, message: "Waiting for diff review"))
            emit(.inputReady(taskInput))
            if try await awaitInputDecision() == .cancel {
                throw DetDocError("RUN_CANCELLED_BY_USER", "Run cancelled before start.")
            }
        }

        emit(.progress(phase: .createRun, message: "Creating run artifacts"))
        let manifest = RunManifest.initial(mode: mode, baseCommit: try await mainRepo.headCommit())
        let store = ArtifactStore(projectRoot: root)
        try store.createRun(manifest)
        try store.writeText(manifest.runId, mode == .run ? "input.diff.md" : "intent.md", taskInput)

        emit(.progress(phase: .createWorktree, message: "Creating isolated worktree"))
        let worktree = try await WorktreeManager().createFromHead(mainRepo, runId: manifest.runId)
        do {
            let outcome = try await runInsideWorktree(mode: mode, taskInput: taskInput, config: config,
                                                      mainRepo: mainRepo, worktree: worktree, store: store,
                                                      manifest: manifest, keepWorktree: config.worktree.keepOnFailure,
                                                      emit: emit)
            if !outcome.keepWorktree {
                emit(.progress(phase: .cleanupWorktree, message: "Cleaning up isolated worktree"))
                try? await WorktreeManager().cleanup(mainRepo, worktree)
            }
            emit(.progress(phase: .done, message: "Run complete"))
            return outcome.result
        } catch {
            if !config.worktree.keepOnFailure {
                try? await WorktreeManager().cleanup(mainRepo, worktree)
            }
            throw error
        }
    }

    private func runInsideWorktree(mode: RunMode, taskInput: String, config: DetDocConfig,
                                   mainRepo: GitRepository, worktree: WorktreeHandle, store: ArtifactStore,
                                   manifest: RunManifest, keepWorktree: Bool,
                                   emit: @Sendable @escaping (RunEvent) -> Void) async throws -> WorktreeOutcome {
        var manifest = manifest
        var keepWorktree = keepWorktree
        let worktreeRepo = worktree.repo
        if mode == .run {
            emit(.progress(phase: .applyInputToWorktree, message: "Applying documentation changes to worktree"))
            try await worktreeRepo.applyPatch(taskInput)
        }

        emit(.progress(phase: .plan, message: "Agent is planning code changes"))
        let planResult = try await agent.plan(PlanRequest(mode: mode, input: taskInput, config: config, cwd: worktree.path))
        let proposed = try PlanValidator.validate(planResult.plan, config: config, mode: mode)
        try store.writeJSON(manifest.runId, "plan.proposed.json", proposed)

        emit(.progress(phase: .approvePlan, message: "Waiting for plan approval"))
        emit(.planReady(proposed))
        if try await awaitPlanDecision() == .reject {
            throw DetDocError("PLAN_NOT_APPROVED", "Plan was not approved.")
        }
        try store.writeJSON(manifest.runId, "plan.approved.json", proposed)
        let approvedTargets = PlanValidator.approvedTargets(from: proposed)
        manifest.approvedTargets = approvedTargets
        try store.writeJSON(manifest.runId, "manifest.json", manifest)

        emit(.progress(phase: .implement, message: "Agent is editing approved files"))
        var agentResult = try await agent.implement(ImplementRequest(mode: mode, input: taskInput, config: config, cwd: worktree.path,
                                                        approvedPlan: proposed, approvedTargets: approvedTargets, progress: nil))

        var patch = ""
        var changedFiles: [String] = []
        var validationLog = ""
        var attempt = 0
        while true {
            emit(.progress(phase: .collectPatch, message: "Collecting generated patch"))
            patch = try await PatchCollector.collect(worktreeRepo, approvedTargets: approvedTargets)
            emit(.progress(phase: .validatePatch, message: "Validating generated patch"))
            try PatchValidator.validatePaths(patch, approvedTargets: approvedTargets, config: config)
            changedFiles = try await worktreeRepo.changedFilesFromPatch(patch).sorted()
            do {
                let worktreeConfig = try ConfigStore().load(root: worktree.path)
                validationLog = try await ValidationRunner().run(commands: worktreeConfig.validation.commands, cwd: worktree.path)
                break
            } catch let error as DetDocError where error.code == "VALIDATION_FAILED" && agent.supportsRepair && attempt < maxRepairAttempts {
                attempt += 1
                try store.writeText(manifest.runId, "validation-failure-\(attempt).log", error.message)
                emit(.progress(phase: .repairValidation, message: "Agent is fixing validation failure (\(attempt)/\(maxRepairAttempts))"))
                let base = ImplementRequest(mode: mode, input: taskInput, config: config, cwd: worktree.path,
                                            approvedPlan: proposed, approvedTargets: approvedTargets, progress: nil)
                agentResult = try await agent.repairValidation(RepairRequest(base: base, validationLog: error.message, attempt: attempt))
            }
        }

        manifest.touchedFiles = changedFiles.map { path in
            TouchedFile(path: path, before: mainRepo.fileSha256(path), after: worktreeRepo.fileSha256(path))
        }
        try store.writeText(manifest.runId, "changes.patch", patch)
        try store.writeText(manifest.runId, "validation.log", validationLog)
        try store.writeJSON(manifest.runId, "manifest.json", manifest)

        emit(.progress(phase: .approveApply, message: "Waiting for apply approval"))
        emit(.patchReady(PatchReview(runId: manifest.runId, changedFiles: changedFiles, patch: patch, worktreePath: worktree.path.path)))
        if try await awaitApplyDecision() == .discard {
            keepWorktree = false
            return WorktreeOutcome(result: RunFlowResult(runId: manifest.runId, applied: false, patch: patch),
                                   keepWorktree: keepWorktree)
        }

        emit(.progress(phase: .applyPatch, message: "Merging validated worktree changes into main"))
        try await mainRepo.applyPatch(patch)
        keepWorktree = false
        emit(.progress(phase: .postApplyValidation, message: "Running validation in main worktree"))
        try await RunApplier().runPostApplyValidation(root: root, store: store, runId: manifest.runId)
        try await writeCodeLinks(agentResult.codeLinks, mainRepo: mainRepo, config: config)
        // Run artifacts are only deleted when auto-committing; otherwise they are intentionally
        // retained so the run stays re-appliable, so only announce cleanup in that case.
        if config.apply.autoCommit {
            emit(.progress(phase: .cleanupRun, message: "Removing run artifacts"))
        }
        emit(.progress(phase: .commit, message: "Committing applied changes"))
        try await RunApplier().commitOrStage(repo: mainRepo, runId: manifest.runId, autoCommit: config.apply.autoCommit, store: store)
        return WorktreeOutcome(result: RunFlowResult(runId: manifest.runId, applied: true, patch: patch),
                               keepWorktree: keepWorktree)
    }

    /// Write the agent's doc→code links as a trailing HTML-comment block into each input
    /// doc, idempotently. Restricted to docs that are part of this run's input (currently
    /// dirty docs in main), so the agent can't annotate unrelated files. Staged by the
    /// subsequent `git add -A`, so links land in the same `DetDoc apply` commit.
    private func writeCodeLinks(_ links: [CodeLink], mainRepo: GitRepository, config: DetDocConfig) async throws {
        guard !links.isEmpty else { return }
        let policy = PathPolicy(config: config)
        let inputDocs = Set(try await mainRepo.statusPorcelain().map(\.path).filter { policy.isDoc($0) })
        let filtered = links.filter { inputDocs.contains($0.docPath) }
        if filtered.isEmpty {
            DetDocLog.engine.notice("writeCodeLinks: \(links.count, privacy: .public) link(s) produced but none matched an input doc; all dropped")
        }
        for (docPath, docLinks) in Dictionary(grouping: filtered, by: \.docPath) {
            let url = mainRepo.cwd.appendingPathComponent(docPath)
            guard let original = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let updated = CodeLinkBlock.apply(to: original, links: docLinks)
            if updated != original { try updated.write(to: url, atomically: true, encoding: .utf8) }
        }
    }
}
