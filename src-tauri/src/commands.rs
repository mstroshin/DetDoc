use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use serde::Serialize;

use crate::detdoc::agent::FakeAgentRunner;
use crate::detdoc::artifacts::ArtifactStore;
use crate::detdoc::config::{init_detdoc_files, load_config};
use crate::detdoc::flow::{apply_saved_run, run_doc_flow, RunFlowOptions};
use crate::detdoc::git::GitRepository;
use crate::detdoc::manifest::RunManifest;

#[derive(Debug, Serialize)]
pub struct ProjectStatus {
    root: String,
    initialized: bool,
    #[serde(rename = "piAvailable")]
    pi_available: bool,
    #[serde(rename = "dirtyFiles")]
    dirty_files: Vec<DirtyFile>,
}

#[derive(Debug, Serialize)]
pub struct DirtyFile { status: String, path: String }

#[derive(Debug, Serialize)]
pub struct DocFile { path: String, title: String }

#[derive(Debug, Serialize)]
pub struct RunSummary {
    #[serde(rename = "runId")]
    run_id: String,
    #[serde(rename = "hasPatch")]
    has_patch: bool,
    #[serde(rename = "approvedTargets")]
    approved_targets: Vec<String>,
}

#[tauri::command]
pub async fn ping() -> Result<String, String> { Ok("pong".to_string()) }

#[tauri::command]
pub async fn project_status(root: String) -> Result<ProjectStatus, String> {
    let path = PathBuf::from(&root);
    let repo = GitRepository::new(&path);
    let dirty_files = repo.status_porcelain().unwrap_or_default().into_iter().map(|entry| DirtyFile { status: entry.status, path: entry.path }).collect();
    Ok(ProjectStatus {
        root,
        initialized: path.join(".detdoc/config.yml").exists(),
        pi_available: pi_health_check().await.unwrap_or(false),
        dirty_files,
    })
}

#[tauri::command]
pub async fn detdoc_init(root: String) -> Result<(), String> {
    init_detdoc_files(Path::new(&root)).map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn docs_list(root: String) -> Result<Vec<DocFile>, String> {
    let root_path = PathBuf::from(&root);
    let _config = load_config(&root_path).map_err(|error| error.to_string())?;
    let mut docs = vec![];
    for entry in walkdir::WalkDir::new(root_path.join("docs")).into_iter().filter_map(Result::ok) {
        if entry.file_type().is_file() && entry.path().extension().and_then(|ext| ext.to_str()) == Some("md") {
            let relative = entry.path().strip_prefix(&root_path).unwrap().to_string_lossy().replace('\\', "/");
            let title = entry.path().file_stem().unwrap().to_string_lossy().to_string();
            docs.push(DocFile { path: relative, title });
        }
    }
    docs.sort_by(|a, b| a.path.cmp(&b.path));
    Ok(docs)
}

#[tauri::command]
pub async fn docs_read(root: String, path: String) -> Result<String, String> {
    fs::read_to_string(PathBuf::from(root).join(path)).map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn docs_write(root: String, path: String, markdown: String) -> Result<(), String> {
    fs::write(PathBuf::from(root).join(path), markdown).map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn runs_list(root: String) -> Result<Vec<RunSummary>, String> {
    let runs_root = PathBuf::from(&root).join(".detdoc/runs");
    let store = ArtifactStore::new(Path::new(&root));
    let mut runs = vec![];
    if !runs_root.exists() { return Ok(runs); }
    for entry in fs::read_dir(runs_root).map_err(|error| error.to_string())? {
        let entry = entry.map_err(|error| error.to_string())?;
        if !entry.file_type().map_err(|error| error.to_string())?.is_dir() { continue; }
        let run_id = entry.file_name().to_string_lossy().to_string();
        if let Ok(manifest) = store.read_json::<RunManifest>(&run_id, "manifest.json") {
            runs.push(RunSummary { run_id: run_id.clone(), has_patch: entry.path().join("changes.patch").exists(), approved_targets: manifest.approved_targets });
        }
    }
    runs.sort_by(|a, b| b.run_id.cmp(&a.run_id));
    Ok(runs)
}

#[tauri::command]
pub async fn run_start_fake(root: String, target: String, content: String) -> Result<crate::detdoc::events::RunFlowResult, String> {
    let agent = FakeAgentRunner::new(&target, &content);
    run_doc_flow(Path::new(&root), &agent, RunFlowOptions { auto_approve_plan: true, auto_apply: false, auto_commit: true }).map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn apply_saved_run_command(root: String, run_id: String, auto_commit: bool) -> Result<crate::detdoc::events::RunFlowResult, String> {
    apply_saved_run(Path::new(&root), &run_id, auto_commit).map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn pi_health_check() -> Result<bool, String> {
    Ok(Command::new("pi").arg("--version").output().map(|output| output.status.success()).unwrap_or(false))
}
