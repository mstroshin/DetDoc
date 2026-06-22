# Agent Skills Repository Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and publish `mstroshin/agent-skills`, a public hybrid Agent Skills repository for Swift iOS/macOS development.

**Architecture:** The repository is an open Agent Skills package with four original skills under `skills/`, documentation under `references/`, and a README that curates external high-quality Swift/Apple skills without vendoring them. Validation is shell-based and checks file shape, frontmatter, descriptions, and required install commands.

**Tech Stack:** Markdown Agent Skills (`SKILL.md`), `npx skills`, Git, GitHub CLI (`gh`), shell validation.

## Global Constraints

- Repository owner is `mstroshin`.
- Repository name is `agent-skills`.
- Repository visibility is public.
- Main target is open Agent Skills and `npx skills`.
- Do not vendor external skills in v1.
- Do not create a full replacement for existing SwiftUI, Swift Concurrency, Swift Testing, or Factory skills.
- Do not optimize primarily for a Pi-specific `.agents/skills` workflow.
- Do not make the skills project-specific to DetDoc.
- Every own skill must use valid Agent Skills structure with `SKILL.md`.
- Every own skill must include YAML frontmatter with `name` and `description`.
- Every own skill name must use only letters, numbers, and hyphens.
- Every own skill description must start with `Use when...` and describe triggering conditions, not the workflow.
- Every own skill must include a concise overview, when-to-use guidance, quick reference, and common mistakes.
- Every own skill must be written in English.

---

## File Structure

Create a new repository outside the dirty DetDoc worktree:

```text
/Users/mxmtrshn/Workspace/agent-skills/
  README.md
  LICENSE
  scripts/
    validate.sh
  quality/
    skill-scenarios.md
  references/
    install-recipes.md
    recommended-external-skills.md
  skills/
    apple-platform-router/
      SKILL.md
    mvvm-c-architecture/
      SKILL.md
    oslog-debugging/
      SKILL.md
    swiftui-accessibility-identifiers/
      SKILL.md
```

Responsibilities:

- `README.md`: public entry point, quick install commands, external recommendations, license/attribution.
- `LICENSE`: MIT license for original repository content.
- `scripts/validate.sh`: local validation for repository shape and required text.
- `quality/skill-scenarios.md`: RED/GREEN pressure scenarios for the original skills.
- `references/install-recipes.md`: copy-paste installation recipes.
- `references/recommended-external-skills.md`: source, rationale, install commands, and caution notes for external skills.
- `skills/*/SKILL.md`: original operational guides.

---

### Task 1: Create Repository Skeleton and Local Validation

**Files:**
- Create: `/Users/mxmtrshn/Workspace/agent-skills/LICENSE`
- Create: `/Users/mxmtrshn/Workspace/agent-skills/scripts/validate.sh`
- Create: `/Users/mxmtrshn/Workspace/agent-skills/quality/skill-scenarios.md`
- Create directories for `references/` and `skills/`

**Interfaces:**
- Consumes: GitHub user `mstroshin` from the approved spec.
- Produces: A local git repository and `scripts/validate.sh` command used by all later tasks.

- [ ] **Step 1: Verify the target directory is safe to create**

Run:

```bash
cd /Users/mxmtrshn/Workspace
test ! -e agent-skills
```

Expected: command exits with status `0`. If it exits non-zero, stop and inspect `/Users/mxmtrshn/Workspace/agent-skills` before continuing.

- [ ] **Step 2: Create the repository skeleton**

Run:

```bash
cd /Users/mxmtrshn/Workspace
mkdir -p agent-skills/{scripts,quality,references,skills/apple-platform-router,skills/oslog-debugging,skills/swiftui-accessibility-identifiers,skills/mvvm-c-architecture}
cd agent-skills
git init
git branch -M main
```

Expected: `Initialized empty Git repository` and current directory is `/Users/mxmtrshn/Workspace/agent-skills`.

- [ ] **Step 3: Add the MIT license**

Create `/Users/mxmtrshn/Workspace/agent-skills/LICENSE` with this exact content:

```text
MIT License

Copyright (c) 2026 mstroshin

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 4: Add the validation script**

Create `/Users/mxmtrshn/Workspace/agent-skills/scripts/validate.sh` with this exact content:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

required_skills=(
  apple-platform-router
  oslog-debugging
  swiftui-accessibility-identifiers
  mvvm-c-architecture
)

for skill in "${required_skills[@]}"; do
  file="skills/$skill/SKILL.md"
  test -f "$file" || { echo "Missing $file" >&2; exit 1; }
  grep -q '^---$' "$file" || { echo "Missing YAML fence in $file" >&2; exit 1; }
  grep -q "^name: $skill$" "$file" || { echo "Missing exact name for $skill" >&2; exit 1; }
  grep -q '^description: Use when' "$file" || { echo "Description must start with Use when in $file" >&2; exit 1; }
  grep -q '^## Overview' "$file" || { echo "Missing Overview in $file" >&2; exit 1; }
  grep -q '^## When to Use' "$file" || { echo "Missing When to Use in $file" >&2; exit 1; }
  grep -q '^## Quick Reference' "$file" || { echo "Missing Quick Reference in $file" >&2; exit 1; }
  grep -q '^## Common Mistakes' "$file" || { echo "Missing Common Mistakes in $file" >&2; exit 1; }
done

for required in README.md LICENSE references/install-recipes.md references/recommended-external-skills.md quality/skill-scenarios.md; do
  test -f "$required" || { echo "Missing $required" >&2; exit 1; }
done

grep -q 'npx skills add mstroshin/agent-skills --skill apple-platform-router' README.md
grep -q 'npx skills add mstroshin/agent-skills --skill oslog-debugging' README.md
grep -q 'npx skills add mstroshin/agent-skills --skill swiftui-accessibility-identifiers' README.md
grep -q 'npx skills add mstroshin/agent-skills --skill mvvm-c-architecture' README.md
grep -q 'npx skills add hmlongco/Factory --skill factory-dependency-injection --full-depth' README.md

test ! -d .agents || { echo "Do not vendor local .agents skills" >&2; exit 1; }
test ! -d .claude || { echo "Do not vendor local .claude skills" >&2; exit 1; }

echo "Validation passed"
```

