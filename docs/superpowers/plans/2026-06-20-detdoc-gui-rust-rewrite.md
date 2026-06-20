# DetDoc GUI Rust Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS-first Tauri + React GUI with a Rust DetDoc core that preserves existing DetDoc formats and safety behavior while the TypeScript CLI remains as a temporary parity reference.

**Architecture:** Add a new Tauri application beside the existing TypeScript code. Implement deterministic DetDoc orchestration in Rust modules under `src-tauri/src/detdoc`, expose it through typed Tauri commands/events, and build the React IDE-style workspace as the only product UI. Agent execution will be abstracted behind `AgentRunner`, with a fake runner for tests first and `pi --mode rpc` added after deterministic core parity is established.

**Tech Stack:** Rust 2021, Tauri 2, React, TypeScript, Vite, Tailwind, shadcn/ui/Radix, Tiptap, Vitest, Cargo tests, git CLI subprocesses, installed `pi --mode rpc` for real agent runs.

## Global Constraints

- MVP platform is macOS only.
- Keep existing TypeScript CLI/core in place as a temporary parity reference until the GUI reaches parity.
- Preserve `.detdoc/config.yml`, `.detdoc/runs/<run-id>/`, `manifest.json`, `plan.proposed.json`, `plan.approved.json`, `changes.patch`, and `.worktrees/<run-id>` compatibility.
- Do not bundle pi in the MVP; require `pi` in `PATH` and show GUI health/setup state if unavailable.
- Do not implement Windows/Linux support, multi-project manager, replay-first GUI, or pi sidecar bundling in this plan.
- Default apply behavior is auto-commit; when auto-commit is disabled, apply and stage approved target files without committing.
- Documentation files are read-only input for implementation; plans and patches that target docs are rejected.
- `run` uses dirty Markdown docs as intent; dirty non-doc changes block `run`.
- `fix` uses a user-authored intent and must not target docs.

---

## File Structure

Create the GUI app in-place without deleting the existing TypeScript CLI:

```txt
package.json                         # add GUI/Tauri scripts and frontend dependencies
vite.config.ts                       # Vite config for React frontend
index.html                           # Vite entrypoint
src-ui/                              # React frontend, separate from existing CLI src/
  main.tsx
  app/App.tsx
  app/types.ts
  components/ProjectShell.tsx
  components/DocsExplorer.tsx
  components/DocEditor.tsx
  components/DetDocPanel.tsx
  components/PlanReview.tsx
  components/PatchReview.tsx
  components/RunsView.tsx
  components/SettingsView.tsx
  lib/tauri.ts
  styles.css
src-tauri/
  Cargo.toml
  tauri.conf.json
  build.rs
  src/main.rs
  src/lib.rs
  src/commands.rs
  src/detdoc/mod.rs
  src/detdoc/error.rs
  src/detdoc/config.rs
  src/detdoc/git.rs
  src/detdoc/paths.rs
  src/detdoc/docs.rs
  src/detdoc/manifest.rs
  src/detdoc/artifacts.rs
  src/detdoc/plan.rs
  src/detdoc/validation.rs
  src/detdoc/worktree.rs
  src/detdoc/agent.rs
  src/detdoc/pi_rpc.rs
  src/detdoc/flow.rs
  src/detdoc/events.rs
  tests/fixtures.rs
  tests/config_tests.rs
  tests/plan_tests.rs
  tests/git_worktree_tests.rs
  tests/flow_fake_agent_tests.rs
```

Boundary rules:

- `src-tauri/src/detdoc/*` contains deterministic core logic and no Tauri UI types except event payload structs.
- `src-tauri/src/commands.rs` is the only Tauri command adapter layer.
- `src-ui/*` never shells out to git/pi directly; it calls Tauri commands and subscribes to events.
- Existing `src/core/*` TypeScript files remain unchanged except for docs/tests that compare behavior.

---

### Task 1: Scaffold Tauri, React, and Rust test harness

**Files:**
- Modify: `package.json`
- Create: `vite.config.ts`
- Create: `index.html`
- Create: `src-ui/main.tsx`
- Create: `src-ui/app/App.tsx`
- Create: `src-ui/styles.css`
- Create: `src-tauri/Cargo.toml`
- Create: `src-tauri/tauri.conf.json`
- Create: `src-tauri/build.rs`
- Create: `src-tauri/src/main.rs`
- Create: `src-tauri/src/lib.rs`
- Create: `src-tauri/src/commands.rs`
- Create: `src-tauri/src/detdoc/mod.rs`
- Create: `src-tauri/src/detdoc/error.rs`
- Test: `src-tauri/src/detdoc/error.rs`

**Interfaces:**
- Produces: `detdoc::error::DetDocError`, `detdoc::error::DetDocResult<T>`, `commands::ping() -> Result<String, String>`.
- Later tasks consume the Rust module layout and frontend entrypoint.

- [ ] **Step 1: Write the failing Rust error smoke test**

Add this to `src-tauri/src/detdoc/error.rs` first, before implementation:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn error_display_includes_code_and_message() {
        let error = DetDocError::new("CONFIG_MISSING", "DetDoc config is missing");
        assert_eq!(error.code(), "CONFIG_MISSING");
        assert_eq!(error.to_string(), "CONFIG_MISSING: DetDoc config is missing");
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
cd src-tauri
cargo test error_display_includes_code_and_message
```

Expected: FAIL because `Cargo.toml`, `DetDocError`, or the module does not exist yet.

- [ ] **Step 3: Add frontend and Tauri package scripts/dependencies**

Modify `package.json` so the top-level scripts include the existing scripts plus GUI scripts:

```json
{
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "dev": "tsx src/index.ts",
    "test": "vitest run",
    "typecheck": "tsc -p tsconfig.json --noEmit",
    "gui:dev": "tauri dev",
    "gui:build": "tauri build",
    "gui:test:rust": "cargo test --manifest-path src-tauri/Cargo.toml",
    "gui:test:ui": "vitest run src-ui",
    "gui:typecheck": "tsc -p tsconfig.json --noEmit"
  },
  "dependencies": {
    "@earendil-works/pi-coding-agent": "latest",
    "@tauri-apps/api": "^2.0.0",
    "@tiptap/extension-link": "^2.10.0",
    "@tiptap/extension-placeholder": "^2.10.0",
    "@tiptap/extension-typography": "^2.10.0",
    "@tiptap/pm": "^2.10.0",
    "@tiptap/react": "^2.10.0",
    "@tiptap/starter-kit": "^2.10.0",
    "boxen": "^8.0.1",
    "class-variance-authority": "^0.7.1",
    "clsx": "^2.1.1",
    "commander": "^14.0.0",
    "lucide-react": "^0.468.0",
    "ora": "^9.4.0",
    "picocolors": "^1.1.1",
    "picomatch": "^4.0.3",
    "tailwind-merge": "^2.6.0",
    "typebox": "^1.0.58",
    "yaml": "^2.8.1",
    "zod": "^4.1.12"
  },
  "devDependencies": {
    "@tauri-apps/cli": "^2.0.0",
    "@types/node": "^24.0.0",
    "@types/picomatch": "^4.0.3",
    "@types/react": "^18.3.12",
    "@types/react-dom": "^18.3.1",
    "@vitejs/plugin-react": "^4.3.4",
    "autoprefixer": "^10.4.20",
    "postcss": "^8.4.49",
    "tailwindcss": "^3.4.17",
    "tsx": "^4.20.5",
    "typescript": "^5.9.3",
    "vite": "^6.0.0",
    "vitest": "^4.0.0"
  }
}
```

Keep existing fields such as `name`, `version`, `private`, `type`, and `bin`. Do not remove existing CLI dependencies.

- [ ] **Step 4: Add Vite and React shell files**

Create `vite.config.ts`:

```ts
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  root: ".",
  build: {
    outDir: "dist-ui",
    emptyOutDir: true,
  },
  server: {
    port: 1420,
    strictPort: true,
  },
});
```

Create `index.html`:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>DetDoc</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src-ui/main.tsx"></script>
  </body>
</html>
```

