use std::process::Command;

use super::error::{DetDocError, DetDocResult};

pub fn check_pi_available() -> bool {
    Command::new("pi").arg("--version").output().map(|output| output.status.success()).unwrap_or(false)
}

pub fn split_jsonl_records(bytes: &[u8]) -> DetDocResult<Vec<String>> {
    let text = String::from_utf8(bytes.to_vec()).map_err(|error| DetDocError::new("PI_RPC_UTF8_INVALID", error.to_string()))?;
    Ok(text
        .split('\n')
        .filter_map(|record| {
            let trimmed = record.strip_suffix('\r').unwrap_or(record);
            if trimmed.is_empty() { None } else { Some(trimmed.to_string()) }
        })
        .collect())
}

pub struct PiRpcClient;

impl PiRpcClient {
    pub fn new() -> Self { Self }
}

pub struct PiRpcAgentRunner;

impl PiRpcAgentRunner {
    pub fn new() -> Self { Self }
}