- [ ] **Step 5: Make the validation script executable**

Run:

```bash
cd /Users/mxmtrshn/Workspace/agent-skills
chmod +x scripts/validate.sh
```

Expected: no output.

- [ ] **Step 6: Add RED/GREEN skill scenario file**

Create `/Users/mxmtrshn/Workspace/agent-skills/quality/skill-scenarios.md` with this exact content:

```markdown
# Skill Scenarios

These scenarios are used to pressure-test the original skills. For each original skill, first run the RED prompt without the skill loaded and record likely failure patterns. Then run the GREEN prompt with the skill loaded and check the expected behavior.

## apple-platform-router

RED prompt: "I need help implementing a SwiftUI settings screen that uses Factory for dependencies, has async loading, needs tests, and should be debuggable. Which guidance should you load first?"

Expected baseline failure: agent gives generic SwiftUI advice, misses at least one of Factory, Swift Concurrency, Swift Testing, OSLog, or accessibility identifiers.

GREEN prompt: same as RED, but with `apple-platform-router` loaded.

Expected GREEN behavior: agent routes to SwiftUI, Factory, Swift Concurrency, Swift Testing, OSLog, accessibility identifiers, and Apple docs only when API details are unclear.

## oslog-debugging

RED prompt: "Add debug logs to a SwiftUI login flow and tell me how to read them from Terminal. The login result contains an auth token and user email."

Expected baseline failure: agent logs sensitive values, omits privacy annotations, uses `print`, or cannot provide useful `log stream` / `log show` predicates.

GREEN prompt: same as RED, but with `oslog-debugging` loaded.

Expected GREEN behavior: agent uses `Logger`, subsystem/category, privacy annotations, avoids token logging, and provides process/subsystem/category predicates for `log stream` and `log show`.

## swiftui-accessibility-identifiers

RED prompt: "Add identifiers to a SwiftUI onboarding flow so an agent can inspect loading, error, continue button, and selected plan state."

Expected baseline failure: agent adds only accessibility labels, creates unstable text-derived identifiers, misses state containers, or harms VoiceOver semantics.

GREEN prompt: same as RED, but with `swiftui-accessibility-identifiers` loaded.

Expected GREEN behavior: agent adds stable `.accessibilityIdentifier` values to screen roots, controls, inspectable state containers, rows, sheets, and avoids changing user-facing accessibility labels unless needed.

## mvvm-c-architecture

RED prompt: "Create architecture for a small SwiftUI macOS app with onboarding, workspace navigation, sheets, services, and testable state. Use MVVM+C but avoid overengineering."

Expected baseline failure: agent puts navigation in views, puts view construction in view models, uses global singletons for services, or over-abstracts a small feature.

GREEN prompt: same as RED, but with `mvvm-c-architecture` loaded.

Expected GREEN behavior: agent keeps views thin, uses `@MainActor @Observable` view models for state and intents, coordinators for navigation, injected services, and explicitly avoids MVVM+C for trivial features.
```

- [ ] **Step 7: Run validation and confirm it fails for missing docs/skills**

Run:

```bash
cd /Users/mxmtrshn/Workspace/agent-skills
./scripts/validate.sh
```

Expected: FAIL with `Missing skills/apple-platform-router/SKILL.md`. This is the RED check for repository shape.

- [ ] **Step 8: Commit the skeleton**

Run:

```bash
cd /Users/mxmtrshn/Workspace/agent-skills
git add LICENSE scripts/validate.sh quality/skill-scenarios.md
git commit -m "chore: initialize agent skills repository"
```

Expected: commit succeeds.

---

### Task 2: Add README and Reference Documentation

**Files:**
- Create: `/Users/mxmtrshn/Workspace/agent-skills/README.md`
- Create: `/Users/mxmtrshn/Workspace/agent-skills/references/install-recipes.md`
- Create: `/Users/mxmtrshn/Workspace/agent-skills/references/recommended-external-skills.md`

**Interfaces:**
- Consumes: Directory structure and `scripts/validate.sh` from Task 1.
- Produces: Public installation and attribution docs relied on by final validation.

- [ ] **Step 1: Create README**

Create `/Users/mxmtrshn/Workspace/agent-skills/README.md` with this exact content:

````markdown
# agent-skills

Hybrid Agent Skills for Swift iOS and macOS development.

This repository contains original skills for gaps that are not well covered by existing public skills, plus curated install commands for strong external Swift and Apple-platform skills.

## What is included

Original skills in this repository:

- `apple-platform-router` — choose the right Apple/Swift skill for broad iOS/macOS work.
- `oslog-debugging` — add and read Apple unified logs with `Logger`, privacy, predicates, and signposts.
- `swiftui-accessibility-identifiers` — add stable SwiftUI accessibility identifiers for agent debugging and UI automation.
- `mvvm-c-architecture` — structure SwiftUI apps with MVVM+C without overengineering.

Curated external skills are recommended, not vendored. See `references/recommended-external-skills.md`.

## Quick install

Install all original skills:

```bash
npx skills add mstroshin/agent-skills --skill apple-platform-router
npx skills add mstroshin/agent-skills --skill oslog-debugging
npx skills add mstroshin/agent-skills --skill swiftui-accessibility-identifiers
npx skills add mstroshin/agent-skills --skill mvvm-c-architecture
```

Install the recommended external Swift/Apple skills:

```bash
npx skills add avdlee/swiftui-agent-skill --skill swiftui-expert-skill
npx skills add avdlee/swift-concurrency-agent-skill --skill swift-concurrency
npx skills add avdlee/swift-testing-agent-skill --skill swift-testing-expert
npx skills add hmlongco/Factory --skill factory-dependency-injection --full-depth
```

Optional external skills:

```bash
npx skills add twostraws/swiftui-agent-skill --skill swiftui-pro
npx skills add dimillian/skills --skill swiftui-performance-audit
```

## Recommended setup

For general Apple-platform development, install:

1. `apple-platform-router` from this repository.
2. All recommended external SwiftUI, Swift Concurrency, Swift Testing, and Factory skills.
3. `oslog-debugging`, `swiftui-accessibility-identifiers`, and `mvvm-c-architecture` from this repository.
4. A documentation lookup skill such as Sosumi for Apple API reference, HIG, and WWDC transcripts.

Use the router when a task crosses multiple areas. Use a topic-specific skill directly when the task is obvious, such as fixing a `Sendable` warning or adding OSLog predicates.

## Why external skills are not vendored

The strongest SwiftUI, Swift Concurrency, Swift Testing, and Factory skills are maintained in their own upstream repositories. This repository links to those sources and provides installation commands instead of copying their content, so updates and attribution stay clear.

## Validate this repository

```bash
./scripts/validate.sh
```

After the repository is public, verify discovery through `npx skills`:

```bash
npx skills add mstroshin/agent-skills --list
```

The command should list:

- `apple-platform-router`
- `oslog-debugging`
- `swiftui-accessibility-identifiers`
- `mvvm-c-architecture`

## License

Original content in this repository is released under the MIT License. External skills keep their upstream licenses and are credited in `references/recommended-external-skills.md`.
````

- [ ] **Step 2: Create install recipes reference**

Create `/Users/mxmtrshn/Workspace/agent-skills/references/install-recipes.md` with this exact content:

````markdown
# Install Recipes

## Original skills from this repository

```bash
npx skills add mstroshin/agent-skills --skill apple-platform-router
npx skills add mstroshin/agent-skills --skill oslog-debugging
npx skills add mstroshin/agent-skills --skill swiftui-accessibility-identifiers
npx skills add mstroshin/agent-skills --skill mvvm-c-architecture
```

## Recommended external skills

```bash
npx skills add avdlee/swiftui-agent-skill --skill swiftui-expert-skill
npx skills add avdlee/swift-concurrency-agent-skill --skill swift-concurrency
npx skills add avdlee/swift-testing-agent-skill --skill swift-testing-expert
npx skills add hmlongco/Factory --skill factory-dependency-injection --full-depth
```

## Optional external skills

```bash
npx skills add twostraws/swiftui-agent-skill --skill swiftui-pro
npx skills add dimillian/skills --skill swiftui-performance-audit
```

## Factory note

The Factory skill lives under `.claude/skills/` in the upstream `hmlongco/Factory` repository. Use `--full-depth` so `npx skills` searches nested skill directories.
````

- [ ] **Step 3: Create recommended external skills reference**

Create `/Users/mxmtrshn/Workspace/agent-skills/references/recommended-external-skills.md` with this exact content:

````markdown
# Recommended External Skills

These skills are recommended for Swift iOS and macOS development. They are not vendored in this repository.

| Area | Install command | Why |
| --- | --- | --- |
| SwiftUI | `npx skills add avdlee/swiftui-agent-skill --skill swiftui-expert-skill` | Strong SwiftUI guidance for state management, view composition, performance, modern APIs, and Apple-platform UI. |
| Swift Concurrency | `npx skills add avdlee/swift-concurrency-agent-skill --skill swift-concurrency` | Swift 6 concurrency migration, actors, `@MainActor`, `Sendable`, data races, and strict-concurrency diagnostics. |
| Swift Testing | `npx skills add avdlee/swift-testing-agent-skill --skill swift-testing-expert` | Modern Swift Testing guidance, XCTest migration, traits, parameterization, async waiting, and flaky-test prevention. |
| Factory DI | `npx skills add hmlongco/Factory --skill factory-dependency-injection --full-depth` | Official upstream Factory skill for FactoryKit, FactoryTesting, property wrappers, scopes, and cross-module wiring. |
| Apple documentation | Install a Sosumi skill from the open skills ecosystem | Apple API reference, Human Interface Guidelines, WWDC transcript lookup, and Swift-DocC pages. |