Create `src-ui/main.tsx`:

```tsx
import React from "react";
import { createRoot } from "react-dom/client";
import { App } from "./app/App";
import "./styles.css";

createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
```

Create `src-ui/app/App.tsx`:

```tsx
export function App() {
  return (
    <main className="min-h-screen bg-slate-950 text-slate-100">
      <div className="border-b border-white/10 px-4 py-3 font-semibold">DetDoc GUI</div>
      <div className="p-4 text-sm text-slate-300">Tauri shell scaffold is ready.</div>
    </main>
  );
}
```

Create `src-ui/styles.css`:

```css
@tailwind base;
@tailwind components;
@tailwind utilities;

:root {
  color-scheme: dark;
  font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}

body {
  margin: 0;
}
```

- [ ] **Step 5: Add Rust/Tauri scaffold**

Create `src-tauri/Cargo.toml`:

```toml
[package]
name = "detdoc_gui"
version = "0.1.0"
edition = "2021"

[lib]
name = "detdoc_gui"
path = "src/lib.rs"

[[bin]]
name = "detdoc_gui"
path = "src/main.rs"

[build-dependencies]
tauri-build = { version = "2", features = [] }

[dependencies]
anyhow = "1"
chrono = { version = "0.4", features = ["serde"] }
globset = "0.4"
hex = "0.4"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
serde_yaml = "0.9"
sha2 = "0.10"
tauri = { version = "2", features = [] }
thiserror = "2"
tokio = { version = "1", features = ["macros", "process", "rt-multi-thread", "time", "io-util"] }
uuid = { version = "1", features = ["v4", "serde"] }
walkdir = "2"

[dev-dependencies]
tempfile = "3"
```

Create `src-tauri/tauri.conf.json`:

```json
{
  "$schema": "https://schema.tauri.app/config/2",
  "productName": "DetDoc",
  "version": "0.1.0",
  "identifier": "dev.detdoc.gui",
  "build": {
    "beforeDevCommand": "npm run dev -- --watch=false",
    "beforeBuildCommand": "npm run build",
    "devUrl": "http://localhost:1420",
    "frontendDist": "../dist-ui"
  },
  "app": {
    "windows": [
      {
        "title": "DetDoc",
        "width": 1440,
        "height": 920,
        "minWidth": 1100,
        "minHeight": 720
      }
    ]
  },
  "bundle": {
    "active": true,
    "targets": ["app"]
  }
}
```

Create `src-tauri/build.rs`:

```rust
fn main() {
    tauri_build::build();
}
```

Create `src-tauri/src/main.rs`:

```rust
fn main() {
    detdoc_gui::run();
}
```

Create `src-tauri/src/lib.rs`:

```rust
pub mod commands;
pub mod detdoc;

pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![commands::ping])
        .run(tauri::generate_context!())
        .expect("failed to run DetDoc Tauri app");
}
```

Create `src-tauri/src/commands.rs`:

```rust
#[tauri::command]
pub async fn ping() -> Result<String, String> {
    Ok("pong".to_string())
}
```

Create `src-tauri/src/detdoc/mod.rs`:

```rust
pub mod error;
```

Create `src-tauri/src/detdoc/error.rs` with implementation plus the test from Step 1:

```rust
use std::fmt::{Display, Formatter};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DetDocError {
    code: String,
    message: String,
}

pub type DetDocResult<T> = Result<T, DetDocError>;

impl DetDocError {
    pub fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
        }
    }

    pub fn code(&self) -> &str {
        &self.code
    }

    pub fn message(&self) -> &str {
        &self.message
    }
}

impl Display for DetDocError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}: {}", self.code, self.message)
    }
}

impl std::error::Error for DetDocError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn error_display_includes_code_and_message() {
        let error = DetDocError::new("CONFIG_MISSING", "DetDoc config is missing");
        assert_eq!(error.code(), "CONFIG_MISSING");
        assert_eq!(error.to_string(), "CONFIG_MISSING: DetDoc config is missing");
    }
}
```

- [ ] **Step 6: Run scaffold tests**

Run:

```bash
npm install
npm run gui:test:rust
npm run gui:typecheck
```

Expected: Rust tests pass and TypeScript typecheck passes.

- [ ] **Step 7: Commit scaffold**

```bash
git add package.json package-lock.json vite.config.ts index.html src-ui src-tauri
git commit -m "feat: scaffold Tauri GUI app"
```

---

### Task 2: Port config loading, defaults, init files, and settings serialization

**Files:**
- Modify: `src-tauri/src/detdoc/mod.rs`
- Create: `src-tauri/src/detdoc/config.rs`
- Create: `src-tauri/tests/config_tests.rs`

**Interfaces:**
- Consumes: `DetDocError`, `DetDocResult<T>` from Task 1.
- Produces: `DetDocConfig`, `ValidationCommand`, `AgentConfig`, `WorktreeConfig`, `default_config()`, `default_config_yaml()`, `config_path(root)`, `load_config(root)`, `write_default_config(root)`, `init_detdoc_files(root)`.
- Later tasks consume `DetDocConfig` for path policy, validation, and flow.

- [ ] **Step 1: Write failing config tests**

