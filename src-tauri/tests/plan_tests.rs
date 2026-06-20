use detdoc_gui::detdoc::config::default_config;
use detdoc_gui::detdoc::plan::{approved_targets_from_plan, validate_proposed_plan, PlanChange, ProposedPlan, RunMode};

fn valid_plan(reason: &str, target: &str) -> ProposedPlan {
    ProposedPlan {
        summary: "Change app behavior".to_string(),
        changes: vec![PlanChange {
            reason: reason.to_string(),
            target_files: vec![target.to_string()],
            kind: "modify".to_string(),
            rationale: "The docs require this code change.".to_string(),
        }],
        questions: vec![],
        risk: "low".to_string(),
    }
}

#[test]
fn run_plan_requires_doc_diff_reason() {
    let config = default_config();
    let error = validate_proposed_plan(valid_plan("intent:fix", "src/app.ts"), &config, RunMode::Run).unwrap_err();
    assert_eq!(error.code(), "PLAN_REASON_INVALID");
}

#[test]
fn fix_plan_requires_intent_reason() {
    let config = default_config();
    let error = validate_proposed_plan(valid_plan("doc-diff:docs/spec.md:L1-L2", "src/app.ts"), &config, RunMode::Fix).unwrap_err();
    assert_eq!(error.code(), "PLAN_REASON_INVALID");
}

#[test]
fn plans_cannot_target_docs_or_denied_paths() {
    let config = default_config();
    assert_eq!(validate_proposed_plan(valid_plan("doc-diff:docs/spec.md:L1-L2", "docs/spec.md"), &config, RunMode::Run).unwrap_err().code(), "PLAN_TARGETS_DOC");
    assert_eq!(validate_proposed_plan(valid_plan("doc-diff:docs/spec.md:L1-L2", ".env"), &config, RunMode::Run).unwrap_err().code(), "PLAN_TARGET_DENIED");
}

#[test]
fn approved_targets_are_unique_and_sorted() {
    let plan = ProposedPlan {
        summary: "Change app".to_string(),
        changes: vec![
            PlanChange { reason: "doc-diff:docs/spec.md:L1-L2".to_string(), target_files: vec!["src/b.ts".to_string(), "src/a.ts".to_string()], kind: "modify".to_string(), rationale: "A".to_string() },
            PlanChange { reason: "doc-diff:docs/spec.md:L3-L4".to_string(), target_files: vec!["src/a.ts".to_string()], kind: "modify".to_string(), rationale: "B".to_string() },
        ],
        questions: vec![],
        risk: "low".to_string(),
    };
    assert_eq!(approved_targets_from_plan(&plan), vec!["src/a.ts", "src/b.ts"]);
}