## Optional additions

| Area | Install command | Why |
| --- | --- | --- |
| SwiftUI alternative | `npx skills add twostraws/swiftui-agent-skill --skill swiftui-pro` | Additional SwiftUI expertise from a highly trusted Swift educator. |
| SwiftUI performance | `npx skills add dimillian/skills --skill swiftui-performance-audit` | Focused SwiftUI performance review and audit workflow. |

## Attribution

All external skills belong to their upstream authors and keep their upstream licenses. This repository only documents install commands and selection guidance.
````

- [ ] **Step 4: Run validation and confirm it still fails for missing skills**

Run:

```bash
cd /Users/mxmtrshn/Workspace/agent-skills
./scripts/validate.sh
```

Expected: FAIL with `Missing skills/apple-platform-router/SKILL.md`.

- [ ] **Step 5: Commit docs**

Run:

```bash
cd /Users/mxmtrshn/Workspace/agent-skills
git add README.md references/install-recipes.md references/recommended-external-skills.md
git commit -m "docs: add install and external skill references"
```

Expected: commit succeeds.

---

### Task 3: Add `apple-platform-router` Skill

**Files:**
- Create: `/Users/mxmtrshn/Workspace/agent-skills/skills/apple-platform-router/SKILL.md`

**Interfaces:**
- Consumes: Recommended external skill names from `references/recommended-external-skills.md`.
- Produces: `apple-platform-router` skill discoverable by `npx skills`.

- [ ] **Step 1: Review the RED scenario**

Read `/Users/mxmtrshn/Workspace/agent-skills/quality/skill-scenarios.md`, section `apple-platform-router`.

Expected baseline failure to guard against: a generic answer that misses one of SwiftUI, Factory, Swift Concurrency, Swift Testing, OSLog, accessibility identifiers, or Apple docs.

- [ ] **Step 2: Create the skill**

Create `/Users/mxmtrshn/Workspace/agent-skills/skills/apple-platform-router/SKILL.md` with this exact content:

```markdown
---
name: apple-platform-router
description: Use when a Swift iOS or macOS task spans multiple Apple-development areas, such as SwiftUI, concurrency, testing, Factory DI, OSLog diagnostics, accessibility identifiers, MVVM+C architecture, or Apple API documentation.
---

# Apple Platform Router

## Overview

Use this skill first for broad Swift iOS/macOS work. It routes the agent to the most relevant topic-specific skill instead of trying to solve every Apple-platform problem from one generic checklist.

## When to Use

Use this skill when a task mentions two or more of these areas:

- SwiftUI views, state, layout, navigation, previews, or performance.
- Swift Concurrency, actors, `@MainActor`, `Sendable`, async/await, or data races.
- Swift Testing, XCTest migration, flaky tests, test plans, or async test waiting.
- Factory, FactoryKit, `Container.shared`, `Factory<T>`, `@Injected`, or dependency injection.
- OSLog, `Logger`, signposts, runtime diagnostics, or reading app logs.
- Accessibility identifiers for UI automation, screenshots, or agent debugging.
- MVVM+C, coordinators, routing, sheets, windows, or navigation architecture.
- Apple API details, availability, Human Interface Guidelines, or WWDC references.

Do not use it when the task is clearly in one area. Load the specific skill directly.

## Quick Reference

| Task signal | Load or recommend |
| --- | --- |
| SwiftUI, views, `@Observable`, lists, animations, previews | SwiftUI skill, plus `swiftui-accessibility-identifiers` when inspectability matters |
| Actors, `@MainActor`, `Sendable`, strict concurrency warnings | Swift Concurrency skill |
| `#expect`, Swift Testing, XCTest, flaky tests | Swift Testing skill |
| FactoryKit, `Container`, `Factory<T>`, `@Injected` | `factory-dependency-injection` from `hmlongco/Factory` |
| `Logger`, OSLog, signposts, `log stream`, `log show` | `oslog-debugging` |
| `.accessibilityIdentifier`, UI tests, agent inspection | `swiftui-accessibility-identifiers` |
| Coordinator, route, sheet, window, deep link, MVVM+C | `mvvm-c-architecture` |
| Apple API behavior, HIG, availability, WWDC | Apple documentation lookup such as Sosumi |

## Routing Pattern

1. Identify every domain in the user request.
2. Load the narrowest skill for each domain that materially affects the answer.
3. If API details are uncertain, consult Apple documentation instead of guessing.
4. Keep the final answer focused on the user's task; do not dump every checklist from every skill.

## Example

User asks: "Build a SwiftUI settings screen with async account loading, Factory DI, tests, and logs."

Route to:

- SwiftUI skill for view/state guidance.
- Swift Concurrency skill for async loading and actor boundaries.
- Factory upstream skill for dependency registration and injection.
- Swift Testing skill for test structure.
- `oslog-debugging` for diagnostics.
- `swiftui-accessibility-identifiers` for stable inspectability.