Create `src-tauri/tests/config_tests.rs`:

```rust
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
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
cd src-tauri
cargo test --test config_tests
```

Expected: FAIL because `detdoc::config` does not exist.

- [ ] **Step 3: Implement config module**

Update `src-tauri/src/detdoc/mod.rs`:

```rust
pub mod config;
pub mod error;
```

Create `src-tauri/src/detdoc/config.rs`:

```rust
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
```

- [ ] **Step 4: Run config tests**

Run:

```bash
cd src-tauri
cargo test --test config_tests
```

Expected: PASS.

- [ ] **Step 5: Commit config port**

```bash
git add src-tauri/src/detdoc/mod.rs src-tauri/src/detdoc/config.rs src-tauri/tests/config_tests.rs
git commit -m "feat: port DetDoc config to Rust"
```

---

### Task 3: Port path policy and proposed plan validation

**Files:**
- Modify: `src-tauri/src/detdoc/mod.rs`
- Create: `src-tauri/src/detdoc/paths.rs`
- Create: `src-tauri/src/detdoc/plan.rs`
- Create: `src-tauri/tests/plan_tests.rs`

**Interfaces:**
- Consumes: `DetDocConfig` from Task 2.
- Produces: `RunMode`, `PlanChange`, `ProposedPlan`, `validate_proposed_plan(value, config, mode)`, `approved_targets_from_plan(plan)`, `is_doc_path(path, config)`, `is_denied_path(path, config)`.
- Later tasks consume validated plans and approved target lists.

- [ ] **Step 1: Write failing plan/path tests**

Create `src-tauri/tests/plan_tests.rs`:

```rust
use detdoc_gui::detdoc::config::default_config;
use detdoc_gui::detdoc::plan::{approved_targets_from_plan, validate_proposed_plan, PlanChange, ProposedPlan, RunMode};

fn valid_plan(reason: &str, target: &str) -> ProposedPlan {
    ProposedPlan {
        summary: "Change app behavior".to_string(),
        changes: vec![PlanChange {
            reason: reason.to_string(),
            target_files: vec![target.to_string()],
            kind: "modify".to_string(),
            rationale: "The docs require this code change.".to_string(),
        }],
        questions: vec![],
        risk: "low".to_string(),
    }
}

#[test]
fn run_plan_requires_doc_diff_reason() {
    let config = default_config();
    let error = validate_proposed_plan(valid_plan("intent:fix", "src/app.ts"), &config, RunMode::Run).unwrap_err();
    assert_eq!(error.code(), "PLAN_REASON_INVALID");
}

#[test]
fn fix_plan_requires_intent_reason() {
    let config = default_config();
    let error = validate_proposed_plan(valid_plan("doc-diff:docs/spec.md:L1-L2", "src/app.ts"), &config, RunMode::Fix).unwrap_err();
    assert_eq!(error.code(), "PLAN_REASON_INVALID");
}

#[test]
fn plans_cannot_target_docs_or_denied_paths() {
    let config = default_config();
    assert_eq!(validate_proposed_plan(valid_plan("doc-diff:docs/spec.md:L1-L2", "docs/spec.md"), &config, RunMode::Run).unwrap_err().code(), "PLAN_TARGETS_DOC");
    assert_eq!(validate_proposed_plan(valid_plan("doc-diff:docs/spec.md:L1-L2", ".env"), &config, RunMode::Run).unwrap_err().code(), "PLAN_TARGET_DENIED");
}

#[test]
fn approved_targets_are_unique_and_sorted() {
    let plan = ProposedPlan {
        summary: "Change app".to_string(),
        changes: vec![
            PlanChange { reason: "doc-diff:docs/spec.md:L1-L2".to_string(), target_files: vec!["src/b.ts".to_string(), "src/a.ts".to_string()], kind: "modify".to_string(), rationale: "A".to_string() },
            PlanChange { reason: "doc-diff:docs/spec.md:L3-L4".to_string(), target_files: vec!["src/a.ts".to_string()], kind: "modify".to_string(), rationale: "B".to_string() },
        ],
        questions: vec![],
        risk: "low".to_string(),
    };
    assert_eq!(approved_targets_from_plan(&plan), vec!["src/a.ts", "src/b.ts"]);
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
cd src-tauri
cargo test --test plan_tests
```

Expected: FAIL because modules do not exist.

- [ ] **Step 3: Implement paths and plan modules**

Update `src-tauri/src/detdoc/mod.rs`:

```rust
pub mod config;
pub mod error;
pub mod paths;
pub mod plan;
```

Create `src-tauri/src/detdoc/paths.rs`:

```rust
use globset::{Glob, GlobSetBuilder};

use super::config::DetDocConfig;

pub fn is_denied_path(path: &str, config: &DetDocConfig) -> bool {
    matches_any(path, &config.paths.deny)
}

pub fn is_doc_path(path: &str, config: &DetDocConfig) -> bool {
    matches_any(path, &config.docs.include) && !matches_any(path, &config.docs.exclude)
}

fn matches_any(path: &str, patterns: &[String]) -> bool {
    let mut builder = GlobSetBuilder::new();
    for pattern in patterns {
        if let Ok(glob) = Glob::new(pattern) {
            builder.add(glob);
        }
    }
    builder.build().map(|set| set.is_match(path)).unwrap_or(false)
}
```

Create `src-tauri/src/detdoc/plan.rs`:

```rust
use std::collections::BTreeSet;

use serde::{Deserialize, Serialize};

use super::config::DetDocConfig;
use super::error::{DetDocError, DetDocResult};
use super::paths::{is_denied_path, is_doc_path};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RunMode {
    Run,
    Fix,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlanChange {
    pub reason: String,
    #[serde(rename = "targetFiles")]
    pub target_files: Vec<String>,
    pub kind: String,
    pub rationale: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProposedPlan {
    pub summary: String,
    pub changes: Vec<PlanChange>,
    #[serde(default)]
    pub questions: Vec<String>,
    pub risk: String,
}

pub fn validate_proposed_plan(plan: ProposedPlan, config: &DetDocConfig, mode: RunMode) -> DetDocResult<ProposedPlan> {
    if plan.summary.trim().is_empty() || plan.changes.is_empty() {
        return Err(DetDocError::new("PLAN_EMPTY", "Plan summary and changes are required"));
    }
    if !matches!(plan.risk.as_str(), "low" | "medium" | "high") {
        return Err(DetDocError::new("PLAN_RISK_INVALID", format!("Invalid risk: {}", plan.risk)));
    }
    for change in &plan.changes {
        if !matches!(change.kind.as_str(), "create" | "modify" | "delete" | "rename") {
            return Err(DetDocError::new("PLAN_KIND_INVALID", format!("Invalid change kind: {}", change.kind)));
        }
        match mode {
            RunMode::Run if !change.reason.starts_with("doc-diff:") => {
                return Err(DetDocError::new("PLAN_REASON_INVALID", format!("run plan change must use doc-diff reason: {}", change.reason)));
            }
            RunMode::Fix if !change.reason.starts_with("intent:") => {
                return Err(DetDocError::new("PLAN_REASON_INVALID", format!("fix plan change must use intent reason: {}", change.reason)));
            }
            _ => {}
        }
        for target in &change.target_files {
            if is_denied_path(target, config) {
                return Err(DetDocError::new("PLAN_TARGET_DENIED", format!("plan targets denied path: {}", target)));
            }
            if is_doc_path(target, config) {
                return Err(DetDocError::new("PLAN_TARGETS_DOC", format!("plans must not target documentation files: {}", target)));
            }
        }
    }
    Ok(plan)
}

pub fn approved_targets_from_plan(plan: &ProposedPlan) -> Vec<String> {
    plan.changes
        .iter()
        .flat_map(|change| change.target_files.iter().cloned())
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect()
}
```

