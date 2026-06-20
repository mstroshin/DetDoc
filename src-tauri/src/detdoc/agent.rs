use std::fs;
use std::path::Path;

use super::config::DetDocConfig;
use super::error::DetDocResult;
use super::plan::{PlanChange, ProposedPlan, RunMode};

pub trait AgentRunner {
    fn plan(&self, mode: RunMode, input: &str, config: &DetDocConfig, cwd: &Path) -> DetDocResult<ProposedPlan>;
    fn implement(&self, approved_targets: &[String], cwd: &Path) -> DetDocResult<()>;
}

pub struct FakeAgentRunner {
    target: String,
    content: String,
}

impl FakeAgentRunner {
    pub fn new(target: &str, content: &str) -> Self {
        Self { target: target.to_string(), content: content.to_string() }
    }
}

impl AgentRunner for FakeAgentRunner {
    fn plan(&self, mode: RunMode, _input: &str, _config: &DetDocConfig, _cwd: &Path) -> DetDocResult<ProposedPlan> {
        let reason = match mode { RunMode::Run => "doc-diff:docs/technical-spec.md:L1-L2", RunMode::Fix => "intent:fix" };
        Ok(ProposedPlan {
            summary: "Fake plan".to_string(),
            changes: vec![PlanChange { reason: reason.to_string(), target_files: vec![self.target.clone()], kind: "modify".to_string(), rationale: "Fake agent writes target".to_string() }],
            questions: vec![],
            risk: "low".to_string(),
        })
    }

    fn implement(&self, _approved_targets: &[String], cwd: &Path) -> DetDocResult<()> {
        let path = cwd.join(&self.target);
        if let Some(parent) = path.parent() { fs::create_dir_all(parent).unwrap(); }
        fs::write(path, &self.content).unwrap();
        Ok(())
    }
}