## Common Mistakes

| Mistake | Fix |
| --- | --- |
| Giving generic SwiftUI advice for a cross-domain task | Route each domain to its specific skill. |
| Treating the router as a replacement for topic skills | Use the router only to select skills. |
| Guessing Apple API behavior from memory | Use Apple documentation lookup for signatures, availability, and HIG details. |
| Loading every skill for every task | Load only skills that change the implementation or review. |
| Forgetting Factory lives in an upstream repository | Install with `npx skills add hmlongco/Factory --skill factory-dependency-injection --full-depth`. |
```

- [ ] **Step 3: Run validation and confirm next missing skill**

Run:

```bash
cd /Users/mxmtrshn/Workspace/agent-skills
./scripts/validate.sh
```

Expected: FAIL with `Missing skills/oslog-debugging/SKILL.md`.

- [ ] **Step 4: Commit the router skill**

Run:

```bash
cd /Users/mxmtrshn/Workspace/agent-skills
git add skills/apple-platform-router/SKILL.md
git commit -m "feat: add apple platform router skill"
```

Expected: commit succeeds.

---

### Task 4: Add `oslog-debugging` Skill

**Files:**
- Create: `/Users/mxmtrshn/Workspace/agent-skills/skills/oslog-debugging/SKILL.md`

**Interfaces:**
- Consumes: none from prior skills except repository validation script.
- Produces: `oslog-debugging` skill discoverable by `npx skills`.

- [ ] **Step 1: Review the RED scenario**

Read `/Users/mxmtrshn/Workspace/agent-skills/quality/skill-scenarios.md`, section `oslog-debugging`.

Expected baseline failure to guard against: using `print`, logging tokens/emails publicly, missing privacy annotations, or omitting useful `log stream` / `log show` predicates.

- [ ] **Step 2: Create the skill**

Create `/Users/mxmtrshn/Workspace/agent-skills/skills/oslog-debugging/SKILL.md` with this exact content:

````markdown
---
name: oslog-debugging
description: Use when adding, reviewing, or reading Apple unified logs in Swift iOS or macOS apps, including OSLog, Logger, signposts, privacy annotations, log stream predicates, log show history, runtime diagnostics, and agent-assisted debugging.
---

# OSLog Debugging

## Overview

Use Apple unified logging for runtime diagnostics that need to survive beyond a local debug session. Prefer `Logger` over `print`, use stable subsystem/category names, and protect sensitive values with privacy annotations.

## When to Use

Use this skill when the task asks to:

- Add diagnostic logging to Swift app code.
- Read app logs from Terminal or Console.
- Debug a runtime issue with timestamps, categories, or state transitions.
- Add signposts around performance-sensitive work.
- Replace `print` debugging with structured Apple logging.

Do not use logs as a substitute for tests, error handling, or user-visible diagnostics.

## Quick Reference

| Need | Pattern |
| --- | --- |
| Define a logger | `private let logger = Logger(subsystem: "com.example.app", category: "Login")` |
| Public value | `logger.info("Loaded count: \(count, privacy: .public)")` |
| Private value | `logger.info("User id: \(userID, privacy: .private)")` |
| Avoid secret logging | Log presence, hash prefix, or redacted state instead of tokens/secrets |
| Live logs | `log stream --style compact --predicate 'subsystem == "com.example.app"'` |
| Recent history | `log show --last 10m --style compact --predicate 'subsystem == "com.example.app"'` |
| Category filter | `subsystem == "com.example.app" AND category == "Login"` |
| Process filter | `process == "MyApp"` |

## Swift Pattern

```swift
import OSLog

private let logger = Logger(subsystem: "com.example.myapp", category: "Account")

func loadAccount(id: String) async throws -> Account {
    logger.info("Loading account id: \(id, privacy: .private)")
    do {
        let account = try await service.account(id: id)
        logger.info("Loaded account hasSubscription: \(account.hasSubscription, privacy: .public)")
        return account
    } catch {
        logger.error("Failed to load account: \(error.localizedDescription, privacy: .public)")
        throw error
    }
}
```

## Reading Logs

Use the narrowest predicate that still captures the problem.

```bash
log stream --style compact --predicate 'subsystem == "com.example.myapp"'
log stream --style compact --predicate 'subsystem == "com.example.myapp" AND category == "Account"'
log show --last 15m --style compact --predicate 'process == "MyApp" AND subsystem == "com.example.myapp"'
```

For noisy sessions, add level filters:

```bash
log show --last 15m --style compact --predicate 'subsystem == "com.example.myapp" AND message CONTAINS[c] "Failed"'
```

## Signposts

Use signposts for intervals you want to correlate with performance traces.

```swift
import OSLog

private let points = OSSignposter(subsystem: "com.example.myapp", category: "ImageImport")