- [ ] **Step 4: Run plan tests**

Run:

```bash
cd src-tauri
cargo test --test plan_tests
```

Expected: PASS.

- [ ] **Step 5: Commit plan/path policy**

```bash
git add src-tauri/src/detdoc/mod.rs src-tauri/src/detdoc/paths.rs src-tauri/src/detdoc/plan.rs src-tauri/tests/plan_tests.rs
git commit -m "feat: port plan validation to Rust"
```

---

### Task 4: Port git repository wrapper and worktree lifecycle

**Files:**
- Modify: `src-tauri/src/detdoc/mod.rs`
- Create: `src-tauri/src/detdoc/git.rs`
- Create: `src-tauri/src/detdoc/worktree.rs`
- Create: `src-tauri/tests/fixtures.rs`
- Create: `src-tauri/tests/git_worktree_tests.rs`

**Interfaces:**
- Consumes: `DetDocError`, `DetDocResult<T>`.
- Produces: `GitRepository`, `GitStatusEntry`, `WorktreeManager`, `WorktreeHandle`.
- Later tasks consume git/worktree functions for docs diff, flow, and apply.

- [ ] **Step 1: Write failing git/worktree tests**

Create `src-tauri/tests/fixtures.rs`:

```rust
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
```

Create `src-tauri/tests/git_worktree_tests.rs`:

```rust
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
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
cd src-tauri
cargo test --test git_worktree_tests
```

Expected: FAIL because `git` and `worktree` modules do not exist.

- [ ] **Step 3: Implement git wrapper**

Update `src-tauri/src/detdoc/mod.rs`:

```rust
pub mod config;
pub mod error;
pub mod git;
pub mod paths;
pub mod plan;
pub mod worktree;
```

Create `src-tauri/src/detdoc/git.rs`:

```rust
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
        let output = self.git(&["status", "--porcelain"])?;
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
```

- [ ] **Step 4: Implement worktree manager**

Create `src-tauri/src/detdoc/worktree.rs`:

```rust
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
```

- [ ] **Step 5: Run git/worktree tests**

Run:

```bash
cd src-tauri
cargo test --test git_worktree_tests
```

Expected: PASS.

- [ ] **Step 6: Commit git/worktree port**

```bash
git add src-tauri/src/detdoc/mod.rs src-tauri/src/detdoc/git.rs src-tauri/src/detdoc/worktree.rs src-tauri/tests/fixtures.rs src-tauri/tests/git_worktree_tests.rs
git commit -m "feat: port git worktree lifecycle to Rust"
```

---

### Task 5: Port artifacts, manifest, docs diff, patch validation, and fake-agent flow

**Files:**
- Modify: `src-tauri/src/detdoc/mod.rs`
- Create: `src-tauri/src/detdoc/manifest.rs`
- Create: `src-tauri/src/detdoc/artifacts.rs`
- Create: `src-tauri/src/detdoc/docs.rs`
- Create: `src-tauri/src/detdoc/validation.rs`
- Create: `src-tauri/src/detdoc/agent.rs`
- Create: `src-tauri/src/detdoc/flow.rs`
- Create: `src-tauri/src/detdoc/events.rs`
- Create: `src-tauri/tests/flow_fake_agent_tests.rs`

**Interfaces:**
- Consumes: config, git, paths, plan, worktree modules.
- Produces: `ArtifactStore`, `RunManifest`, `AgentRunner`, `FakeAgentRunner`, `run_doc_flow`, `run_fix_flow`, `apply_saved_run`, `RunEvent`.
- Later Tauri commands consume flow functions.

- [ ] **Step 1: Write failing fake-agent flow tests**

Create `src-tauri/tests/flow_fake_agent_tests.rs`:

```rust
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
    fixtures::git(repo_dir.path(), &["add", "src/app.ts"]);
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
    std::fs::write(run_dir.join("changes.patch"), fixtures::git(repo_dir.path(), &["diff", "--no-index", "--", "src/app.ts", "src/app.ts"]).unwrap_or_default()).ok();

    std::fs::write(repo_dir.path().join("src/app.ts"), "export const value = 2;\n").unwrap();
    let patch = fixtures::git(repo_dir.path(), &["diff", "--", "src/app.ts"]);
    fixtures::git(repo_dir.path(), &["checkout", "--", "src/app.ts"]);
    std::fs::write(run_dir.join("changes.patch"), patch).unwrap();

    let result = apply_saved_run(repo_dir.path(), run_id, false).unwrap();
    assert!(result.applied);
    let status = fixtures::git(repo_dir.path(), &["status", "--porcelain"]);
    assert!(status.contains("M  src/app.ts"));
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
cd src-tauri
cargo test --test flow_fake_agent_tests
```

Expected: FAIL because modules and flow functions do not exist.

- [ ] **Step 3: Implement minimal flow modules with fake agent**

Implement these modules with the following public signatures. Keep internal code focused and pass tests before adding pi RPC.

Update `src-tauri/src/detdoc/mod.rs`:

```rust
pub mod agent;
pub mod artifacts;
pub mod config;
pub mod docs;
pub mod error;
pub mod events;
pub mod flow;
pub mod git;
pub mod manifest;
pub mod paths;
pub mod plan;
pub mod validation;
pub mod worktree;
```

Create `src-tauri/src/detdoc/manifest.rs`:

