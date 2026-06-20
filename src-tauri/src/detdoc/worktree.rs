use std::fs;
use std::path::PathBuf;

use super::error::DetDocResult;
use super::git::GitRepository;

#[derive(Debug, Clone)]
pub struct WorktreeHandle {
    pub path: PathBuf,
    pub branch_name: String,
}

pub struct WorktreeManager;

impl WorktreeManager {
    pub fn new() -> Self { Self }

    pub fn create_from_head(&self, repo: &GitRepository, run_id: &str) -> DetDocResult<WorktreeHandle> {
        let path = repo.cwd.join(".worktrees").join(run_id);
        fs::create_dir_all(repo.cwd.join(".worktrees")).map_err(|error| super::error::DetDocError::new("WORKTREE_DIR_FAILED", error.to_string()))?;
        let path_string = path.to_string_lossy().to_string();
        let base = repo.head()?;
        repo.git(&["worktree", "add", "-b", run_id, &path_string, &base])?;
        Ok(WorktreeHandle { path, branch_name: run_id.to_string() })
    }

    pub fn cleanup(&self, repo: &GitRepository, handle: &WorktreeHandle) -> DetDocResult<()> {
        let path_string = handle.path.to_string_lossy().to_string();
        if handle.path.exists() {
            repo.git(&["worktree", "remove", "--force", &path_string])?;
        }
        repo.git(&["branch", "-D", &handle.branch_name])?;
        Ok(())
    }
}