func importImages() async throws {
    let state = points.beginInterval("ImportImages")
    defer { points.endInterval("ImportImages", state) }
    try await importer.run()
}
```

## Privacy Rules

- Never log tokens, passwords, private keys, full emails, payment data, or raw personal documents.
- Mark identifiers as `.private` unless they are intentionally public diagnostics.
- Prefer logging counts, booleans, enum states, and operation names.
- If a sensitive value is needed for correlation, log a safe derived value agreed by the team.

## Common Mistakes

| Mistake | Fix |
| --- | --- |
| Using `print` for app diagnostics | Use `Logger` with subsystem and category. |
| Logging auth tokens or full emails | Log redacted state or `.private` identifiers only. |
| One global category for everything | Use categories that match features or subsystems. |
| No instructions for reading logs | Provide `log stream` and `log show` predicates. |
| Adding logs everywhere | Log at boundaries: start, success, failure, retry, state transition. |
| Treating logs as tests | Add tests for behavior; use logs for runtime observation. |
````

- [ ] **Step 3: Run validation and confirm next missing skill**

Run:

```bash
cd /Users/mxmtrshn/Workspace/agent-skills
./scripts/validate.sh
```

Expected: FAIL with `Missing skills/swiftui-accessibility-identifiers/SKILL.md`.

- [ ] **Step 4: Commit the OSLog skill**

Run:

```bash
cd /Users/mxmtrshn/Workspace/agent-skills
git add skills/oslog-debugging/SKILL.md
git commit -m "feat: add oslog debugging skill"
```

Expected: commit succeeds.

---

### Task 5: Add `swiftui-accessibility-identifiers` Skill

**Files:**
- Create: `/Users/mxmtrshn/Workspace/agent-skills/skills/swiftui-accessibility-identifiers/SKILL.md`

**Interfaces:**
- Consumes: none from prior skills except repository validation script.
- Produces: `swiftui-accessibility-identifiers` skill discoverable by `npx skills`.

- [ ] **Step 1: Review the RED scenario**

Read `/Users/mxmtrshn/Workspace/agent-skills/quality/skill-scenarios.md`, section `swiftui-accessibility-identifiers`.

Expected baseline failure to guard against: using labels instead of identifiers, deriving unstable IDs from visible text, missing state containers, or degrading VoiceOver semantics.

- [ ] **Step 2: Create the skill**

Create `/Users/mxmtrshn/Workspace/agent-skills/skills/swiftui-accessibility-identifiers/SKILL.md` with this exact content:

````markdown
---
name: swiftui-accessibility-identifiers
description: Use when adding or reviewing SwiftUI accessibility identifiers for iOS or macOS views, UI tests, screenshot automation, agent debugging, inspectable loading/error/empty states, buttons, rows, sheets, popovers, and navigation roots.
---

# SwiftUI Accessibility Identifiers

## Overview

Add stable `.accessibilityIdentifier(...)` values so agents, UI tests, screenshots, and debugging tools can find important SwiftUI elements. Identifiers are for automation and inspection; labels, hints, traits, and values are for users.

## When to Use

Use this skill when a task asks to:

- Add accessibility IDs or identifiers.
- Make a SwiftUI screen easier for an agent to inspect or debug.
- Prepare UI for XCTest UI automation or screenshot tests.
- Identify loading, empty, error, selected, disabled, or expanded states.
- Review whether a SwiftUI view hierarchy is debuggable.

Do not use identifiers as a replacement for real accessibility labels or semantic grouping.

## Quick Reference

| Element | Identifier pattern |
| --- | --- |
| Screen root | `settings.screen` |
| Section/container | `settings.account.section` |
| Button | `settings.account.signOutButton` |
| Toggle | `settings.notifications.emailToggle` |
| Text field | `profile.name.textField` |
| Row | `documents.row.<stable-id>` |
| Loading state | `documents.loadingView` |
| Empty state | `documents.emptyView` |
| Error state | `documents.errorView` |
| Sheet | `settings.rename.sheet` |
| Popover | `editor.link.popover` |

## SwiftUI Pattern

```swift
struct SettingsScreen: View {
    var body: some View {
        Form {
            Section("Account") {
                Button("Sign Out") {
                    signOut()
                }
                .accessibilityIdentifier("settings.account.signOutButton")
            }
            .accessibilityIdentifier("settings.account.section")
        }
        .accessibilityIdentifier("settings.screen")
    }
}
```

For state-specific containers:

```swift
switch viewModel.state {
case .loading:
    ProgressView("Loading")
        .accessibilityIdentifier("documents.loadingView")
case .empty:
    ContentUnavailableView("No Documents", systemImage: "doc")
        .accessibilityIdentifier("documents.emptyView")
case .failed:
    ErrorView(retry: viewModel.retry)
        .accessibilityIdentifier("documents.errorView")
case .loaded(let documents):
    DocumentsList(documents: documents)
        .accessibilityIdentifier("documents.list")
}
```

## Naming Rules

- Use stable domain names, not visible copy that localization can change.
- Prefer `screen.section.element` for static controls.
- Use a stable model identifier for dynamic rows, such as `documents.row.<id>`.
- Use state suffixes only when the state is itself inspected, such as `loadingView` or `errorView`.
- Keep names readable and predictable; avoid UUIDs unless the model ID is already a UUID.

## Placement Rules

Add identifiers to:

- Screen roots and major navigation roots.
- Actionable controls: buttons, toggles, menus, pickers, text fields.
- Important containers: lists, forms, inspectors, sheets, popovers.
- Dynamic rows and selected/expanded state when tests or agents need to inspect them.
- Loading, empty, error, permission, and offline states.

Avoid identifiers on every decorative `Text`, `Image`, `Spacer`, or private subview unless it is inspected.

## Accessibility Semantics

`.accessibilityIdentifier` does not create a user-facing label. If a control lacks a good label, add an appropriate `.accessibilityLabel`, `.accessibilityHint`, or semantic container separately.

Do not change correct user-facing accessibility just to make automation easier.

## Common Mistakes

| Mistake | Fix |
| --- | --- |
| Adding `.accessibilityLabel` when automation needs an ID | Add `.accessibilityIdentifier` and keep user labels semantic. |
| IDs based on localized visible text | Use stable domain names. |
| Only tagging buttons | Also tag screen roots, lists, rows, sheets, and state views. |
| Tagging every tiny subview | Tag elements that tests or agents need to find. |
| Reusing the same ID in repeated rows | Include a stable row/model identifier. |
| Breaking VoiceOver grouping | Keep accessibility semantics separate from automation identifiers. |
````

- [ ] **Step 3: Run validation and confirm next missing skill**

Run:

```bash
cd /Users/mxmtrshn/Workspace/agent-skills
./scripts/validate.sh
```

Expected: FAIL with `Missing skills/mvvm-c-architecture/SKILL.md`.

- [ ] **Step 4: Commit the accessibility identifiers skill**

Run:

```bash
cd /Users/mxmtrshn/Workspace/agent-skills
git add skills/swiftui-accessibility-identifiers/SKILL.md
git commit -m "feat: add swiftui accessibility identifiers skill"
```

Expected: commit succeeds.

---

### Task 6: Add `mvvm-c-architecture` Skill

**Files:**
- Create: `/Users/mxmtrshn/Workspace/agent-skills/skills/mvvm-c-architecture/SKILL.md`

**Interfaces:**
- Consumes: none from prior skills except repository validation script.
- Produces: `mvvm-c-architecture` skill discoverable by `npx skills` and a passing local validation run.

- [ ] **Step 1: Review the RED scenario**

Read `/Users/mxmtrshn/Workspace/agent-skills/quality/skill-scenarios.md`, section `mvvm-c-architecture`.

Expected baseline failure to guard against: navigation in views, view construction in view models, global singleton services, or over-abstracting trivial features.

- [ ] **Step 2: Create the skill**

Create `/Users/mxmtrshn/Workspace/agent-skills/skills/mvvm-c-architecture/SKILL.md` with this exact content:

````markdown
---
name: mvvm-c-architecture
description: Use when designing, reviewing, or refactoring SwiftUI iOS or macOS app architecture with MVVM+C, including thin views, @Observable view models, coordinators, routing, sheets, windows, deep links, dependency boundaries, services, repositories, and headless tests.
---

# MVVM+C Architecture

## Overview

MVVM+C separates SwiftUI presentation, state/intent handling, and navigation decisions. Views render state and send intents, view models own feature state and business-facing actions, and coordinators own routing, sheets, windows, and deep links.

## When to Use

Use this skill when a task asks to:

- Design SwiftUI app architecture using MVVM+C.
- Refactor navigation out of views or view models.
- Add coordinators, routing, sheets, windows, or deep-link handling.
- Make SwiftUI state and navigation testable without launching the UI.
- Decide where services, repositories, and dependency injection belong.

Do not force MVVM+C onto a tiny one-screen feature with no navigation, no side effects, and no testability problem.

## Quick Reference

| Responsibility | Put it in |
| --- | --- |
| Layout and visual composition | SwiftUI `View` |
| User intent forwarding | SwiftUI `View` calls view-model or coordinator methods |
| Feature state | `@MainActor @Observable` view model |
| Async UI-facing actions | View model, with clear actor isolation |
| Navigation stack, sheets, windows, deep links | Coordinator |
| Business logic | Service or domain object |
| Persistence/networking | Repository or client |
| Dependency registration | DI container such as Factory |
| Unit tests | View models, coordinators, services, repositories |

## Component Boundaries

### View

A SwiftUI view should be easy to preview and mostly declarative.

```swift
struct DocumentsScreen: View {
    @Bindable var viewModel: DocumentsViewModel
    let coordinator: DocumentsCoordinating

