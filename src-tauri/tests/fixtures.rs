use std::path::Path;
use std::process::Command;

pub fn git(root: &Path, args: &[&str]) -> String {
    let output = Command::new("git").args(args).current_dir(root).output().unwrap();
    if !output.status.success() {
        panic!("git {:?} failed: {}", args, String::from_utf8_lossy(&output.stderr));
    }
    String::from_utf8_lossy(&output.stdout).to_string()
}

pub fn init_repo() -> tempfile::TempDir {
    let temp = tempfile::tempdir().unwrap();
    git(temp.path(), &["init"]);
    git(temp.path(), &["config", "user.email", "detdoc@example.com"]);
    git(temp.path(), &["config", "user.name", "DetDoc Test"]);
    std::fs::write(temp.path().join("README.md"), "# Test\n").unwrap();
    git(temp.path(), &["add", "."]);
    git(temp.path(), &["commit", "-m", "initial"]);
    temp
}
