import Testing
@testable import DetDocViewModels
@testable import DetDocCore

@MainActor
@Test func planReviewExposesPlanFields() {
    let plan = ProposedPlan(summary: "do it", changes: [PlanChange(reason: "doc-diff:x", targetFiles: ["src/a.swift"], kind: "modify", rationale: "r")], questions: ["q1"], risk: "low")
    let vm = PlanReviewViewModel(plan: plan)
    #expect(vm.summary == "do it")
    #expect(vm.risk == "low")
    #expect(vm.questions == ["q1"])
    #expect(vm.changes.first?.targetFiles == ["src/a.swift"])
}

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