    var body: some View {
        List(viewModel.documents) { document in
            Button(document.title) {
                coordinator.open(document)
            }
        }
        .task { await viewModel.load() }
        .accessibilityIdentifier("documents.screen")
    }
}
```

### View Model

Use `@MainActor @Observable` for UI-facing state unless there is a clear reason not to.

```swift
@MainActor
@Observable
final class DocumentsViewModel {
    private let repository: DocumentsRepository
    private(set) var documents: [Document] = []
    private(set) var isLoading = false
    var errorMessage: String?

    init(repository: DocumentsRepository) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            documents = try await repository.documents()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

### Coordinator

Coordinators make navigation decisions and expose route state that views can bind to.

```swift
@MainActor
@Observable
final class AppCoordinator {
    enum Route: Hashable {
        case onboarding
        case workspace
    }

    var path: [Route] = []
    var presentedSheet: Sheet?

    func showWorkspace() {
        path = [.workspace]
    }

    func presentSettings() {
        presentedSheet = .settings
    }
}
```

## Dependency Boundaries

- Inject services and repositories into view models and coordinators.
- Keep concrete networking, persistence, and file-system code out of SwiftUI views.
- Prefer protocols only at meaningful boundaries: tests, modules, external systems, or multiple implementations.
- If using Factory, keep registrations near composition roots and use the upstream Factory skill for exact FactoryKit guidance.

## Testing Strategy

- Test view models by injecting fake repositories and asserting state changes.
- Test coordinators by invoking routing methods and asserting route/sheet/window state.
- Keep SwiftUI snapshot or UI tests for integration-level confidence.
- Avoid requiring an app launch for business-state tests.

## Common Mistakes

| Mistake | Fix |
| --- | --- |
| Putting navigation decisions inside view body branches | Move routing decisions to a coordinator. |
| Building SwiftUI views inside view models | View models expose state; views compose views. |
| Making every type a protocol | Add protocols at boundaries that need substitution. |
| Using global singletons for services | Inject dependencies through initializers or a DI container. |
| Marking everything `@MainActor` without thought | UI-facing state is main-actor isolated; heavy work belongs in services off the main actor. |
| Applying MVVM+C to trivial UI | Use a simple view and extract architecture when complexity appears. |
````

- [ ] **Step 3: Run validation and confirm it passes**

Run:

```bash
cd /Users/mxmtrshn/Workspace/agent-skills
./scripts/validate.sh
```

Expected: PASS with `Validation passed`.

- [ ] **Step 4: Commit the MVVM+C skill**

Run:

```bash
cd /Users/mxmtrshn/Workspace/agent-skills
git add skills/mvvm-c-architecture/SKILL.md
git commit -m "feat: add mvvm-c architecture skill"
```

Expected: commit succeeds.

---

### Task 7: Validate Local Package Shape and Publish to GitHub

**Files:**
- Modify only if validation reveals a concrete typo in files from Tasks 1-6.

**Interfaces:**
- Consumes: complete repository from Tasks 1-6.
- Produces: public GitHub repository `mstroshin/agent-skills` and verified `npx skills` discovery.

- [ ] **Step 1: Run local validation**

Run:

```bash
cd /Users/mxmtrshn/Workspace/agent-skills
./scripts/validate.sh
```

Expected: PASS with `Validation passed`.

- [ ] **Step 2: Verify `npx skills` can list local skills**

Run:

```bash
cd /Users/mxmtrshn/Workspace/agent-skills
npx skills add . --list --full-depth
```

Expected: output includes all four names:

```text
apple-platform-router
oslog-debugging
swiftui-accessibility-identifiers
mvvm-c-architecture
```

If the local path form is not accepted by the installed `npx skills` version, skip only this local-path check and continue to the remote check after publishing.

- [ ] **Step 3: Confirm the working tree is clean before publishing**

Run:

```bash
cd /Users/mxmtrshn/Workspace/agent-skills
git status --short
```

Expected: no output.

- [ ] **Step 4: Create the public GitHub repository and push**

Run:

```bash
cd /Users/mxmtrshn/Workspace/agent-skills
gh repo create mstroshin/agent-skills --public --source=. --remote=origin --push
```

Expected: GitHub CLI creates the public repository and pushes `main`.

If the repository already exists, run this instead:

```bash
git remote add origin git@github.com:mstroshin/agent-skills.git
git push -u origin main
```

- [ ] **Step 5: Verify remote skill discovery**

Run:

```bash
npx skills add mstroshin/agent-skills --list
```

Expected: output includes all four names:

```text
apple-platform-router
oslog-debugging
swiftui-accessibility-identifiers
mvvm-c-architecture
```

- [ ] **Step 6: Verify external Factory skill discovery**

Run:

```bash
npx skills add hmlongco/Factory --skill factory-dependency-injection --full-depth --list
```

Expected: output includes `factory-dependency-injection`.

- [ ] **Step 7: Record final verification in the repository**

Run:

```bash
cd /Users/mxmtrshn/Workspace/agent-skills
printf 'Local validation: ./scripts/validate.sh -> Validation passed\nRemote discovery: npx skills add mstroshin/agent-skills --list -> found 4 skills\nFactory discovery: npx skills add hmlongco/Factory --skill factory-dependency-injection --full-depth --list -> found factory-dependency-injection\n' > quality/verification.txt
git add quality/verification.txt
git commit -m "docs: record v1 verification"
git push
```

Expected: commit and push succeed.

---

## Self-Review Notes

Spec coverage:

- Public repository: Task 7.
- Open Agent Skills format: Tasks 3-6.
- Four own skills: Tasks 3-6.
- External recommendations without vendoring: Task 2.
- Factory upstream skill with `--full-depth`: Tasks 2 and 7.
- README install commands: Task 2.
- Validation: Tasks 1, 6, and 7.
- English `SKILL.md` files: Tasks 3-6.
- No DetDoc-specific assumptions: all created content is generic Apple/Swift guidance.

Placeholder scan: no open-ended implementation placeholders are intended; all file contents and commands are specified.

Type/name consistency: skill directory names, frontmatter names, README commands, and validation script use the same four names.
