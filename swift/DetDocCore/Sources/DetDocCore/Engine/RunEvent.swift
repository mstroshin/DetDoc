public enum RunPhase: String, Sendable {
    case loadConfig = "load_config"
    case collectInput = "collect_input"
    case reviewInput = "review_input"
    case createRun = "create_run"
    case createWorktree = "create_worktree"
    case applyInputToWorktree = "apply_input_to_worktree"
    case plan
    case approvePlan = "approve_plan"
    case implement
    case collectPatch = "collect_patch"
    case validatePatch = "validate_patch"
    case repairValidation = "repair_validation"
    case approveApply = "approve_apply"
    case applyPatch = "apply_patch"
    case postApplyValidation = "post_apply_validation"
    case cleanupRun = "cleanup_run"
    case commit
    case cleanupWorktree = "cleanup_worktree"
    case done
}

public struct PatchReview: Sendable {
    public let runId: String
    public let changedFiles: [String]
    public let patch: String
    public let worktreePath: String
    public init(runId: String, changedFiles: [String], patch: String, worktreePath: String) {
        self.runId = runId; self.changedFiles = changedFiles; self.patch = patch; self.worktreePath = worktreePath
    }
}

public enum RunEvent: Sendable {
    case progress(phase: RunPhase, message: String)
    case inputReady(String)
    case planReady(ProposedPlan)
    case patchReady(PatchReview)
    case error(DetDocError)
    case complete(RunFlowResult)

    /// One-line, content-free summary for OSLog (counts/codes, never patch/diff bodies).
    public var logLine: String {
        switch self {
        case .progress(let phase, let message): return "phase=\(phase.rawValue) \(message)"
        case .inputReady(let diff): return "inputReady bytes=\(diff.utf8.count)"
        case .planReady(let plan): return "planReady changes=\(plan.changes.count) risk=\(plan.risk)"
        case .patchReady(let review): return "patchReady files=\(review.changedFiles.count) run=\(review.runId)"
        case .error(let e): return "error=\(e.code) \(e.message)"
        case .complete(let r): return "complete run=\(r.runId) applied=\(r.applied)"
        }
    }
}

public enum PlanDecision: Sendable { case approve, reject }
public enum ApplyDecision: Sendable { case apply, discard }
public enum InputDecision: Sendable { case confirm, cancel }
