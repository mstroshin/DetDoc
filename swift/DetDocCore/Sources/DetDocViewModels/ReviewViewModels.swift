import Observation
import DetDocCore

@MainActor
@Observable
public final class PlanReviewViewModel {
    public let plan: ProposedPlan
    public init(plan: ProposedPlan) { self.plan = plan }
    public var summary: String { plan.summary }
    public var risk: String { plan.risk }
    public var questions: [String] { plan.questions }
    public var changes: [PlanChange] { plan.changes }
}

@MainActor
@Observable
public final class PatchReviewViewModel {
    public let review: PatchReview
    public let diffFiles: [DiffFile]
    public init(review: PatchReview) {
        self.review = review
        self.diffFiles = DiffModel.parse(review.patch)
    }
    public var changedFiles: [String] { review.changedFiles }
    public var worktreePath: String { review.worktreePath }
}
