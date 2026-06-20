mod fixtures;

use detdoc_gui::detdoc::git::GitRepository;
use detdoc_gui::detdoc::worktree::WorktreeManager;

#[test]
fn status_porcelain_parses_dirty_files() {
    let repo_dir = fixtures::init_repo();
    std::fs::create_dir_all(repo_dir.path().join("docs")).unwrap();
    std::fs::write(repo_dir.path().join("docs/spec.md"), "# Spec\n").unwrap();
    std::fs::write(repo_dir.path().join("src.txt"), "dirty\n").unwrap();

    let repo = GitRepository::new(repo_dir.path());
    let status = repo.status_porcelain().unwrap();
    assert!(status.iter().any(|entry| entry.path == "docs/spec.md"));
    assert!(status.iter().any(|entry| entry.path == "src.txt"));
}

#[test]
fn worktree_create_and_cleanup_use_run_id_branch() {
    let repo_dir = fixtures::init_repo();
    std::fs::write(repo_dir.path().join(".gitignore"), ".worktrees/\n").unwrap();
    fixtures::git(repo_dir.path(), &["add", ".gitignore"]);
    fixtures::git(repo_dir.path(), &["commit", "-m", "ignore worktrees"]);

    let repo = GitRepository::new(repo_dir.path());
    let run_id = "20260620T120000Z-run-test1234";
    let handle = WorktreeManager::new().create_from_head(&repo, run_id).unwrap();
    assert!(handle.path.exists());
    assert_eq!(fixtures::git(&handle.path, &["branch", "--show-current"]).trim(), run_id);

    WorktreeManager::new().cleanup(&repo, &handle).unwrap();
    assert!(!handle.path.exists());
    let branches = fixtures::git(repo_dir.path(), &["branch", "--list", run_id]);
    assert!(branches.trim().is_empty());
}
