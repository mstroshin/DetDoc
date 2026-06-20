use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
pub struct RunFlowResult {
    #[serde(rename = "runId")]
    pub run_id: String,
    pub applied: bool,
    pub patch: String,
}
