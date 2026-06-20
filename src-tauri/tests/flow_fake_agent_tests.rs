mod fixtures;

use detdoc_gui::detdoc::agent::FakeAgentRunner;
use detdoc_gui::detdoc::flow::{apply_saved_run, run_doc_flow, RunFlowOptions};

#[test]
fn fake_run_creates_artifacts_and_applies_with_commit() {
    let repo_dir = fixtures::init_repo();
    detdoc_gui::detdoc::config::init_detdoc_files(repo_dir.path()).unwrap();
    fixtures::git(repo_dir.path(), &["add", ".detdoc", ".gitignore"]);
    fixtures::git(repo_dir.path(), &["commit", "-m", "init detdoc"]);

    std::fs::create_dir_all(repo_dir.path().join("docs")).unwrap();
    std::fs::write(repo_dir.path().join("docs/technical-spec.md"), "# Technical Specification\n\nAdd app value.\n").unwrap();
    std::fs::create_dir_all(repo_dir.path().join("src")).unwrap();
    std::fs::write(repo_dir.path().join("src/app.ts"), "export const value = 1;\n").unwrap();
    fixtures::git(repo_dir.path(), &["add", "src/app.ts", "docs"]);
    fixtures::git(repo_dir.path(), &["commit", "-m", "add app"]);
    std::fs::write(repo_dir.path().join("docs/technical-spec.md"), "# Technical Specification\n\nAdd app value 2.\n").unwrap();

    let agent = FakeAgentRunner::new("src/app.ts", "export const value = 2;\n");
    let result = run_doc_flow(repo_dir.path(), &agent, RunFlowOptions { auto_approve_plan: true, auto_apply: true, auto_commit: true }).unwrap();

    assert!(result.applied);
    assert_eq!(std::fs::read_to_string(repo_dir.path().join("src/app.ts")).unwrap(), "export const value = 2;\n");
    assert!(!repo_dir.path().join(".worktrees").join(&result.run_id).exists());
    let log = fixtures::git(repo_dir.path(), &["log", "--oneline", "-1"]);
    assert!(log.contains(&format!("DetDoc apply {}", result.run_id)));
}

#[test]
fn apply_saved_run_can_stage_without_commit() {
    let repo_dir = fixtures::init_repo();
    detdoc_gui::detdoc::config::init_detdoc_files(repo_dir.path()).unwrap();
    std::fs::create_dir_all(repo_dir.path().join("src")).unwrap();
    std::fs::write(repo_dir.path().join("src/app.ts"), "export const value = 1;\n").unwrap();
    fixtures::git(repo_dir.path(), &["add", "."]);
    fixtures::git(repo_dir.path(), &["commit", "-m", "ready"]);

    let run_id = "20260620T120000Z-run-saved123";
    let run_dir = repo_dir.path().join(".detdoc/runs").join(run_id);
    std::fs::create_dir_all(&run_dir).unwrap();
    std::fs::write(run_dir.join("manifest.json"), format!(r#"{{"runId":"{}","mode":"run","baseCommit":"{}","approvedTargets":["src/app.ts"]}}"#, run_id, fixtures::git(repo_dir.path(), &["rev-parse", "HEAD"]).trim())).unwrap();

    std::fs::write(repo_dir.path().join("src/app.ts"), "export const value = 2;\n").unwrap();
    let patch = fixtures::git(repo_dir.path(), &["diff", "--", "src/app.ts"]);
    fixtures::git(repo_dir.path(), &["checkout", "--", "src/app.ts"]);
    std::fs::write(run_dir.join("changes.patch"), patch).unwrap();

    let result = apply_saved_run(repo_dir.path(), run_id, false).unwrap();
    assert!(result.applied);
    let status = fixtures::git(repo_dir.path(), &["status", "--porcelain"]);
    assert!(status.contains("M  src/app.ts"));
}

#[test]
fn apply_saved_run_rejects_moved_head() {
    let repo_dir = fixtures::init_repo();
    detdoc_gui::detdoc::config::init_detdoc_files(repo_dir.path()).unwrap();
    std::fs::create_dir_all(repo_dir.path().join("src")).unwrap();
    std::fs::write(repo_dir.path().join("src/app.ts"), "export const value = 1;\n").unwrap();
    fixtures::git(repo_dir.path(), &["add", "."]);
    fixtures::git(repo_dir.path(), &["commit", "-m", "ready"]);

    let run_id = "20260620T120000Z-run-moved123";
    let run_dir = repo_dir.path().join(".detdoc/runs").join(run_id);
    std::fs::create_dir_all(&run_dir).unwrap();
    std::fs::write(run_dir.join("manifest.json"), format!(r#"{{"runId":"{}","mode":"run","baseCommit":"{}","approvedTargets":["src/app.ts"]}}"#, run_id, fixtures::git(repo_dir.path(), &["rev-parse", "HEAD"]).trim())).unwrap();

    std::fs::write(repo_dir.path().join("src/app.ts"), "export const value = 2;\n").unwrap();
    let patch = fixtures::git(repo_dir.path(), &["diff", "--", "src/app.ts"]);
    fixtures::git(repo_dir.path(), &["checkout", "--", "src/app.ts"]);
    std::fs::write(run_dir.join("changes.patch"), patch).unwrap();

    // Move HEAD forward after the saved run was captured.
    std::fs::write(repo_dir.path().join("other.txt"), "unrelated\n").unwrap();
    fixtures::git(repo_dir.path(), &["add", "other.txt"]);
    fixtures::git(repo_dir.path(), &["commit", "-m", "move head"]);

    let error = apply_saved_run(repo_dir.path(), run_id, false).unwrap_err();
    assert_eq!(error.code(), "APPLY_BASE_MISMATCH");
}
