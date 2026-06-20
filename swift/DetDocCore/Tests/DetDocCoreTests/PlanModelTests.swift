import Foundation
import Testing
@testable import DetDocCore

@Test func planDecodesWithCamelCaseTargetFiles() throws {
    let json = """
    {
      "summary": "do the thing",
      "changes": [
        { "reason": "doc-diff:docs/spec.md:L1-L2", "targetFiles": ["src/app.ts"], "kind": "modify", "rationale": "because" }
      ],
      "risk": "low"
    }
    """
    let plan = try JSONDecoder().decode(ProposedPlan.self, from: Data(json.utf8))
    #expect(plan.summary == "do the thing")
    #expect(plan.changes.first?.targetFiles == ["src/app.ts"])
    #expect(plan.questions == [])  // defaulted when absent
    #expect(plan.risk == "low")
}
