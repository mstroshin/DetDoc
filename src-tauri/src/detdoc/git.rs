use std::path::{Path, PathBuf};
use std::process::Command;

use super::error::{DetDocError, DetDocResult};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GitStatusEntry {
    pub status: String,
    pub path: String,
}

#[derive(Debug, Clone)]
pub struct GitRepository {
    pub cwd: PathBuf,
}

impl GitRepository {
    pub fn new(path: impl AsRef<Path>) -> Self {
        Self { cwd: path.as_ref().to_path_buf() }
    }

    pub fn git(&self, args: &[&str]) -> DetDocResult<String> {
        let output = Command::new("git")
            .args(args)
            .current_dir(&self.cwd)
            .output()
            .map_err(|error| DetDocError::new("GIT_SPAWN_FAILED", error.to_string()))?;
        if !output.status.success() {
            return Err(DetDocError::new(
                "GIT_COMMAND_FAILED",
                format!("git {:?}: {}", args, String::from_utf8_lossy(&output.stderr)),
            ));
        }
        Ok(String::from_utf8_lossy(&output.stdout).to_string())
    }

    pub fn head(&self) -> DetDocResult<String> {
        Ok(self.git(&["rev-parse", "HEAD"])?.trim().to_string())
    }

    pub fn status_porcelain(&self) -> DetDocResult<Vec<GitStatusEntry>> {
        let output = self.git(&["status", "--porcelain", "-uall"])?;
        Ok(output
            .lines()
            .filter_map(|line| {
                if line.len() < 4 { return None; }
                Some(GitStatusEntry {
                    status: line[0..2].trim().to_string(),
                    path: line[3..].trim().to_string(),
                })
            })
            .collect())
    }

    pub fn apply_patch(&self, patch: &str) -> DetDocResult<()> {
        let mut child = Command::new("git")
            .args(["apply", "--binary", "-"])
            .current_dir(&self.cwd)
            .stdin(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .map_err(|error| DetDocError::new("GIT_APPLY_SPAWN_FAILED", error.to_string()))?;
        use std::io::Write;
        child.stdin.as_mut().unwrap().write_all(patch.as_bytes()).map_err(|error| DetDocError::new("GIT_APPLY_STDIN_FAILED", error.to_string()))?;
        let output = child.wait_with_output().map_err(|error| DetDocError::new("GIT_APPLY_WAIT_FAILED", error.to_string()))?;
        if !output.status.success() {
            return Err(DetDocError::new("GIT_APPLY_FAILED", String::from_utf8_lossy(&output.stderr).to_string()));
        }
        Ok(())
    }
}
