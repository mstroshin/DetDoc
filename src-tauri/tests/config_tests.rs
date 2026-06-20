use detdoc_gui::detdoc::config::{default_config, default_config_yaml, init_detdoc_files, load_config};

#[test]
fn default_config_matches_typescript_defaults() {
    let config = default_config();
    assert_eq!(config.docs.include, vec!["**/*.md"]);
    assert_eq!(config.docs.exclude, vec![".detdoc/**", "node_modules/**"]);
    assert_eq!(config.paths.deny, vec![".env", ".env.*", "node_modules/**", ".git/**"]);
    assert!(config.validation.commands.is_empty());
    assert_eq!(config.agent.provider, "pi-rpc");
    assert_eq!(config.agent.model, None);
    assert_eq!(config.agent.thinking, "high");
    assert!(config.worktree.keep_on_failure);
    assert!(config.apply.auto_commit);
}

#[test]
fn validation_command_aliases_are_normalized() {
    let temp = tempfile::tempdir().unwrap();
    let detdoc = temp.path().join(".detdoc");
    std::fs::create_dir_all(&detdoc).unwrap();
    std::fs::write(
        detdoc.join("config.yml"),
        r#"
docs:
  include: ["**/*.md"]
  exclude: [".detdoc/**", "node_modules/**"]
paths:
  deny: [".env", ".env.*", "node_modules/**", ".git/**"]
validation:
  commands:
    - npm test
    - name: Typecheck
      command: npm run typecheck
    - name: Build
      cmd: npm run build
agent:
  provider: pi-rpc
  model: null
  thinking: high
worktree:
  keepOnFailure: true
apply:
  autoCommit: false
"#,
    )
    .unwrap();

    let config = load_config(temp.path()).unwrap();
    assert_eq!(config.validation.commands[0].name, "npm test");
    assert_eq!(config.validation.commands[0].run, "npm test");
    assert_eq!(config.validation.commands[1].name, "Typecheck");
    assert_eq!(config.validation.commands[1].run, "npm run typecheck");
    assert_eq!(config.validation.commands[2].name, "Build");
    assert_eq!(config.validation.commands[2].run, "npm run build");
    assert!(!config.apply.auto_commit);
}

#[test]
fn init_creates_config_runs_gitkeep_starter_docs_and_gitignore_entries() {
    let temp = tempfile::tempdir().unwrap();
    init_detdoc_files(temp.path()).unwrap();

    assert!(temp.path().join(".detdoc/config.yml").exists());
    assert!(temp.path().join(".detdoc/runs/.gitkeep").exists());
    assert!(temp.path().join("docs/idea.md").exists());
    assert!(temp.path().join("docs/technical-spec.md").exists());
    assert!(temp.path().join("docs/features/_guide.md").exists());

    let gitignore = std::fs::read_to_string(temp.path().join(".gitignore")).unwrap();
    assert!(gitignore.contains(".DS_Store"));
    assert!(gitignore.contains(".detdoc/runs/*"));
    assert!(gitignore.contains("!.detdoc/runs/.gitkeep"));
    assert!(gitignore.contains(".worktrees/"));

    let yaml = default_config_yaml().unwrap();
    assert!(yaml.contains("keepOnFailure"));
    assert!(yaml.contains("autoCommit"));
}
