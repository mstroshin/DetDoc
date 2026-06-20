import Testing
@testable import DetDocCore

private func change(_ reason: String, _ targets: [String], kind: String = "modify") -> PlanChange {
    PlanChange(reason: reason, targetFiles: targets, kind: kind, rationale: "because")
}

private func plan(_ changes: [PlanChange], risk: String = "low") -> ProposedPlan {
    ProposedPlan(summary: "s", changes: changes, risk: risk)
}

@Test func validRunPlanPasses() throws {
    let p = plan([change("doc-diff:docs/spec.md:L1-L2", ["src/app.ts"])])
    let out = try PlanValidator.validate(p, config: .default, mode: .run)
    #expect(out == p)
}

@Test func emptyChangesIsRejected() {
    let p = ProposedPlan(summary: "s", changes: [], risk: "low")
    #expect { try PlanValidator.validate(p, config: .default, mode: .run) }
        throws: { ($0 as? DetDocError)?.code == "PLAN_EMPTY" }
}

@Test func invalidRiskIsRejected() {
    let p = plan([change("doc-diff:x", ["src/a.ts"])], risk: "extreme")
    #expect { try PlanValidator.validate(p, config: .default, mode: .run) }
        throws: { ($0 as? DetDocError)?.code == "PLAN_RISK_INVALID" }
}

@Test func invalidKindIsRejected() {
    let p = plan([change("doc-diff:x", ["src/a.ts"], kind: "refactor")])
    #expect { try PlanValidator.validate(p, config: .default, mode: .run) }
        throws: { ($0 as? DetDocError)?.code == "PLAN_KIND_INVALID" }
}

@Test func emptyTargetsIsRejected() {
    let p = plan([change("doc-diff:x", [])])
    #expect { try PlanValidator.validate(p, config: .default, mode: .run) }
        throws: { ($0 as? DetDocError)?.code == "PLAN_CHANGE_NO_TARGETS" }
}

@Test func runReasonMustStartWithDocDiff() {
    let p = plan([change("intent:fix", ["src/a.ts"])])
    #expect { try PlanValidator.validate(p, config: .default, mode: .run) }
        throws: { ($0 as? DetDocError)?.code == "PLAN_REASON_INVALID" }
}

@Test func fixReasonMustStartWithIntent() {
    let p = plan([change("doc-diff:x", ["src/a.ts"])])
    #expect { try PlanValidator.validate(p, config: .default, mode: .fix) }
        throws: { ($0 as? DetDocError)?.code == "PLAN_REASON_INVALID" }
}

@Test func deniedTargetIsRejected() {
    let p = plan([change("doc-diff:x", [".env"])])
    #expect { try PlanValidator.validate(p, config: .default, mode: .run) }
        throws: { ($0 as? DetDocError)?.code == "PLAN_TARGET_DENIED" }
}

@Test func docTargetIsRejected() {
    let p = plan([change("doc-diff:x", ["docs/idea.md"])])
    #expect { try PlanValidator.validate(p, config: .default, mode: .run) }
        throws: { ($0 as? DetDocError)?.code == "PLAN_TARGETS_DOC" }
}

@Test func approvedTargetsAreSortedAndDeduplicated() {
    let p = plan([
        change("doc-diff:x", ["src/b.ts", "src/a.ts"]),
        change("doc-diff:y", ["src/a.ts"]),
    ])
    #expect(PlanValidator.approvedTargets(from: p) == ["src/a.ts", "src/b.ts"])
}
