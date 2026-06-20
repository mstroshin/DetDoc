use std::path::Path;

use super::agent::AgentRunner;
use super::artifacts::ArtifactStore;
use super::config::load_config;
use super::docs::get_normalized_doc_diff;
use super::error::{DetDocError, DetDocResult};
use super::events::RunFlowResult;
use super::git::GitRepository;
use super::manifest::{create_run_id, RunManifest};
use super::plan::{approved_targets_from_plan, validate_proposed_plan, RunMode};
use super::validation::validate_patch_paths;
use super::worktree::WorktreeManager;

pub struct RunFlowOptions {
    pub auto_approve_plan: bool,
    pub auto_apply: bool,
    pub auto_commit: bool,
}

pub fn run_doc_flow(root: &Path, agent: &dyn AgentRunner, options: RunFlowOptions) -> DetDocResult<RunFlowResult> {
    let config = load_config(root)?;
    let main_repo = GitRepository::new(root);
    let input = get_normalized_doc_diff(&main_repo, &config)?;
    let run_id = create_run_id(RunMode::Run);
    let mut manifest = RunManifest { run_id: run_id.clone(), mode: RunMode::Run, base_commit: main_repo.head()?, approved_targets: vec![] };
    let store = ArtifactStore::new(root);
    store.create_run(&manifest)?;
    store.write_text(&run_id, "input.diff.md", &input)?;

    let manager = WorktreeManager::new();
    let worktree = manager.create_from_head(&main_repo, &run_id)?;
    let worktree_repo = GitRepository::new(&worktree.path);
    worktree_repo.apply_patch(&input)?;

    let plan = validate_proposed_plan(agent.plan(RunMode::Run, &input, &config, &worktree.path)?, &config, RunMode::Run)?;
    store.write_json(&run_id, "plan.proposed.json", &plan)?;
    if !options.auto_approve_plan { return Err(DetDocError::new("PLAN_APPROVAL_REQUIRED", "GUI approval is required")); }
    store.write_json(&run_id, "plan.approved.json", &plan)?;
    manifest.approved_targets = approved_targets_from_plan(&plan);
    store.write_json(&run_id, "manifest.json", &manifest)?;

    agent.implement(&manifest.approved_targets, &worktree.path)?;
    let mut add_args = vec!["add", "-N", "--"];
    for target in &manifest.approved_targets { add_args.push(target); }
    let _ = worktree_repo.git(&add_args);
    let mut args = vec!["diff", "--no-color", "--no-ext-diff", "--binary", "--"];
    for target in &manifest.approved_targets { args.push(target); }
    let patch = worktree_repo.git(&args)?;
    if patch.trim().is_empty() {
        return Err(DetDocError::new("EMPTY_PATCH", "Agent produced no code changes for approved target files"));
    }
    validate_patch_paths(&patch, &manifest.approved_targets, &config)?;
    store.write_text(&run_id, "changes.patch", &patch)?;

    let applied = if options.auto_apply {
        apply_saved_run(root, &run_id, options.auto_commit)?.applied
    } else { false };
    manager.cleanup(&main_repo, &worktree)?;
    Ok(RunFlowResult { run_id, applied, patch })
}

pub fn apply_saved_run(root: &Path, run_id: &str, auto_commit: bool) -> DetDocResult<RunFlowResult> {
    let store = ArtifactStore::new(root);
    let manifest: RunManifest = store.read_json(run_id, "manifest.json")?;
    let patch = store.read_text(run_id, "changes.patch")?;
    let repo = GitRepository::new(root);
    let head = repo.head()?;
    if head != manifest.base_commit {
        return Err(DetDocError::new(
            "APPLY_BASE_MISMATCH",
            format!("HEAD ({}) does not match the saved run base commit ({})", head, manifest.base_commit),
        ));
    }
    repo.apply_patch(&patch)?;
    if auto_commit {
        let mut args = vec!["add", "--"];
        for target in &manifest.approved_targets { args.push(target); }
        repo.git(&args)?;
        repo.git(&["commit", "-m", &format!("DetDoc apply {}", run_id)])?;
        store.delete_run(run_id)?;
    } else {
        let mut args = vec!["add", "--"];
        for target in &manifest.approved_targets { args.push(target); }
        repo.git(&args)?;
    }
    Ok(RunFlowResult { run_id: run_id.to_string(), applied: true, patch })
}