```rust
use serde::{Deserialize, Serialize};

use super::plan::RunMode;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunManifest {
    #[serde(rename = "runId")]
    pub run_id: String,
    pub mode: RunMode,
    #[serde(rename = "baseCommit")]
    pub base_commit: String,
    #[serde(default, rename = "approvedTargets")]
    pub approved_targets: Vec<String>,
}

pub fn create_run_id(mode: RunMode) -> String {
    let prefix = match mode { RunMode::Run => "run", RunMode::Fix => "fix" };
    format!("{}-{}-{}", chrono::Utc::now().format("%Y%m%dT%H%M%SZ"), prefix, uuid::Uuid::new_v4().simple().to_string()[0..8].to_string())
}
```

Create `src-tauri/src/detdoc/artifacts.rs`:

```rust
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
```

Create `src-tauri/src/detdoc/agent.rs`:

```rust
use std::fs;
use std::path::Path;

use super::config::DetDocConfig;
use super::error::DetDocResult;
use super::plan::{PlanChange, ProposedPlan, RunMode};

pub trait AgentRunner {
    fn plan(&self, mode: RunMode, input: &str, config: &DetDocConfig, cwd: &Path) -> DetDocResult<ProposedPlan>;
    fn implement(&self, approved_targets: &[String], cwd: &Path) -> DetDocResult<()>;
}

pub struct FakeAgentRunner {
    target: String,
    content: String,
}

impl FakeAgentRunner {
    pub fn new(target: &str, content: &str) -> Self {
        Self { target: target.to_string(), content: content.to_string() }
    }
}

impl AgentRunner for FakeAgentRunner {
    fn plan(&self, mode: RunMode, _input: &str, _config: &DetDocConfig, _cwd: &Path) -> DetDocResult<ProposedPlan> {
        let reason = match mode { RunMode::Run => "doc-diff:docs/technical-spec.md:L1-L2", RunMode::Fix => "intent:fix" };
        Ok(ProposedPlan {
            summary: "Fake plan".to_string(),
            changes: vec![PlanChange { reason: reason.to_string(), target_files: vec![self.target.clone()], kind: "modify".to_string(), rationale: "Fake agent writes target".to_string() }],
            questions: vec![],
            risk: "low".to_string(),
        })
    }

    fn implement(&self, _approved_targets: &[String], cwd: &Path) -> DetDocResult<()> {
        let path = cwd.join(&self.target);
        if let Some(parent) = path.parent() { fs::create_dir_all(parent).unwrap(); }
        fs::write(path, &self.content).unwrap();
        Ok(())
    }
}
```

Create `src-tauri/src/detdoc/docs.rs`, `validation.rs`, `events.rs`, and `flow.rs` with minimal implementation:

```rust
// docs.rs
use super::config::DetDocConfig;
use super::error::{DetDocError, DetDocResult};
use super::git::GitRepository;
use super::paths::is_doc_path;

pub fn get_normalized_doc_diff(repo: &GitRepository, config: &DetDocConfig) -> DetDocResult<String> {
    let status = repo.status_porcelain()?;
    let non_doc: Vec<String> = status.iter().filter(|entry| !is_doc_path(&entry.path, config)).map(|entry| entry.path.clone()).collect();
    if !non_doc.is_empty() {
        return Err(DetDocError::new("DIRTY_NON_DOC_CHANGES", non_doc.join(", ")));
    }
    let doc_paths: Vec<String> = status.iter().map(|entry| entry.path.clone()).collect();
    if doc_paths.is_empty() {
        return Err(DetDocError::new("NO_DOC_CHANGES", "No documentation changes found"));
    }
    let mut args = vec!["diff", "--no-color", "--no-ext-diff", "--binary", "--"];
    for path in &doc_paths { args.push(path); }
    repo.git(&args)
}
```

```rust
// validation.rs
use super::config::DetDocConfig;
use super::error::{DetDocError, DetDocResult};
use super::paths::{is_denied_path, is_doc_path};

pub fn validate_patch_paths(patch: &str, approved_targets: &[String], config: &DetDocConfig) -> DetDocResult<()> {
    for line in patch.lines().filter(|line| line.starts_with("+++ b/") || line.starts_with("--- a/")) {
        let path = line[6..].to_string();
        if path == "/dev/null" { continue; }
        if is_denied_path(&path, config) { return Err(DetDocError::new("PATCH_DENIED_PATH", path)); }
        if is_doc_path(&path, config) { return Err(DetDocError::new("PATCH_DOC_PATH", path)); }
        if !approved_targets.contains(&path) { return Err(DetDocError::new("PATCH_UNAPPROVED_PATH", path)); }
    }
    Ok(())
}
```

```rust
// events.rs
use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
pub struct RunFlowResult {
    #[serde(rename = "runId")]
    pub run_id: String,
    pub applied: bool,
    pub patch: String,
}
```

```rust
// flow.rs
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
    let mut args = vec!["diff", "--no-color", "--no-ext-diff", "--binary", "--"];
    for target in &manifest.approved_targets { args.push(target); }
    let patch = worktree_repo.git(&args)?;
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
    repo.apply_patch(&patch)?;
    if auto_commit {
        repo.git(&["add", "-A", "--", "."])?;
        repo.git(&["commit", "-m", &format!("DetDoc apply {}", run_id)])?;
        store.delete_run(run_id)?;
    } else {
        let mut args = vec!["add", "--"];
        for target in &manifest.approved_targets { args.push(target); }
        repo.git(&args)?;
    }
    Ok(RunFlowResult { run_id: run_id.to_string(), applied: true, patch })
}
```

- [ ] **Step 4: Run fake-agent flow tests**

Run:

```bash
cd src-tauri
cargo test --test flow_fake_agent_tests
```

Expected: PASS. If this fails, the implementer must correct the exact compiler error before continuing and rerun the same command until it passes.

- [ ] **Step 5: Commit fake-agent deterministic flow**

```bash
git add src-tauri/src/detdoc src-tauri/tests/flow_fake_agent_tests.rs
git commit -m "feat: add Rust fake-agent run and apply flow"
```

---

### Task 6: Add Tauri commands for project status, docs IO, init, runs, and fake run/apply

**Files:**
- Modify: `src-tauri/src/lib.rs`
- Modify: `src-tauri/src/commands.rs`
- Create: `src-ui/app/types.ts`
- Create: `src-ui/lib/tauri.ts`

**Interfaces:**
- Consumes: Rust flow/config/artifacts modules.
- Produces Tauri commands: `project_status`, `detdoc_init`, `docs_list`, `docs_read`, `docs_write`, `runs_list`, `run_start_fake`, `apply_saved_run_command`, `pi_health_check`.
- Later React components consume `src-ui/lib/tauri.ts` functions.

