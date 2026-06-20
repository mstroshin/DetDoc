use super::config::DetDocConfig;
use super::error::{DetDocError, DetDocResult};
use super::paths::{is_denied_path, is_doc_path};

pub fn validate_patch_paths(patch: &str, approved_targets: &[String], config: &DetDocConfig) -> DetDocResult<()> {
    for line in patch.lines().filter(|line| line.starts_with("+++ b/") || line.starts_with("--- a/")) {
        let path = line[6..].to_string();
        if path == "/dev/null" { continue; }
        if is_denied_path(&path, config) { return Err(DetDocError::new("PATCH_DENIED_PATH", path)); }
        if is_doc_path(&path, config) { return Err(DetDocError::new("PATCH_DOC_PATH", path)); }
        if !approved_targets.contains(&path) { return Err(DetDocError::new("PATCH_UNAPPROVED_PATH", path)); }
    }
    Ok(())
}
