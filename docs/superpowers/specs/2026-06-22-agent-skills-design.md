# Agent Skills Repository Design

Date: 2026-06-22
Owner: mstroshin
Repository: `mstroshin/agent-skills`
Visibility: public

## Goal

Create a public hybrid Agent Skills repository for iOS and macOS development with Swift. The repository will provide original skills for gaps that are not well-covered by existing public skills, and will curate high-quality external skills for SwiftUI, Swift Concurrency, Swift Testing, Factory DI, and Apple documentation lookup.

The first version should be useful in any Swift Apple-platform project through the open Agent Skills format and `npx skills`.

## Non-Goals

- Do not vendor external skills in v1.
- Do not create a full replacement for existing SwiftUI, Swift Concurrency, Swift Testing, or Factory skills.
- Do not optimize primarily for a Pi-specific `.agents/skills` workflow. The main target is open Agent Skills and `npx skills`.
- Do not make the skills project-specific to DetDoc.

## Repository Structure

```text
agent-skills/
  README.md
  skills/
    apple-platform-router/
      SKILL.md
    oslog-debugging/
      SKILL.md
    swiftui-accessibility-identifiers/
      SKILL.md
    mvvm-c-architecture/
      SKILL.md
  references/
    recommended-external-skills.md
    install-recipes.md
```

## Own Skills in v1

### `apple-platform-router`

A meta-skill that helps the agent choose the correct Apple/Swift skill for a task. It does not replace topic-specific skills.

Routing behavior:

- SwiftUI/UI work -> use a SwiftUI skill, and add `swiftui-accessibility-identifiers` when identifiers are relevant.
- Swift concurrency diagnostics, actors, `Sendable`, `@MainActor`, data races -> use Swift Concurrency skill.
- Tests, Swift Testing, XCTest migration, flaky tests -> use Swift Testing skill.
- Factory, FactoryKit, DI containers, `@Injected`, `Container.shared` -> use Factory upstream skill.
- Runtime debugging, diagnostics, app logs, signposts -> use `oslog-debugging`.
- Architecture, navigation, coordinators, MVVM+C -> use `mvvm-c-architecture`.
- Apple API ambiguity, HIG, WWDC/API references -> use Apple documentation lookup via Sosumi.

### `oslog-debugging`

Guides agents when adding and reading Apple unified logging for Swift apps.

Scope:

- Use `OSLog.Logger` with clear subsystem and category names.
- Add diagnostic logs and signposts at meaningful boundaries.
- Use privacy annotations for sensitive values.
- Read logs with commands such as `log stream` and `log show` using app-scoped predicates by subsystem, category, or process.
- Avoid logging secrets, PII, tokens, or unnecessary high-volume data.
- Do not use logs as a substitute for tests.

### `swiftui-accessibility-identifiers`

Guides agents to add stable `.accessibilityIdentifier(...)` values for agent debugging, UI tests, screenshot automation, and app inspection.

Scope:

- Add identifiers to screens, actionable controls, inspectable containers, important rows/cells, empty/error/loading states, sheets, popovers, and navigation roots.
- Prefer stable naming such as `screen.section.element` and add state suffixes only when state is part of the inspected target.
- Do not confuse `.accessibilityIdentifier` with `.accessibilityLabel`.
- Do not degrade real accessibility semantics while adding debugging identifiers.

### `mvvm-c-architecture`

Guides agents when creating, reviewing, or refactoring SwiftUI app architecture using MVVM+C.

Scope:

- SwiftUI views stay thin and declarative.
- View models are `@MainActor @Observable` where appropriate and own state plus user intents.
- Coordinators own navigation, routing, sheets, windows, and deep-link decisions.
- Services and repositories are injected behind protocols or clear boundaries, preferably compatible with Factory DI.
- Tests target view models and coordinators headlessly where possible.
- Do not over-architect features that are too small to benefit from MVVM+C.

## Recommended External Skills

These are recommended rather than vendored in v1.

| Area | Skill | Reason |
| --- | --- | --- |
| SwiftUI | `avdlee/swiftui-agent-skill@swiftui-expert-skill` | High-install, high-star SwiftUI guidance for state, performance, modern APIs, and Apple-platform UI. |
| SwiftUI optional | `twostraws/swiftui-agent-skill@swiftui-pro` | Strong alternative/additional SwiftUI guidance. |
| SwiftUI performance optional | `dimillian/skills@swiftui-performance-audit` | Focused performance-audit workflow. |
| Swift Concurrency | `avdlee/swift-concurrency-agent-skill@swift-concurrency` | Strong Swift 6 concurrency and migration guidance. |
| Swift Testing | `avdlee/swift-testing-agent-skill@swift-testing-expert` | Modern Swift Testing guidance. |
| Factory DI | `hmlongco/Factory@factory-dependency-injection` | Official upstream Factory skill in the Factory repository. Install with `--full-depth`. |
| Apple docs | `sosumi` | Apple API docs, Human Interface Guidelines, and WWDC transcript lookup. |

## README Requirements

The repository README is the entry point. It must include:

1. What the repository is: a hybrid Apple/Swift agent skill pack.
2. Quick install commands for all own skills.
3. Recommended external install commands.
4. Guidance for when to install the router only versus all recommended skills.
5. A note that external skills are not vendored and are credited to their sources.
6. License and attribution information.

Own skill install commands:

```bash
npx skills add mstroshin/agent-skills --skill apple-platform-router
npx skills add mstroshin/agent-skills --skill oslog-debugging
npx skills add mstroshin/agent-skills --skill swiftui-accessibility-identifiers
npx skills add mstroshin/agent-skills --skill mvvm-c-architecture
```

Recommended external install commands:

```bash
npx skills add avdlee/swiftui-agent-skill --skill swiftui-expert-skill
npx skills add avdlee/swift-concurrency-agent-skill --skill swift-concurrency
npx skills add avdlee/swift-testing-agent-skill --skill swift-testing-expert
npx skills add hmlongco/Factory --skill factory-dependency-injection --full-depth
```

Optional external install commands:

```bash
npx skills add twostraws/swiftui-agent-skill --skill swiftui-pro
npx skills add dimillian/skills --skill swiftui-performance-audit
```

## Skill Authoring Requirements

Every own skill must:

- Use valid Agent Skills structure with `SKILL.md`.
- Include YAML frontmatter with `name` and `description`.
- Use only letters, numbers, and hyphens in `name`.
- Start `description` with `Use when...` and describe triggering conditions, not the workflow.
- Include a concise overview, when-to-use guidance, quick reference, and common mistakes.
- Be written in English.
- Avoid project-specific DetDoc assumptions.

## Validation

Before publishing v1:

- `npx skills add mstroshin/agent-skills --list` must find the four own skills after the repository is public.
- Each `SKILL.md` must have valid frontmatter.
- README must contain commands for own skills and external recommendations.
- External skills must remain linked/credited, not copied into the repository.
- The repository must be public on GitHub as `mstroshin/agent-skills`.

## Risks and Mitigations

- External skills may change or disappear. Mitigation: keep references in one file and update periodically.
- Own skills may become stale as Apple APIs evolve. Mitigation: router should direct API-specific questions to Apple documentation lookup.
- Skills may become too verbose. Mitigation: keep v1 focused on operational guidance and move heavy references to separate files only when necessary.
- Architecture guidance may be over-applied. Mitigation: `mvvm-c-architecture` must explicitly warn against over-architecting small features.