- [ ] **Step 1: Write frontend API wrapper first**

Create `src-ui/app/types.ts`:

```ts
export interface ProjectStatus {
  root: string;
  initialized: boolean;
  piAvailable: boolean;
  dirtyFiles: Array<{ status: string; path: string }>;
}

export interface DocFile {
  path: string;
  title: string;
}

export interface RunSummary {
  runId: string;
  hasPatch: boolean;
  approvedTargets: string[];
}

export interface RunFlowResult {
  runId: string;
  applied: boolean;
  patch: string;
}
```

Create `src-ui/lib/tauri.ts`:

```ts
import { invoke } from "@tauri-apps/api/core";
import type { DocFile, ProjectStatus, RunFlowResult, RunSummary } from "../app/types";

export const api = {
  projectStatus(root: string) {
    return invoke<ProjectStatus>("project_status", { root });
  },
  detdocInit(root: string) {
    return invoke<void>("detdoc_init", { root });
  },
  docsList(root: string) {
    return invoke<DocFile[]>("docs_list", { root });
  },
  docsRead(root: string, path: string) {
    return invoke<string>("docs_read", { root, path });
  },
  docsWrite(root: string, path: string, markdown: string) {
    return invoke<void>("docs_write", { root, path, markdown });
  },
  runsList(root: string) {
    return invoke<RunSummary[]>("runs_list", { root });
  },
  runStartFake(root: string, target: string, content: string) {
    return invoke<RunFlowResult>("run_start_fake", { root, target, content });
  },
  applySavedRun(root: string, runId: string, autoCommit: boolean) {
    return invoke<RunFlowResult>("apply_saved_run_command", { root, runId, autoCommit });
  },
  piHealthCheck() {
    return invoke<boolean>("pi_health_check");
  },
};
```

- [ ] **Step 2: Implement Tauri command structs and command functions**

Replace `src-tauri/src/commands.rs` with:

```rust
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
```

Update `src-tauri/src/lib.rs` invoke handler:

```rust
pub mod commands;
pub mod detdoc;

pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            commands::ping,
            commands::project_status,
            commands::detdoc_init,
            commands::docs_list,
            commands::docs_read,
            commands::docs_write,
            commands::runs_list,
            commands::run_start_fake,
            commands::apply_saved_run_command,
            commands::pi_health_check,
        ])
        .run(tauri::generate_context!())
        .expect("failed to run DetDoc Tauri app");
}
```

- [ ] **Step 3: Run Rust and UI typecheck**

Run:

```bash
npm run gui:test:rust
npm run gui:typecheck
```

Expected: PASS.

- [ ] **Step 4: Commit Tauri command layer**

```bash
git add src-tauri/src/lib.rs src-tauri/src/commands.rs src-ui/app/types.ts src-ui/lib/tauri.ts
git commit -m "feat: expose Rust DetDoc commands to GUI"
```

---

### Task 7: Build IDE-style React shell with docs explorer, Tiptap dual editor, panel, and runs view

**Files:**
- Modify: `src-ui/app/App.tsx`
- Create: `src-ui/components/ProjectShell.tsx`
- Create: `src-ui/components/DocsExplorer.tsx`
- Create: `src-ui/components/DocEditor.tsx`
- Create: `src-ui/components/DetDocPanel.tsx`
- Create: `src-ui/components/PlanReview.tsx`
- Create: `src-ui/components/PatchReview.tsx`
- Create: `src-ui/components/RunsView.tsx`
- Create: `src-ui/components/SettingsView.tsx`
- Modify: `src-ui/styles.css`

**Interfaces:**
- Consumes: `api` from `src-ui/lib/tauri.ts` and types from `src-ui/app/types.ts`.
- Produces: visible MVP GUI shell that can initialize, list docs, edit Markdown, create fake run, list/apply saved runs.

- [ ] **Step 1: Create component files with explicit props**

Create `src-ui/components/DocsExplorer.tsx`:

```tsx
import type { DocFile } from "../app/types";

export function DocsExplorer({ docs, selectedPath, onSelect }: { docs: DocFile[]; selectedPath: string | null; onSelect: (path: string) => void }) {
  return (
    <aside className="min-h-0 border-r border-white/10 bg-slate-950/80">
      <div className="border-b border-white/10 px-3 py-2 text-xs font-semibold uppercase tracking-wide text-slate-400">Docs</div>
      <div className="space-y-1 p-2">
        {docs.map((doc) => (
          <button
            key={doc.path}
            className={`w-full rounded-md px-2 py-1.5 text-left text-sm ${selectedPath === doc.path ? "bg-cyan-500/15 text-cyan-200" : "text-slate-300 hover:bg-white/5"}`}
            onClick={() => onSelect(doc.path)}
            type="button"
          >
            {doc.path}
          </button>
        ))}
      </div>
    </aside>
  );
}
```

Create `src-ui/components/DocEditor.tsx`:

```tsx
import { EditorContent, useEditor } from "@tiptap/react";
import StarterKit from "@tiptap/starter-kit";
import Placeholder from "@tiptap/extension-placeholder";
import { useEffect, useState } from "react";

export function DocEditor({ path, markdown, onSave }: { path: string | null; markdown: string; onSave: (markdown: string) => Promise<void> }) {
  const [sourceMode, setSourceMode] = useState(true);
  const [source, setSource] = useState(markdown);
  const editor = useEditor({
    extensions: [StarterKit, Placeholder.configure({ placeholder: "Write DetDoc documentation…" })],
    content: markdown,
    immediatelyRender: false,
  });

  useEffect(() => {
    setSource(markdown);
    editor?.commands.setContent(markdown);
  }, [markdown, editor]);

  if (!path) {
    return <section className="flex items-center justify-center text-sm text-slate-500">Select a Markdown document.</section>;
  }

  return (
    <section className="flex min-h-0 flex-col bg-slate-950">
      <div className="flex items-center justify-between border-b border-white/10 px-4 py-2">
        <div className="font-mono text-sm text-slate-200">{path}</div>
        <div className="flex gap-2">
          <button className="rounded-md border border-white/10 px-2 py-1 text-xs" onClick={() => setSourceMode(!sourceMode)} type="button">
            {sourceMode ? "Rich" : "Markdown source"}
          </button>
          <button className="rounded-md bg-cyan-500 px-2 py-1 text-xs font-semibold text-slate-950" onClick={() => onSave(sourceMode ? source : editor?.getText() ?? source)} type="button">Save</button>
        </div>
      </div>
      {sourceMode ? (
        <textarea className="min-h-0 flex-1 resize-none bg-slate-950 p-4 font-mono text-sm leading-6 text-slate-100 outline-none" value={source} onChange={(event) => setSource(event.target.value)} />
      ) : (
        <div className="prose prose-invert max-w-none min-h-0 flex-1 overflow-auto p-4"><EditorContent editor={editor} /></div>
      )}
    </section>
  );
}
```

