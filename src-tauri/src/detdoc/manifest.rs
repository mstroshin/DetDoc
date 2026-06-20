use serde::{Deserialize, Serialize};

use super::plan::RunMode;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunManifest {
    #[serde(rename = "runId")]
    pub run_id: String,
    pub mode: RunMode,
    #[serde(rename = "baseCommit")]
    pub base_commit: String,
    #[serde(default, rename = "approvedTargets")]
    pub approved_targets: Vec<String>,
}

pub fn create_run_id(mode: RunMode) -> String {
    let prefix = match mode { RunMode::Run => "run", RunMode::Fix => "fix" };
    format!("{}-{}-{}", chrono::Utc::now().format("%Y%m%dT%H%M%SZ"), prefix, uuid::Uuid::new_v4().simple().to_string()[0..8].to_string())
}
