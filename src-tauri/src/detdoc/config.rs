use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use super::error::{DetDocError, DetDocResult};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DocsConfig {
    #[serde(default = "default_docs_include")]
    pub include: Vec<String>,
    #[serde(default = "default_docs_exclude")]
    pub exclude: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PathsConfig {
    #[serde(default = "default_paths_deny")]
    pub deny: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ValidationConfig {
    #[serde(default, deserialize_with = "deserialize_validation_commands")]
    pub commands: Vec<ValidationCommand>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ValidationCommand {
    pub name: String,
    pub run: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AgentConfig {
    #[serde(default = "default_agent_provider")]
    pub provider: String,
    #[serde(default)]
    pub model: Option<String>,
    #[serde(default = "default_thinking")]
    pub thinking: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorktreeConfig {
    #[serde(default = "default_true", rename = "keepOnFailure")]
    pub keep_on_failure: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ApplyConfig {
    #[serde(default = "default_true", rename = "autoCommit")]
    pub auto_commit: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DetDocConfig {
    #[serde(default = "default_docs_config")]
    pub docs: DocsConfig,
    #[serde(default = "default_paths_config")]
    pub paths: PathsConfig,
    #[serde(default = "default_validation_config")]
    pub validation: ValidationConfig,
    #[serde(default = "default_agent_config")]
    pub agent: AgentConfig,
    #[serde(default = "default_worktree_config")]
    pub worktree: WorktreeConfig,
    #[serde(default = "default_apply_config")]
    pub apply: ApplyConfig,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum ValidationCommandInput {
    String(String),
    Run { name: Option<String>, run: String },
    Command { name: Option<String>, command: String },
    Cmd { name: Option<String>, cmd: String },
}

fn deserialize_validation_commands<'de, D>(deserializer: D) -> Result<Vec<ValidationCommand>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let inputs = Vec::<ValidationCommandInput>::deserialize(deserializer)?;
    Ok(inputs
        .into_iter()
        .map(|input| match input {
            ValidationCommandInput::String(run) => ValidationCommand { name: run.clone(), run },
            ValidationCommandInput::Run { name, run } => ValidationCommand { name: name.unwrap_or_else(|| run.clone()), run },
            ValidationCommandInput::Command { name, command } => ValidationCommand { name: name.unwrap_or_else(|| command.clone()), run: command },
            ValidationCommandInput::Cmd { name, cmd } => ValidationCommand { name: name.unwrap_or_else(|| cmd.clone()), run: cmd },
        })
        .collect())
}

fn default_docs_include() -> Vec<String> { vec!["**/*.md".to_string()] }
fn default_docs_exclude() -> Vec<String> { vec![".detdoc/**".to_string(), "node_modules/**".to_string()] }
fn default_paths_deny() -> Vec<String> { vec![".env".to_string(), ".env.*".to_string(), "node_modules/**".to_string(), ".git/**".to_string()] }
fn default_agent_provider() -> String { "pi-rpc".to_string() }
fn default_thinking() -> String { "high".to_string() }
fn default_true() -> bool { true }
fn default_docs_config() -> DocsConfig { DocsConfig { include: default_docs_include(), exclude: default_docs_exclude() } }
fn default_paths_config() -> PathsConfig { PathsConfig { deny: default_paths_deny() } }
fn default_validation_config() -> ValidationConfig { ValidationConfig { commands: vec![] } }
fn default_agent_config() -> AgentConfig { AgentConfig { provider: default_agent_provider(), model: None, thinking: default_thinking() } }
fn default_worktree_config() -> WorktreeConfig { WorktreeConfig { keep_on_failure: true } }
fn default_apply_config() -> ApplyConfig { ApplyConfig { auto_commit: true } }

pub fn default_config() -> DetDocConfig {
    DetDocConfig {
        docs: default_docs_config(),
        paths: default_paths_config(),
        validation: default_validation_config(),
        agent: default_agent_config(),
        worktree: default_worktree_config(),
        apply: default_apply_config(),
    }
}

pub fn default_config_yaml() -> DetDocResult<String> {
    serde_yaml::to_string(&default_config()).map_err(|error| DetDocError::new("CONFIG_SERIALIZE_FAILED", error.to_string()))
}

pub fn config_path(root: &Path) -> PathBuf {
    root.join(".detdoc").join("config.yml")
}

pub fn load_config(root: &Path) -> DetDocResult<DetDocConfig> {
    let path = config_path(root);
    let content = fs::read_to_string(&path).map_err(|error| DetDocError::new("CONFIG_READ_FAILED", format!("{}: {}", path.display(), error)))?;
    serde_yaml::from_str(&content).map_err(|error| DetDocError::new("CONFIG_PARSE_FAILED", error.to_string()))
}

pub fn write_default_config(root: &Path) -> DetDocResult<()> {
    let path = config_path(root);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| DetDocError::new("CONFIG_CREATE_DIR_FAILED", error.to_string()))?;
    }
    fs::write(&path, default_config_yaml()?).map_err(|error| DetDocError::new("CONFIG_WRITE_FAILED", error.to_string()))
}

pub fn init_detdoc_files(root: &Path) -> DetDocResult<()> {
    write_if_missing(&config_path(root), &default_config_yaml()?)?;
    write_if_missing(&root.join(".detdoc/runs/.gitkeep"), "")?;
    for (path, content) in starter_docs() {
        write_if_missing(&root.join(path), content)?;
    }
    ensure_gitignore_entries(root)?;
    Ok(())
}

fn starter_docs() -> Vec<(&'static str, &'static str)> {
    vec![
        ("docs/idea.md", "# Project Idea\n\nDescribe the product in plain language.\n"),
        ("docs/technical-spec.md", "# Technical Specification\n\nKeep durable technical decisions here.\n"),
        ("docs/features/_guide.md", "# Feature Planning Guide\n\nUse this folder for free-form feature planning.\n"),
        ("docs/features/example-feature/brief.md", "# Example Feature Brief\n\n## Goal\n\nDescribe the user-visible behavior.\n"),
        ("docs/features/example-feature/plan.md", "# Example Feature Plan\n\nUse this file for free-form implementation planning.\n"),
        ("docs/features/example-feature/notes.md", "# Example Feature Notes\n\nUse this file for decisions and examples.\n"),
    ]
}

fn write_if_missing(path: &Path, content: &str) -> DetDocResult<()> {
    if path.exists() {
        return Ok(());
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| DetDocError::new("WRITE_DIR_FAILED", error.to_string()))?;
    }
    fs::write(path, content).map_err(|error| DetDocError::new("WRITE_FILE_FAILED", format!("{}: {}", path.display(), error)))
}

fn ensure_gitignore_entries(root: &Path) -> DetDocResult<()> {
    let path = root.join(".gitignore");
    let mut content = fs::read_to_string(&path).unwrap_or_default();
    let entries = [".DS_Store", ".detdoc/runs/*", "!.detdoc/runs/.gitkeep", ".worktrees/"];
    for entry in entries {
        if !content.lines().any(|line| line.trim() == entry) {
            if !content.is_empty() && !content.ends_with('\n') {
                content.push('\n');
            }
            content.push_str(entry);
            content.push('\n');
        }
    }
    fs::write(&path, content).map_err(|error| DetDocError::new("GITIGNORE_WRITE_FAILED", error.to_string()))
}