Create `src-ui/components/DetDocPanel.tsx`:

```tsx
import type { RunFlowResult } from "../app/types";

export function DetDocPanel({ onFakeRun, latestRun }: { onFakeRun: () => Promise<void>; latestRun: RunFlowResult | null }) {
  return (
    <aside className="min-h-0 border-l border-white/10 bg-slate-950/80">
      <div className="border-b border-white/10 px-3 py-2 text-xs font-semibold uppercase tracking-wide text-slate-400">DetDoc</div>
      <div className="space-y-3 p-3">
        <button className="w-full rounded-md bg-cyan-500 px-3 py-2 text-sm font-semibold text-slate-950" onClick={onFakeRun} type="button">Run docs (fake agent)</button>
        <div className="rounded-lg border border-white/10 p-3 text-xs text-slate-300">
          <div className="font-semibold text-slate-100">Progress</div>
          <div className="mt-2">Structured progress and expandable raw logs will stream here.</div>
        </div>
        {latestRun ? <pre className="max-h-64 overflow-auto rounded-lg bg-black/40 p-3 text-[11px] text-slate-300">{latestRun.patch}</pre> : null}
      </div>
    </aside>
  );
}
```

Create review/settings components with stable exported names for later expansion:

```tsx
// PlanReview.tsx
export function PlanReview() { return <div className="text-sm text-slate-400">Plan review</div>; }
```

```tsx
// PatchReview.tsx
export function PatchReview() { return <div className="text-sm text-slate-400">Patch review</div>; }
```

```tsx
// SettingsView.tsx
export function SettingsView() { return <div className="text-sm text-slate-400">Settings</div>; }
```

Create `src-ui/components/RunsView.tsx`:

```tsx
import type { RunSummary } from "../app/types";

export function RunsView({ runs, onApply }: { runs: RunSummary[]; onApply: (runId: string) => Promise<void> }) {
  return (
    <section className="border-t border-white/10 bg-slate-950 p-3">
      <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-400">Saved Runs</div>
      <div className="flex gap-2 overflow-auto">
        {runs.map((run) => (
          <div key={run.runId} className="min-w-72 rounded-lg border border-white/10 p-3 text-xs text-slate-300">
            <div className="font-mono text-slate-100">{run.runId}</div>
            <div className="mt-1">Targets: {run.approvedTargets.length}</div>
            <button className="mt-2 rounded-md border border-cyan-400/40 px-2 py-1 text-cyan-200" onClick={() => onApply(run.runId)} type="button">Apply staged</button>
          </div>
        ))}
      </div>
    </section>
  );
}
```

- [ ] **Step 2: Build ProjectShell and wire API**

Create `src-ui/components/ProjectShell.tsx`:

```tsx
import { useEffect, useState } from "react";
import type { DocFile, ProjectStatus, RunFlowResult, RunSummary } from "../app/types";
import { api } from "../lib/tauri";
import { DocsExplorer } from "./DocsExplorer";
import { DocEditor } from "./DocEditor";
import { DetDocPanel } from "./DetDocPanel";
import { RunsView } from "./RunsView";

const defaultRoot = new URLSearchParams(window.location.search).get("root") ?? ".";

export function ProjectShell() {
  const [root, setRoot] = useState(defaultRoot);
  const [status, setStatus] = useState<ProjectStatus | null>(null);
  const [docs, setDocs] = useState<DocFile[]>([]);
  const [runs, setRuns] = useState<RunSummary[]>([]);
  const [selectedPath, setSelectedPath] = useState<string | null>(null);
  const [markdown, setMarkdown] = useState("");
  const [latestRun, setLatestRun] = useState<RunFlowResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function refresh() {
    setError(null);
    const nextStatus = await api.projectStatus(root);
    setStatus(nextStatus);
    if (nextStatus.initialized) {
      setDocs(await api.docsList(root));
      setRuns(await api.runsList(root));
    }
  }

  useEffect(() => { refresh().catch((error) => setError(String(error))); }, [root]);

  async function openDoc(path: string) {
    setSelectedPath(path);
    setMarkdown(await api.docsRead(root, path));
  }

  async function saveDoc(nextMarkdown: string) {
    if (!selectedPath) return;
    await api.docsWrite(root, selectedPath, nextMarkdown);
    setMarkdown(nextMarkdown);
    await refresh();
  }

  async function init() {
    await api.detdocInit(root);
    await refresh();
  }

  async function fakeRun() {
    const result = await api.runStartFake(root, "src/app.ts", "export const value = 2;\n");
    setLatestRun(result);
    await refresh();
  }

  async function applyRun(runId: string) {
    const result = await api.applySavedRun(root, runId, false);
    setLatestRun(result);
    await refresh();
  }

  return (
    <main className="grid h-screen grid-rows-[auto_1fr_auto] bg-slate-950 text-slate-100">
      <header className="flex items-center justify-between border-b border-white/10 px-4 py-2">
        <div className="font-semibold">DetDoc</div>
        <input className="w-[520px] rounded-md border border-white/10 bg-black/30 px-2 py-1 font-mono text-xs" value={root} onChange={(event) => setRoot(event.target.value)} />
        <div className="text-xs text-slate-400">pi: {status?.piAvailable ? "available" : "missing"}</div>
      </header>
      {status?.initialized ? (
        <div className="grid min-h-0 grid-cols-[280px_1fr_360px]">
          <DocsExplorer docs={docs} selectedPath={selectedPath} onSelect={openDoc} />
          <DocEditor path={selectedPath} markdown={markdown} onSave={saveDoc} />
          <DetDocPanel onFakeRun={fakeRun} latestRun={latestRun} />
        </div>
      ) : (
        <div className="flex items-center justify-center">
          <button className="rounded-lg bg-cyan-500 px-4 py-2 font-semibold text-slate-950" onClick={init} type="button">Initialize DetDoc</button>
        </div>
      )}
      <RunsView runs={runs} onApply={applyRun} />
      {error ? <div className="fixed bottom-3 right-3 rounded-lg border border-red-500/40 bg-red-950 p-3 text-sm text-red-100">{error}</div> : null}
    </main>
  );
}
```

Modify `src-ui/app/App.tsx`:

```tsx
import { ProjectShell } from "../components/ProjectShell";

export function App() {
  return <ProjectShell />;
}
```

- [ ] **Step 3: Run frontend build/typecheck**

