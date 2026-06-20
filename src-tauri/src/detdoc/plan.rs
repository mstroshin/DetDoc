use std::collections::BTreeSet;

use serde::{Deserialize, Serialize};

use super::config::DetDocConfig;
use super::error::{DetDocError, DetDocResult};
use super::paths::{is_denied_path, is_doc_path};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RunMode {
    Run,
    Fix,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlanChange {
    pub reason: String,
    #[serde(rename = "targetFiles")]
    pub target_files: Vec<String>,
    pub kind: String,
    pub rationale: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProposedPlan {
    pub summary: String,
    pub changes: Vec<PlanChange>,
    #[serde(default)]
    pub questions: Vec<String>,
    pub risk: String,
}

pub fn validate_proposed_plan(plan: ProposedPlan, config: &DetDocConfig, mode: RunMode) -> DetDocResult<ProposedPlan> {
    if plan.summary.trim().is_empty() || plan.changes.is_empty() {
        return Err(DetDocError::new("PLAN_EMPTY", "Plan summary and changes are required"));
    }
    if !matches!(plan.risk.as_str(), "low" | "medium" | "high") {
        return Err(DetDocError::new("PLAN_RISK_INVALID", format!("Invalid risk: {}", plan.risk)));
    }
    for change in &plan.changes {
        if !matches!(change.kind.as_str(), "create" | "modify" | "delete" | "rename") {
            return Err(DetDocError::new("PLAN_KIND_INVALID", format!("Invalid change kind: {}", change.kind)));
        }
        if change.target_files.is_empty() {
            return Err(DetDocError::new("PLAN_CHANGE_NO_TARGETS", "plan change must list at least one target file"));
        }
        match mode {
            RunMode::Run if !change.reason.starts_with("doc-diff:") => {
                return Err(DetDocError::new("PLAN_REASON_INVALID", format!("run plan change must use doc-diff reason: {}", change.reason)));
            }
            RunMode::Fix if !change.reason.starts_with("intent:") => {
                return Err(DetDocError::new("PLAN_REASON_INVALID", format!("fix plan change must use intent reason: {}", change.reason)));
            }
            _ => {}
        }
        for target in &change.target_files {
            if is_denied_path(target, config) {
                return Err(DetDocError::new("PLAN_TARGET_DENIED", format!("plan targets denied path: {}", target)));
            }
            if is_doc_path(target, config) {
                return Err(DetDocError::new("PLAN_TARGETS_DOC", format!("plans must not target documentation files: {}", target)));
            }
        }
    }
    Ok(plan)
}

pub fn approved_targets_from_plan(plan: &ProposedPlan) -> Vec<String> {
    plan.changes
        .iter()
        .flat_map(|change| change.target_files.iter().cloned())
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect()
}
