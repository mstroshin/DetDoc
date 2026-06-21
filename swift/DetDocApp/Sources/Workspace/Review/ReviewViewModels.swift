import Observation
import DetDocCore

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