Run:

```bash
npm run gui:typecheck
npm run gui:test:rust
```

Expected: PASS.

- [ ] **Step 4: Commit React shell**

```bash
git add src-ui
git commit -m "feat: add DetDoc GUI workspace shell"
```

---

### Task 8: Add pi health and initial JSONL RPC client boundary

**Files:**
- Modify: `src-tauri/src/detdoc/mod.rs`
- Create: `src-tauri/src/detdoc/pi_rpc.rs`
- Modify: `src-tauri/src/commands.rs`
- Create: `src-tauri/tests/pi_rpc_tests.rs`

**Interfaces:**
- Consumes: `AgentRunner` trait from Task 5.
- Produces: `PiRpcClient`, `PiRpcAgentRunner`, `check_pi_available()`, strict LF JSONL reader helper.
- Later tasks replace fake run command with real `run_start_from_docs` and `run_start_fix`.

- [ ] **Step 1: Write strict JSONL parser tests**

Create `src-tauri/tests/pi_rpc_tests.rs`:

```rust
use detdoc_gui::detdoc::pi_rpc::split_jsonl_records;

#[test]
fn jsonl_split_uses_lf_only_and_preserves_unicode_separators_inside_json() {
    let input = b"{\"text\":\"a\xE2\x80\xA8b\"}\n{\"ok\":true}\r\n";
    let records = split_jsonl_records(input).unwrap();
    assert_eq!(records, vec!["{\"text\":\"a\u{2028}b\"}", "{\"ok\":true}"]);
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
cd src-tauri
cargo test --test pi_rpc_tests
```

Expected: FAIL because `pi_rpc` does not exist.

- [ ] **Step 3: Implement pi RPC boundary**

Update `src-tauri/src/detdoc/mod.rs`:

```rust
pub mod agent;
pub mod artifacts;
pub mod config;
pub mod docs;
pub mod error;
pub mod events;
pub mod flow;
pub mod git;
pub mod manifest;
pub mod paths;
pub mod pi_rpc;
pub mod plan;
pub mod validation;
pub mod worktree;
```

Create `src-tauri/src/detdoc/pi_rpc.rs`:

```rust
use std::process::Command;

use super::error::{DetDocError, DetDocResult};

pub fn check_pi_available() -> bool {
    Command::new("pi").arg("--version").output().map(|output| output.status.success()).unwrap_or(false)
}

pub fn split_jsonl_records(bytes: &[u8]) -> DetDocResult<Vec<String>> {
    let text = String::from_utf8(bytes.to_vec()).map_err(|error| DetDocError::new("PI_RPC_UTF8_INVALID", error.to_string()))?;
    Ok(text
        .split('\n')
        .filter_map(|record| {
            let trimmed = record.strip_suffix('\r').unwrap_or(record);
            if trimmed.is_empty() { None } else { Some(trimmed.to_string()) }
        })
        .collect())
}

pub struct PiRpcClient;

impl PiRpcClient {
    pub fn new() -> Self { Self }
}

pub struct PiRpcAgentRunner;

impl PiRpcAgentRunner {
    pub fn new() -> Self { Self }
}
```

Modify `pi_health_check` in `src-tauri/src/commands.rs`:

```rust
#[tauri::command]
pub async fn pi_health_check() -> Result<bool, String> {
    Ok(crate::detdoc::pi_rpc::check_pi_available())
}
```

- [ ] **Step 4: Run pi RPC tests**

Run:

```bash
cd src-tauri
cargo test --test pi_rpc_tests
```

Expected: PASS.

- [ ] **Step 5: Commit pi RPC boundary**

```bash
git add src-tauri/src/detdoc/mod.rs src-tauri/src/detdoc/pi_rpc.rs src-tauri/src/commands.rs src-tauri/tests/pi_rpc_tests.rs
git commit -m "feat: add pi RPC integration boundary"
```

---

### Task 9: Final verification and documentation update for MVP status

**Files:**
- Modify: `README.md`
- Create: `docs/superpowers/plans/2026-06-20-detdoc-gui-rust-rewrite-status.md` if needed for handoff notes

**Interfaces:**
- Consumes all previous tasks.
- Produces verified branch with scaffolded GUI, Rust deterministic foundation, fake-agent run/apply path, and pi health boundary.

- [ ] **Step 1: Update README GUI development section**

Add this section to `README.md` under Development:

```md
## GUI rewrite development

The DetDoc GUI rewrite lives beside the current TypeScript CLI while Rust/Tauri reaches parity.

Useful commands:

```bash
npm run gui:test:rust
npm run gui:typecheck
npm run gui:dev
```

The MVP GUI is macOS-first and expects `pi` to be installed in `PATH`. The current TypeScript CLI remains as a temporary parity reference during the rewrite.
```

- [ ] **Step 2: Run full verification**

Run:

```bash
npm test
npm run typecheck
npm run build
npm run gui:test:rust
npm run gui:typecheck
```

Expected:

- existing TypeScript tests pass;
- TypeScript typecheck passes;
- existing CLI build passes;
- Rust GUI tests pass;
- frontend typecheck passes.

- [ ] **Step 3: Check git status**

Run:

```bash
git status --short
```

Expected: only README/status docs modified before final commit.

- [ ] **Step 4: Commit verification docs**

```bash
git add README.md docs/superpowers/plans/2026-06-20-detdoc-gui-rust-rewrite.md
git commit -m "docs: document GUI rewrite development workflow"
```

- [ ] **Step 5: Report final branch state**

Run:

```bash
git log --oneline --max-count=10
git status --short
```

Expected: branch contains the design commit, plan commit, and task commits; status is clean.

---

## Self-Review Notes

Spec coverage:

- Tauri + React + Rust GUI-only product direction: Tasks 1, 6, 7.
- Existing TS CLI retained as reference: Global Constraints and no deletion tasks.
- Existing config/artifact compatibility: Tasks 2, 5.
- Documentation editor and IDE layout: Task 7.
- `init`: Tasks 2 and 6.
- `run`/`apply` deterministic flow with fake agent: Task 5.
- Saved runs list/apply: Tasks 5, 6, 7.
- pi required in PATH and RPC boundary: Task 8.
- macOS-first: Global Constraints and Tauri config.
- Safety model: Tasks 3, 4, 5.

Known follow-up after this plan:

- Replace fake run command with real `PiRpcAgentRunner` planning/implementation protocol.
- Add real approval pause/resume events for plan and apply.
- Add validation command execution and repair attempts.
- Improve Tiptap Markdown serialization beyond the initial source-mode-safe editor.
- Add polished shadcn/ui components and diff viewer package.
