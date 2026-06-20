import Foundation
import Observation
import DetDocCore

@MainActor
@Observable
public final class RunPanelViewModel {
    public enum Stage: Sendable, Equatable {
        case idle, running, planPending, patchPending, completed, failed
    }

    public private(set) var stage: Stage = .idle
    public private(set) var currentPhase: RunPhase?
    public private(set) var logLines: [String] = []
    public private(set) var planReview: PlanReviewViewModel?
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
            } catch let e as DetDocError {
                self?.fail(e)
            } catch {
                self?.fail(DetDocError("ENGINE_FAILED", "\(error)"))
            }
        }
    }

    public func approvePlan() {
        planReview = nil
        stage = .running
        let engine = engine
        Task { await engine?.submitPlanDecision(.approve) }
    }

    public func rejectPlan() {
        let engine = engine
        Task { await engine?.submitPlanDecision(.reject) }
    }

    public func applyPatch() {
        patchReview = nil
        stage = .running
        let engine = engine
        Task { await engine?.submitApplyDecision(.apply) }
    }

    public func discardPatch() {
        let engine = engine
        Task { await engine?.submitApplyDecision(.discard) }
    }

    public func cancel() {
        task?.cancel()
    }

    private func handle(_ event: RunEvent) {
        switch event {
        case .progress(let phase, _):
            currentPhase = phase
        case .log(let line):
            logLines.append(line)
        case .planReady(let plan):
            planReview = PlanReviewViewModel(plan: plan)
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
    }

    private func fail(_ e: DetDocError) {
        error = e
        stage = .failed
    }

    private func reset() {
        currentPhase = nil
        logLines = []
        planReview = nil
        patchReview = nil
        result = nil
        error = nil
    }
}
