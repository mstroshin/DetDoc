public enum PlanValidator {
    private static let validKinds: Set<String> = ["create", "modify", "delete", "rename"]
    private static let validRisks: Set<String> = ["low", "medium", "high"]

    public static func validate(_ plan: ProposedPlan, config: DetDocConfig, mode: RunMode) throws -> ProposedPlan {
        if plan.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || plan.changes.isEmpty {
            throw DetDocError("PLAN_EMPTY", "Plan summary and changes are required")
        }
        if !validRisks.contains(plan.risk) {
            throw DetDocError("PLAN_RISK_INVALID", "Invalid risk: \(plan.risk)")
        }
        let policy = PathPolicy(config: config)
        for change in plan.changes {
            if !validKinds.contains(change.kind) {
                throw DetDocError("PLAN_KIND_INVALID", "Invalid change kind: \(change.kind)")
            }
            if change.targetFiles.isEmpty {
                throw DetDocError("PLAN_CHANGE_NO_TARGETS", "plan change must list at least one target file")
            }
            switch mode {
            case .run where !change.reason.hasPrefix("doc-diff:"):
                throw DetDocError("PLAN_REASON_INVALID", "run plan change must use doc-diff reason: \(change.reason)")
            case .fix where !change.reason.hasPrefix("intent:"):
                throw DetDocError("PLAN_REASON_INVALID", "fix plan change must use intent reason: \(change.reason)")
            default:
                break
            }
            for target in change.targetFiles {
                if policy.isDenied(target) {
                    throw DetDocError("PLAN_TARGET_DENIED", "plan targets denied path: \(target)")
                }
                if policy.isDoc(target) {
                    throw DetDocError("PLAN_TARGETS_DOC", "plans must not target documentation files: \(target)")
                }
            }
        }
        return plan
    }

    public static func approvedTargets(from plan: ProposedPlan) -> [String] {
        var set = Set<String>()
        for change in plan.changes { set.formUnion(change.targetFiles) }
        return set.sorted()
    }
}
