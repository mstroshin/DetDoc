import Foundation
import Observation
import DetDocCore

@MainActor
@Observable
public final class RunPanelViewModel {
    nonisolated public enum Stage: Sendable, Equatable {
        case idle, running, inputPending, planPending, patchPending, completed, failed
    }

    public private(set) var stage: Stage = .idle
    public private(set) var inputDiff: String?
    public private(set) var currentPhase: RunPhase?
    public private(set) var planReview: ProposedPlan?
    public private(set) var patchReview: PatchReviewViewModel?
    public private(set) var result: RunFlowResult?
    public private(set) var error: DetDocError?

    private let root: URL
    private let agent: any AgentRunner
    private var engine: DetDocEngine?
    private var task: Task<Void, Never>?

    public init(root: URL, agent: any AgentRunner) {
        self.root = root
        self.agent = agent
    }

    public func start(mode: RunMode, message: String? = nil) {
        guard stage == .idle || stage == .completed || stage == .failed else { return }
        reset()
        stage = .running
        let engine = DetDocEngine(root: root, agent: agent)
        self.engine = engine
        task = Task { [weak self] in
            do {
                let stream = await engine.start(mode: mode, message: message)
                for try await event in stream {
                    self?.handle(event)
                }
                // AsyncThrowingStream exits the for loop normally (not via throw) when the
                // consumer task is cancelled and the stream terminates via onTermination.
                // Detect this and surface it as ENGINE_CANCELLED so the UI reaches .failed.
                if Task.isCancelled {
                    self?.fail(DetDocError("ENGINE_CANCELLED", "Run cancelled"))
                }
            } catch let e as DetDocError {
                self?.fail(e)
            } catch is CancellationError {
                // Direct CancellationError throw (e.g. from try Task.checkCancellation()
                // called before the stream loop) — normalise to ENGINE_CANCELLED so the UI
                // always receives a stable, identifiable code rather than ENGINE_FAILED.
                self?.fail(DetDocError("ENGINE_CANCELLED", "Run cancelled"))
            } catch {
                self?.fail(DetDocError("ENGINE_FAILED", "\(error)"))
            }
        }
    }

    public func confirmInput() {
        DetDocLog.run.notice("user confirmed input diff")
        inputDiff = nil
        stage = .running
        let engine = engine
        Task { await engine?.submitInputDecision(.confirm) }
    }

    /// Deliberately does NOT move `stage` synchronously (unlike `confirmInput`). The stage only
    /// reaches `.idle` once the engine's `RUN_CANCELLED_BY_USER` error round-trips back through the
    /// stream into `fail`. Setting `.idle` here would pass `start()`'s guard immediately, letting the
    /// user launch a fresh run that the old task's late error could then clobber back to `.idle`.
    public func cancelInput() {
        DetDocLog.run.notice("user cancelled input diff")
        let engine = engine
        Task { await engine?.submitInputDecision(.cancel) }
    }

    public func approvePlan() {
        DetDocLog.run.notice("user approved plan")
        planReview = nil
        stage = .running
        let engine = engine
        Task { await engine?.submitPlanDecision(.approve) }
    }

    public func rejectPlan() {
        DetDocLog.run.notice("user rejected plan")
        let engine = engine
        Task { await engine?.submitPlanDecision(.reject) }
    }

    public func applyPatch() {
        DetDocLog.run.notice("user applied patch")
        patchReview = nil
        stage = .running
        let engine = engine
        Task { await engine?.submitApplyDecision(.apply) }
    }

    public func discardPatch() {
        DetDocLog.run.notice("user discarded patch")
        let engine = engine
        Task { await engine?.submitApplyDecision(.discard) }
    }

    public func cancel() {
        DetDocLog.run.notice("user cancelled run")
        task?.cancel()
    }

    private func handle(_ event: RunEvent) {
        switch event {
        case .progress(let phase, _):
            currentPhase = phase
        case .inputReady(let diff):
            inputDiff = diff
            stage = .inputPending
        case .planReady(let plan):
            planReview = plan
            stage = .planPending
        case .patchReady(let review):
            patchReview = PatchReviewViewModel(review: review)
            stage = .patchPending
        case .error(let e):
            fail(e)
        case .complete(let r):
            result = r
            stage = .completed
        }
        DetDocLog.run.info("stage=\(String(describing: self.stage), privacy: .public)")
    }

    private func fail(_ e: DetDocError) {
        if e.code == "RUN_CANCELLED_BY_USER" {
            DetDocLog.run.notice("run cancelled at input gate")
            inputDiff = nil
            error = nil
            stage = .idle
            return
        }
        DetDocLog.run.error("run failed code=\(e.code, privacy: .public) \(e.message, privacy: .public)")
        error = e
        stage = .failed
    }

    private func reset() {
        inputDiff = nil
        currentPhase = nil
        planReview = nil
        patchReview = nil
        result = nil
        error = nil
    }
}
