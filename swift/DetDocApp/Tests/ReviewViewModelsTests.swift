import Testing
@testable import DetDoc
@testable import DetDocCore

@MainActor
@Test func patchReviewParsesDiff() {
    let review = PatchReview(runId: "r1", changedFiles: ["src/a.swift"], patch: """
    diff --git a/src/a.swift b/src/a.swift
    +++ b/src/a.swift
    +new
    """, worktreePath: "/tmp/wt")
    let vm = PatchReviewViewModel(review: review)
    #expect(vm.changedFiles == ["src/a.swift"])
    #expect(vm.diffFiles.first?.path == "src/a.swift")
    #expect(vm.worktreePath == "/tmp/wt")
}
