use std::fs;
use std::path::{Path, PathBuf};

use serde::{de::DeserializeOwned, Serialize};

use super::error::{DetDocError, DetDocResult};
use super::manifest::RunManifest;

pub struct ArtifactStore { root: PathBuf }

impl ArtifactStore {
    pub fn new(project_root: &Path) -> Self { Self { root: project_root.join(".detdoc/runs") } }
    pub fn run_dir(&self, run_id: &str) -> PathBuf { self.root.join(run_id) }
    pub fn create_run(&self, manifest: &RunManifest) -> DetDocResult<()> {
        fs::create_dir_all(self.run_dir(&manifest.run_id)).map_err(|error| DetDocError::new("ARTIFACT_DIR_FAILED", error.to_string()))?;
        self.write_json(&manifest.run_id, "manifest.json", manifest)
    }
    pub fn write_json<T: Serialize>(&self, run_id: &str, name: &str, value: &T) -> DetDocResult<()> {
        let content = serde_json::to_string_pretty(value).map_err(|error| DetDocError::new("ARTIFACT_JSON_FAILED", error.to_string()))?;
        self.write_text(run_id, name, &(content + "\n"))
    }
    pub fn read_json<T: DeserializeOwned>(&self, run_id: &str, name: &str) -> DetDocResult<T> {
        let content = fs::read_to_string(self.run_dir(run_id).join(name)).map_err(|error| DetDocError::new("ARTIFACT_READ_FAILED", error.to_string()))?;
        serde_json::from_str(&content).map_err(|error| DetDocError::new("ARTIFACT_PARSE_FAILED", error.to_string()))
    }
    pub fn write_text(&self, run_id: &str, name: &str, content: &str) -> DetDocResult<()> {
        fs::write(self.run_dir(run_id).join(name), content).map_err(|error| DetDocError::new("ARTIFACT_WRITE_FAILED", error.to_string()))
    }
    pub fn read_text(&self, run_id: &str, name: &str) -> DetDocResult<String> {
        fs::read_to_string(self.run_dir(run_id).join(name)).map_err(|error| DetDocError::new("ARTIFACT_READ_FAILED", error.to_string()))
    }
    pub fn delete_run(&self, run_id: &str) -> DetDocResult<()> {
        fs::remove_dir_all(self.run_dir(run_id)).map_err(|error| DetDocError::new("ARTIFACT_DELETE_FAILED", error.to_string()))
    }
}
