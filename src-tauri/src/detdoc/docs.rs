use super::config::DetDocConfig;
use super::error::{DetDocError, DetDocResult};
use super::git::GitRepository;
use super::paths::is_doc_path;

pub fn get_normalized_doc_diff(repo: &GitRepository, config: &DetDocConfig) -> DetDocResult<String> {
    let status = repo.status_porcelain()?;
    let non_doc: Vec<String> = status.iter().filter(|entry| !is_doc_path(&entry.path, config)).map(|entry| entry.path.clone()).collect();
    if !non_doc.is_empty() {
        return Err(DetDocError::new("DIRTY_NON_DOC_CHANGES", non_doc.join(", ")));
    }
    let doc_paths: Vec<String> = status.iter().map(|entry| entry.path.clone()).collect();
    if doc_paths.is_empty() {
        return Err(DetDocError::new("NO_DOC_CHANGES", "No documentation changes found"));
    }
    let mut args = vec!["diff", "--no-color", "--no-ext-diff", "--binary", "--"];
    for path in &doc_paths { args.push(path); }
    repo.git(&args)
}
