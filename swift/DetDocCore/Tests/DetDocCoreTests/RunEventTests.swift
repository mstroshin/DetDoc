@testable import DetDocCore
import Testing

@Test func runPhaseHasStableRawValues() {
    #expect(RunPhase.plan.rawValue == "plan")
    #expect(RunPhase.approveApply.rawValue == "approve_apply")
    #expect(RunPhase.done.rawValue == "done")
}
