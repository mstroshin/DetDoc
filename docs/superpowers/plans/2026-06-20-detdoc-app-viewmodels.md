# DetDocApp View Models Implementation Plan (Plan 3a)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `DetDocViewModels` — the UI-agnostic MVVM+C logic of the DetDoc macOS app (coordinator/routing, per-screen `@Observable` view models, and the diff model) — as a SwiftPM library on top of `DetDocCore`, fully tested headless with Swift Testing. The SwiftUI views, XcodeGen project, and native folder picker are Plan 3b.

**Architecture:** A new `DetDocViewModels` library target (in the existing `swift/DetDocCore` package) depends on `DetDocCore` and imports `Observation` (not SwiftUI), so view models are testable with `swift test`. View models are `@MainActor @Observable` classes holding presentation state and calling `DetDocCore` services/engine. Navigation lives in an `AppCoordinator`. The native folder picker is abstracted behind a `FolderPicking` protocol so view models test without AppKit.

**Tech Stack:** Swift 6.4, SwiftPM, Observation, Swift Testing, `DetDocCore`.

## Global Constraints

- Platform floor **macOS 27**; **pure Swift**; tests use **Swift Testing**; only external dep stays **Yams** (via DetDocCore).
- `DetDocViewModels` imports **Observation** and **DetDocCore** only — NOT SwiftUI/AppKit (those are Plan 3b).
- All view models are `@MainActor @Observable final class`; navigation/coordinator state is `@MainActor @Observable`.
- The `DetDocViewModels` target carries `swiftSettings: [.treatAllWarnings(as: .error)]` — code must be warning-clean.
- View models depend on `DetDocCore` types (`DetDocEngine`, `RunEvent`, `ProposedPlan`, `PatchReview`, `RunFlowResult`, `ProjectStatus`, `DocFile`, `RunSummary`, `DetDocConfig`, `DetDocError`, services). Do not duplicate core logic; call into it.
- The app surface mirrors the design spec's full screen list: workspace (status/docs/runs), doc editor (source + preview), run/fix panel with plan & patch approval gates, runs list, settings, onboarding/init.

## Behavior anchors (from the design spec + DetDocCore)

- App routing: `noProject` → (folder chosen) → `onboarding` (if `.detdoc/config.yml` missing) → `workspace` (initialized).
- `ProjectStatus` = `{root, initialized, piAvailable, dirtyFiles}` (from `DetDocCore`: `ConfigStore` existence + `GitRepository.statusPorcelain` + `PiHealth`).
- Run/fix panel drives `DetDocEngine.start(mode:message:)`'s `AsyncThrowingStream<RunEvent>`; it pauses at `.planReady` (consumer calls `submitPlanDecision`) and `.patchReady` (`submitApplyDecision`).
- Saved runs come from `.detdoc/runs/*` (list via `ArtifactStore`/manifest); apply via `RunApplier`.
- Settings edits `.detdoc/config.yml` via `ConfigStore` (validation commands, agent, worktree.keepOnFailure, apply.autoCommit).
- Editor saves exact Markdown source via `DocsService` (no WYSIWYG; preview is render-only).

---

## File Structure

```txt
swift/DetDocCore/
  Package.swift                                   # MODIFIED: + DetDocViewModels library + test target
  Sources/DetDocViewModels/
    AppCoordinator.swift                          # AppRoute, FolderPicking, AppCoordinator
    WorkspaceViewModel.swift
    DocEditorViewModel.swift
    RunsViewModel.swift
    SettingsViewModel.swift
    OnboardingViewModel.swift
    DiffModel.swift                               # unified-diff parser for the patch viewer
    ReviewViewModels.swift                        # PlanReviewViewModel, PatchReviewViewModel
    RunPanelViewModel.swift                       # drives DetDocEngine + gates
  Tests/DetDocViewModelsTests/
    Support/AsyncPoll.swift                       # bounded async polling helper
    Support/VMGitFixture.swift                    # git repo + detdoc init helper for VM tests
    AppCoordinatorTests.swift
    WorkspaceViewModelTests.swift
    DocEditorViewModelTests.swift
    RunsViewModelTests.swift
    SettingsViewModelTests.swift
    OnboardingViewModelTests.swift
    DiffModelTests.swift
    ReviewViewModelsTests.swift
    RunPanelViewModelTests.swift
```

---

### Task 1: Scaffold the DetDocViewModels target

**Files:**
- Modify: `Package.swift`
- Create: `Sources/DetDocViewModels/DetDocViewModels.swift`
- Test: `Tests/DetDocViewModelsTests/PackageSmokeTests.swift`

**Interfaces:**
- Produces: a `DetDocViewModels` library product (depends on `DetDocCore`) with `enum DetDocViewModels { static let version: String }`, and a `DetDocViewModelsTests` Swift Testing target.

- [ ] **Step 1: Write the failing test**

`Tests/DetDocViewModelsTests/PackageSmokeTests.swift`
```swift
import Testing
@testable import DetDocViewModels

@Test func viewModelsModuleExposesVersion() {
    #expect(DetDocViewModels.version == "0.1.0")
}
```

- [ ] **Step 2: Run to verify it fails** — `cd swift/DetDocCore && swift test` → build error (no `DetDocViewModels` module).

- [ ] **Step 3: Implement**

Edit `Package.swift` — add to `products` and `targets` (keep the existing `DetDocCore` library/target/test and Yams dependency unchanged):
```swift
        .library(name: "DetDocViewModels", targets: ["DetDocViewModels"]),
```
```swift
        .target(
            name: "DetDocViewModels",
            dependencies: ["DetDocCore"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "DetDocViewModelsTests",
            dependencies: ["DetDocViewModels", "DetDocCore"]
        ),
```

`Sources/DetDocViewModels/DetDocViewModels.swift`
```swift
/// Namespace + version marker for the DetDocViewModels library.
public enum DetDocViewModels {
    public static let version = "0.1.0"
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test` → all green (existing DetDocCore tests + 1 new).
- [ ] **Step 5: Commit**
```bash
git add swift/DetDocCore/Package.swift swift/DetDocCore/Sources/DetDocViewModels swift/DetDocCore/Tests/DetDocViewModelsTests/PackageSmokeTests.swift
git commit -m "feat(viewmodels): scaffold DetDocViewModels SwiftPM target"
```

---

### Task 2: AppCoordinator + routing + FolderPicking + test helpers

**Files:**
- Create: `Sources/DetDocViewModels/AppCoordinator.swift`
- Create: `Tests/DetDocViewModelsTests/Support/AsyncPoll.swift`
- Create: `Tests/DetDocViewModelsTests/Support/VMGitFixture.swift`
- Test: `Tests/DetDocViewModelsTests/AppCoordinatorTests.swift`

**Interfaces:**
- Consumes: `DetDocCore` (`ConfigStore`).
- Produces:
  - `enum AppRoute: Equatable, Sendable { case noProject; case onboarding(root: URL); case workspace(root: URL) }`
  - `protocol FolderPicking: Sendable { func pickFolder() async -> URL? }`
  - `@MainActor @Observable final class AppCoordinator` with `var route: AppRoute`, `init(picker: any FolderPicking)`, `func chooseProject() async`, `func open(root: URL)`, `func initialized(root: URL)` (move onboarding→workspace).
  - `open(root:)` sets `.workspace` if `<root>/.detdoc/config.yml` exists, else `.onboarding`.
  - Test helpers: `func poll(timeout:_ predicate:) async` and `final class VMGitFixture` (git repo + optional `detdocInit()`).

- [ ] **Step 1: Write the failing test**

`Tests/DetDocViewModelsTests/Support/AsyncPoll.swift`
```swift
import Foundation

/// Polls `predicate` until true or the timeout elapses; fatalErrors on timeout so a hang fails fast.
func poll(timeout: Double = 5.0, _ predicate: @Sendable () async -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await predicate() { return }
        try? await Task.sleep(nanoseconds: 5_000_000)  // 5ms
    }
    fatalError("poll timed out")
}
```

`Tests/DetDocViewModelsTests/Support/VMGitFixture.swift`
```swift
import Foundation
@testable import DetDocCore

final class VMGitFixture {
    let root: URL
    let repo: GitRepository
    init() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("detdoc-vm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        repo = GitRepository(root)
        _ = try await repo.git(["init", "-q", "-b", "main"])
        _ = try await repo.git(["config", "user.email", "t@detdoc.local"])
        _ = try await repo.git(["config", "user.name", "DetDoc Test"])
        _ = try await repo.git(["config", "commit.gpgsign", "false"])
    }
    func write(_ path: String, _ contents: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
    func commitAll(_ message: String) async throws {
        _ = try await repo.git(["add", "-A", "--", "."])
        _ = try await repo.git(["commit", "-q", "-m", message])
    }
    func detdocInit() async throws {
        try ConfigStore().initFiles(root: root)
        try await commitAll("detdoc init")
    }
    deinit { try? FileManager.default.removeItem(at: root) }
}
```

`Tests/DetDocViewModelsTests/AppCoordinatorTests.swift`
```swift
import Foundation
import Testing
@testable import DetDocViewModels
@testable import DetDocCore

private struct StubPicker: FolderPicking {
    let url: URL?
    func pickFolder() async -> URL? { url }
}

@MainActor
@Test func openRoutesToOnboardingWhenNotInitialized() async throws {
    let fx = try await VMGitFixture()
    let coordinator = AppCoordinator(picker: StubPicker(url: fx.root))
    coordinator.open(root: fx.root)
    #expect(coordinator.route == .onboarding(root: fx.root))
}

@MainActor
@Test func openRoutesToWorkspaceWhenInitialized() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    let coordinator = AppCoordinator(picker: StubPicker(url: fx.root))
    coordinator.open(root: fx.root)
    #expect(coordinator.route == .workspace(root: fx.root))
}

@MainActor
@Test func chooseProjectUsesPickerThenRoutes() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    let coordinator = AppCoordinator(picker: StubPicker(url: fx.root))
    await coordinator.chooseProject()
    #expect(coordinator.route == .workspace(root: fx.root))
}

@MainActor
@Test func chooseProjectStaysNoProjectWhenCancelled() async {
    let coordinator = AppCoordinator(picker: StubPicker(url: nil))
    await coordinator.chooseProject()
    #expect(coordinator.route == .noProject)
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test` → build error (`AppCoordinator` not found).

- [ ] **Step 3: Implement**

`Sources/DetDocViewModels/AppCoordinator.swift`
```swift
import Foundation
import Observation
import DetDocCore

public enum AppRoute: Equatable, Sendable {
    case noProject
    case onboarding(root: URL)
    case workspace(root: URL)
}

public protocol FolderPicking: Sendable {
    func pickFolder() async -> URL?
}

@MainActor
@Observable
public final class AppCoordinator {
    public private(set) var route: AppRoute = .noProject
    private let picker: any FolderPicking

    public init(picker: any FolderPicking) {
        self.picker = picker
    }

    public func chooseProject() async {
        guard let url = await picker.pickFolder() else { return }
        open(root: url)
    }

    public func open(root: URL) {
        let configPath = ConfigStore().configPath(root: root)
        if FileManager.default.fileExists(atPath: configPath.path) {
            route = .workspace(root: root)
        } else {
            route = .onboarding(root: root)
        }
    }

    public func initialized(root: URL) {
        route = .workspace(root: root)
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test` → all green.
- [ ] **Step 5: Commit**
```bash
git add swift/DetDocCore/Sources/DetDocViewModels/AppCoordinator.swift swift/DetDocCore/Tests/DetDocViewModelsTests/Support swift/DetDocCore/Tests/DetDocViewModelsTests/AppCoordinatorTests.swift
git commit -m "feat(viewmodels): AppCoordinator routing + FolderPicking + test helpers"
```

---

### Task 3: WorkspaceViewModel

**Files:**
- Create: `Sources/DetDocViewModels/WorkspaceViewModel.swift`
- Test: `Tests/DetDocViewModelsTests/WorkspaceViewModelTests.swift`

**Interfaces:**
- Consumes: `DetDocCore` (`GitRepository`, `ConfigStore`, `DocsService`, `PiHealth`, `ArtifactStore`, `ProjectStatus`, `DirtyFile`, `DocFile`, `RunSummary`, `RunManifest`).
- Produces:
  - `@MainActor @Observable final class WorkspaceViewModel` with `init(root: URL)`, `var status: ProjectStatus?`, `var docs: [DocFile]`, `var runs: [RunSummary]`, `func refresh() async`.
  - `refresh()` loads `ProjectStatus` (initialized = config exists; piAvailable via `PiHealth`; dirtyFiles via `statusPorcelain`), then docs (`DocsService.list`) and runs (scan `.detdoc/runs/*` manifests) when initialized.

- [ ] **Step 1: Write the failing test**

`Tests/DetDocViewModelsTests/WorkspaceViewModelTests.swift`
```swift
import Foundation
import Testing
@testable import DetDocViewModels
@testable import DetDocCore

@MainActor
@Test func refreshLoadsStatusDocsAndRuns() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    try fx.write("docs/extra.md", "# Extra\n")

    // seed a saved run
    let store = ArtifactStore(projectRoot: fx.root)
    var manifest = RunManifest.initial(mode: .run, baseCommit: try await fx.repo.headCommit())
    manifest.approvedTargets = ["src/a.swift"]
    try store.createRun(manifest)
    try store.writeText(manifest.runId, "changes.patch", "patch\n")

    let vm = WorkspaceViewModel(root: fx.root)
    await vm.refresh()

    #expect(vm.status?.initialized == true)
    #expect(vm.docs.contains { $0.path == "docs/extra.md" })
    #expect(vm.runs.contains { $0.runId == manifest.runId && $0.hasPatch })
}

@MainActor
@Test func refreshReportsUninitializedWithoutConfig() async throws {
    let fx = try await VMGitFixture()
    let vm = WorkspaceViewModel(root: fx.root)
    await vm.refresh()
    #expect(vm.status?.initialized == false)
    #expect(vm.docs.isEmpty)
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test` → build error (`WorkspaceViewModel` not found).

- [ ] **Step 3: Implement**

`Sources/DetDocViewModels/WorkspaceViewModel.swift`
```swift
import Foundation
import Observation
import DetDocCore

@MainActor
@Observable
public final class WorkspaceViewModel {
    public private(set) var status: ProjectStatus?
    public private(set) var docs: [DocFile] = []
    public private(set) var runs: [RunSummary] = []

    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func refresh() async {
        let repo = GitRepository(root)
        let initialized = FileManager.default.fileExists(atPath: ConfigStore().configPath(root: root).path)
        let dirty = (try? await repo.statusPorcelain()) ?? []
        let piAvailable = await PiHealth.isAvailable()
        status = ProjectStatus(
            root: root.path,
            initialized: initialized,
            piAvailable: piAvailable,
            dirtyFiles: dirty.map { DirtyFile(status: $0.status, path: $0.path) }
        )
        guard initialized, let config = try? ConfigStore().load(root: root) else {
            docs = []
            runs = []
            return
        }
        docs = DocsService(root: root, config: config).list()
        runs = loadRuns()
    }

    private func loadRuns() -> [RunSummary] {
        let store = ArtifactStore(projectRoot: root)
        let runsDir = root.appendingPathComponent(".detdoc/runs")
        guard let entries = try? FileManager.default.contentsOfDirectory(at: runsDir, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        var summaries: [RunSummary] = []
        for entry in entries {
            let runId = entry.lastPathComponent
            guard let manifest: RunManifest = try? store.readJSON(RunManifest.self, runId, "manifest.json") else { continue }
            let hasPatch = FileManager.default.fileExists(atPath: entry.appendingPathComponent("changes.patch").path)
            summaries.append(RunSummary(runId: runId, hasPatch: hasPatch, approvedTargets: manifest.approvedTargets))
        }
        return summaries.sorted { $0.runId > $1.runId }
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test` → all green.
- [ ] **Step 5: Commit**
```bash
git add swift/DetDocCore/Sources/DetDocViewModels/WorkspaceViewModel.swift swift/DetDocCore/Tests/DetDocViewModelsTests/WorkspaceViewModelTests.swift
git commit -m "feat(viewmodels): WorkspaceViewModel (status, docs, runs)"
```

---

### Task 4: DocEditorViewModel

**Files:**
- Create: `Sources/DetDocViewModels/DocEditorViewModel.swift`
- Test: `Tests/DetDocViewModelsTests/DocEditorViewModelTests.swift`

**Interfaces:**
- Consumes: `DetDocCore` (`DocsService`, `DetDocConfig`).
- Produces:
  - `@MainActor @Observable final class DocEditorViewModel` with `init(root: URL, config: DetDocConfig)`, `var selectedPath: String?`, `var source: String`, `var isDirty: Bool`, `func open(_ path: String)`, `func edit(_ text: String)`, `func save()`, `func previewMarkdown() -> AttributedString`.
  - `open` loads source via `DocsService.read`, clears dirty; `edit` sets source + dirty; `save` writes via `DocsService.write` + clears dirty; `previewMarkdown` renders the current source with `AttributedString(markdown:)` (inline). Saving exact source — no WYSIWYG round-trip.

- [ ] **Step 1: Write the failing test**

`Tests/DetDocViewModelsTests/DocEditorViewModelTests.swift`
```swift
import Foundation
import Testing
@testable import DetDocViewModels
@testable import DetDocCore

@MainActor
@Test func openEditSaveRoundTrips() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    let vm = DocEditorViewModel(root: fx.root, config: .default)

    vm.open("docs/idea.md")
    #expect(vm.selectedPath == "docs/idea.md")
    #expect(vm.isDirty == false)

    vm.edit("# Edited\n")
    #expect(vm.isDirty == true)
    vm.save()
    #expect(vm.isDirty == false)

    let onDisk = try String(contentsOf: fx.root.appendingPathComponent("docs/idea.md"), encoding: .utf8)
    #expect(onDisk == "# Edited\n")
}

@MainActor
@Test func previewRendersMarkdown() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    let vm = DocEditorViewModel(root: fx.root, config: .default)
    vm.edit("Hello **bold**")
    let preview = vm.previewMarkdown()
    #expect(String(preview.characters).contains("Hello"))
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test` → build error (`DocEditorViewModel` not found).

- [ ] **Step 3: Implement**

`Sources/DetDocViewModels/DocEditorViewModel.swift`
```swift
import Foundation
import Observation
import DetDocCore

@MainActor
@Observable
public final class DocEditorViewModel {
    public private(set) var selectedPath: String?
    public private(set) var source: String = ""
    public private(set) var isDirty: Bool = false

    private let root: URL
    private let docs: DocsService

    public init(root: URL, config: DetDocConfig) {
        self.root = root
        self.docs = DocsService(root: root, config: config)
    }

    public func open(_ path: String) {
        selectedPath = path
        source = (try? docs.read(path)) ?? ""
        isDirty = false
    }

    public func edit(_ text: String) {
        source = text
        isDirty = true
    }

    public func save() {
        guard let path = selectedPath else { return }
        try? docs.write(path, source)
        isDirty = false
    }

    public func previewMarkdown() -> AttributedString {
        (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(source)
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test` → all green.
- [ ] **Step 5: Commit**
```bash
git add swift/DetDocCore/Sources/DetDocViewModels/DocEditorViewModel.swift swift/DetDocCore/Tests/DetDocViewModelsTests/DocEditorViewModelTests.swift
git commit -m "feat(viewmodels): DocEditorViewModel (source edit + save + preview)"
```

---

### Task 5: RunsViewModel

**Files:**
- Create: `Sources/DetDocViewModels/RunsViewModel.swift`
- Test: `Tests/DetDocViewModelsTests/RunsViewModelTests.swift`

**Interfaces:**
- Consumes: `DetDocCore` (`ArtifactStore`, `RunManifest`, `RunSummary`, `RunApplier`, `ConfigStore`, `DetDocError`).
- Produces:
  - `@MainActor @Observable final class RunsViewModel` with `init(root: URL)`, `var runs: [RunSummary]`, `var error: DetDocError?`, `func refresh()`, `func apply(_ runId: String) async`.
  - `apply` calls `RunApplier().apply(root:runId:autoCommit:)` using `config.apply.autoCommit`; on success refreshes; on `DetDocError` stores it in `error`.

- [ ] **Step 1: Write the failing test**

`Tests/DetDocViewModelsTests/RunsViewModelTests.swift`
```swift
import Foundation
import Testing
@testable import DetDocViewModels
@testable import DetDocCore

@MainActor
@Test func applyReportsBaseMismatchError() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    let store = ArtifactStore(projectRoot: fx.root)
    var manifest = RunManifest.initial(mode: .run, baseCommit: "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef")  // wrong base
    manifest.approvedTargets = ["src/a.swift"]
    try store.createRun(manifest)
    try store.writeText(manifest.runId, "changes.patch", "patch\n")

    let vm = RunsViewModel(root: fx.root)
    vm.refresh()
    #expect(vm.runs.contains { $0.runId == manifest.runId })
    await vm.apply(manifest.runId)
    #expect(vm.error?.code == "APPLY_BASE_MISMATCH")
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test` → build error (`RunsViewModel` not found).

- [ ] **Step 3: Implement**

`Sources/DetDocViewModels/RunsViewModel.swift`
```swift
import Foundation
import Observation
import DetDocCore

@MainActor
@Observable
public final class RunsViewModel {
    public private(set) var runs: [RunSummary] = []
    public private(set) var error: DetDocError?

    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func refresh() {
        let store = ArtifactStore(projectRoot: root)
        let runsDir = root.appendingPathComponent(".detdoc/runs")
        let entries = (try? FileManager.default.contentsOfDirectory(at: runsDir, includingPropertiesForKeys: nil)) ?? []
        var summaries: [RunSummary] = []
        for entry in entries {
            let runId = entry.lastPathComponent
            guard let manifest: RunManifest = try? store.readJSON(RunManifest.self, runId, "manifest.json") else { continue }
            let hasPatch = FileManager.default.fileExists(atPath: entry.appendingPathComponent("changes.patch").path)
            summaries.append(RunSummary(runId: runId, hasPatch: hasPatch, approvedTargets: manifest.approvedTargets))
        }
        runs = summaries.sorted { $0.runId > $1.runId }
    }

    public func apply(_ runId: String) async {
        error = nil
        do {
            let config = try ConfigStore().load(root: root)
            _ = try await RunApplier().apply(root: root, runId: runId, autoCommit: config.apply.autoCommit)
            refresh()
        } catch let e as DetDocError {
            error = e
        } catch {
            self.error = DetDocError("APPLY_FAILED", "\(error)")
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test` → all green.
- [ ] **Step 5: Commit**
```bash
git add swift/DetDocCore/Sources/DetDocViewModels/RunsViewModel.swift swift/DetDocCore/Tests/DetDocViewModelsTests/RunsViewModelTests.swift
git commit -m "feat(viewmodels): RunsViewModel (list + apply saved runs)"
```

---

### Task 6: SettingsViewModel

**Files:**
- Create: `Sources/DetDocViewModels/SettingsViewModel.swift`
- Test: `Tests/DetDocViewModelsTests/SettingsViewModelTests.swift`

**Interfaces:**
- Consumes: `DetDocCore` (`ConfigStore`, `DetDocConfig`, `ValidationCommand`, `PiHealth`, `DetDocError`).
- Produces:
  - `@MainActor @Observable final class SettingsViewModel` with `init(root: URL)`, `var config: DetDocConfig`, `var piAvailable: Bool`, `var error: DetDocError?`, `func load()`, `func save()`, `func refreshPiHealth() async`.
  - `load` reads config (or `.default` if missing); `save` writes via a new `ConfigStore.write(_:root:)` (added here); editing mutates `config` in place via the SwiftUI binding.
- Also: extend `DetDocCore.ConfigStore` with `func write(_ config: DetDocConfig, root: URL) throws` (YAML-encode + write) — **this is the only DetDocCore change in Plan 3a** (additive).

- [ ] **Step 1: Write the failing test**

`Tests/DetDocViewModelsTests/SettingsViewModelTests.swift`
```swift
import Foundation
import Testing
@testable import DetDocViewModels
@testable import DetDocCore

@MainActor
@Test func loadEditSavePersistsConfig() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    let vm = SettingsViewModel(root: fx.root)
    vm.load()
    #expect(vm.config.apply.autoCommit == true)

    vm.config.apply = ApplyConfig(autoCommit: false)
    vm.config.validation = ValidationConfig(commands: [ValidationCommand(name: "test", run: "swift test")])
    vm.save()
    #expect(vm.error == nil)

    let reloaded = try ConfigStore().load(root: fx.root)
    #expect(reloaded.apply.autoCommit == false)
    #expect(reloaded.validation.commands == [ValidationCommand(name: "test", run: "swift test")])
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test` → build error (`SettingsViewModel` / `ConfigStore.write` not found).

- [ ] **Step 3: Implement**

Add to `Sources/DetDocCore/Config/ConfigStore.swift` (new method on the existing struct):
```swift
    public func write(_ config: DetDocConfig, root: URL) throws {
        let yaml: String
        do {
            yaml = try Yams.YAMLEncoder().encode(config)
        } catch {
            throw DetDocError("CONFIG_SERIALIZE_FAILED", "\(error)")
        }
        let path = configPath(root: root)
        do {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try yaml.write(to: path, atomically: true, encoding: .utf8)
        } catch {
            throw DetDocError("CONFIG_WRITE_FAILED", "\(error)")
        }
    }
```
(Ensure `import Yams` is present at the top of ConfigStore.swift — it already is from Plan 1. Use `Yams.YAMLEncoder` to be explicit.)

`Sources/DetDocViewModels/SettingsViewModel.swift`
```swift
import Foundation
import Observation
import DetDocCore

@MainActor
@Observable
public final class SettingsViewModel {
    public var config: DetDocConfig = .default
    public private(set) var piAvailable: Bool = false
    public private(set) var error: DetDocError?

    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func load() {
        config = (try? ConfigStore().load(root: root)) ?? .default
    }

    public func save() {
        error = nil
        do {
            try ConfigStore().write(config, root: root)
        } catch let e as DetDocError {
            error = e
        } catch {
            self.error = DetDocError("CONFIG_WRITE_FAILED", "\(error)")
        }
    }

    public func refreshPiHealth() async {
        piAvailable = await PiHealth.isAvailable()
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test` → all green.
- [ ] **Step 5: Commit**
```bash
git add swift/DetDocCore/Sources/DetDocCore/Config/ConfigStore.swift swift/DetDocCore/Sources/DetDocViewModels/SettingsViewModel.swift swift/DetDocCore/Tests/DetDocViewModelsTests/SettingsViewModelTests.swift
git commit -m "feat(viewmodels): SettingsViewModel + ConfigStore.write"
```

---

### Task 7: OnboardingViewModel

**Files:**
- Create: `Sources/DetDocViewModels/OnboardingViewModel.swift`
- Test: `Tests/DetDocViewModelsTests/OnboardingViewModelTests.swift`

**Interfaces:**
- Consumes: `DetDocCore` (`ConfigStore`, `DetDocError`).
- Produces:
  - `@MainActor @Observable final class OnboardingViewModel` with `init(root: URL)`, `var error: DetDocError?`, `func initialize() -> Bool` (returns true on success). Calls `ConfigStore().initFiles(root:)`.

- [ ] **Step 1: Write the failing test**

`Tests/DetDocViewModelsTests/OnboardingViewModelTests.swift`
```swift
import Foundation
import Testing
@testable import DetDocViewModels
@testable import DetDocCore

@MainActor
@Test func initializeCreatesDetdocConfig() async throws {
    let fx = try await VMGitFixture()
    let vm = OnboardingViewModel(root: fx.root)
    let ok = vm.initialize()
    #expect(ok)
    #expect(vm.error == nil)
    #expect(FileManager.default.fileExists(atPath: ConfigStore().configPath(root: fx.root).path))
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test` → build error (`OnboardingViewModel` not found).

- [ ] **Step 3: Implement**

`Sources/DetDocViewModels/OnboardingViewModel.swift`
```swift
import Foundation
import Observation
import DetDocCore

@MainActor
@Observable
public final class OnboardingViewModel {
    public private(set) var error: DetDocError?
    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    @discardableResult
    public func initialize() -> Bool {
        error = nil
        do {
            try ConfigStore().initFiles(root: root)
            return true
        } catch let e as DetDocError {
            error = e
            return false
        } catch {
            self.error = DetDocError("INIT_FAILED", "\(error)")
            return false
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test` → all green.
- [ ] **Step 5: Commit**
```bash
git add swift/DetDocCore/Sources/DetDocViewModels/OnboardingViewModel.swift swift/DetDocCore/Tests/DetDocViewModelsTests/OnboardingViewModelTests.swift
git commit -m "feat(viewmodels): OnboardingViewModel (detdoc init)"
```

---

### Task 8: DiffModel

**Files:**
- Create: `Sources/DetDocViewModels/DiffModel.swift`
- Test: `Tests/DetDocViewModelsTests/DiffModelTests.swift`

**Interfaces:**
- Consumes: nothing (pure).
- Produces:
  - `enum DiffLineKind: Sendable, Equatable { case header, hunk, addition, deletion, context }`
  - `struct DiffLine: Sendable, Equatable { let kind: DiffLineKind; let text: String }`
  - `struct DiffFile: Sendable, Equatable { let path: String; let lines: [DiffLine] }`
  - `enum DiffModel { static func parse(_ patch: String) -> [DiffFile] }` — split a unified diff into per-file sections (`diff --git a/… b/…`), classify each line (`+++`/`---`/`diff`/`index` → header; `@@` → hunk; `+` → addition; `-` → deletion; else context); file path = the `b/…` path from the `+++ b/…` line (or the `diff --git` line).

- [ ] **Step 1: Write the failing test**

`Tests/DetDocViewModelsTests/DiffModelTests.swift`
```swift
import Testing
@testable import DetDocViewModels

@Test func parseClassifiesLinesPerFile() {
    let patch = """
    diff --git a/src/a.swift b/src/a.swift
    index 111..222 100644
    --- a/src/a.swift
    +++ b/src/a.swift
    @@ -1,2 +1,2 @@
     keep
    -old
    +new
    """
    let files = DiffModel.parse(patch)
    #expect(files.count == 1)
    #expect(files[0].path == "src/a.swift")
    #expect(files[0].lines.contains(DiffLine(kind: .addition, text: "+new")))
    #expect(files[0].lines.contains(DiffLine(kind: .deletion, text: "-old")))
    #expect(files[0].lines.contains(DiffLine(kind: .hunk, text: "@@ -1,2 +1,2 @@")))
    #expect(files[0].lines.contains(DiffLine(kind: .context, text: " keep")))
}

@Test func parseSplitsMultipleFiles() {
    let patch = """
    diff --git a/x b/x
    +++ b/x
    +x
    diff --git a/y b/y
    +++ b/y
    +y
    """
    #expect(DiffModel.parse(patch).map(\.path) == ["x", "y"])
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test` → build error (`DiffModel` not found).

- [ ] **Step 3: Implement**

`Sources/DetDocViewModels/DiffModel.swift`
```swift
public enum DiffLineKind: Sendable, Equatable {
    case header, hunk, addition, deletion, context
}

public struct DiffLine: Sendable, Equatable {
    public let kind: DiffLineKind
    public let text: String
    public init(kind: DiffLineKind, text: String) {
        self.kind = kind
        self.text = text
    }
}

public struct DiffFile: Sendable, Equatable {
    public let path: String
    public let lines: [DiffLine]
    public init(path: String, lines: [DiffLine]) {
        self.path = path
        self.lines = lines
    }
}

public enum DiffModel {
    public static func parse(_ patch: String) -> [DiffFile] {
        var files: [DiffFile] = []
        var currentPath: String?
        var currentLines: [DiffLine] = []

        func flush() {
            if let path = currentPath {
                files.append(DiffFile(path: path, lines: currentLines))
            }
            currentLines = []
            currentPath = nil
        }

        for raw in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("diff --git ") {
                flush()
                currentPath = line.split(separator: " ").last.map { String($0).replacingOccurrences(of: "b/", with: "") }
            }
            let kind: DiffLineKind
            if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") || line.hasPrefix("index ") {
                kind = .header
                if line.hasPrefix("+++ b/") { currentPath = String(line.dropFirst(6)) }
            } else if line.hasPrefix("@@") {
                kind = .hunk
            } else if line.hasPrefix("+") {
                kind = .addition
            } else if line.hasPrefix("-") {
                kind = .deletion
            } else {
                kind = .context
            }
            if currentPath != nil { currentLines.append(DiffLine(kind: kind, text: line)) }
        }
        flush()
        return files
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test` → all green.
- [ ] **Step 5: Commit**
```bash
git add swift/DetDocCore/Sources/DetDocViewModels/DiffModel.swift swift/DetDocCore/Tests/DetDocViewModelsTests/DiffModelTests.swift
git commit -m "feat(viewmodels): DiffModel unified-diff parser"
```

---

### Task 9: PlanReviewViewModel + PatchReviewViewModel

**Files:**
- Create: `Sources/DetDocViewModels/ReviewViewModels.swift`
- Test: `Tests/DetDocViewModelsTests/ReviewViewModelsTests.swift`

**Interfaces:**
- Consumes: `DetDocCore` (`ProposedPlan`, `PatchReview`), `DiffModel` (Task 8).
- Produces:
  - `@MainActor @Observable final class PlanReviewViewModel { init(plan: ProposedPlan); let plan: ProposedPlan; var summary/risk/questions/changes accessors }`
  - `@MainActor @Observable final class PatchReviewViewModel { init(review: PatchReview); let review: PatchReview; var diffFiles: [DiffFile] (parsed from review.patch); var changedFiles: [String]; var worktreePath: String }`

- [ ] **Step 1: Write the failing test**

`Tests/DetDocViewModelsTests/ReviewViewModelsTests.swift`
```swift
import Testing
@testable import DetDocViewModels
@testable import DetDocCore

@MainActor
@Test func planReviewExposesPlanFields() {
    let plan = ProposedPlan(summary: "do it", changes: [PlanChange(reason: "doc-diff:x", targetFiles: ["src/a.swift"], kind: "modify", rationale: "r")], questions: ["q1"], risk: "low")
    let vm = PlanReviewViewModel(plan: plan)
    #expect(vm.summary == "do it")
    #expect(vm.risk == "low")
    #expect(vm.questions == ["q1"])
    #expect(vm.changes.first?.targetFiles == ["src/a.swift"])
}

@MainActor
@Test func patchReviewParsesDiff() {
    let review = PatchReview(runId: "r1", changedFiles: ["src/a.swift"], patch: """
    diff --git a/src/a.swift b/src/a.swift
    +++ b/src/a.swift
    +new
    """, worktreePath: "/tmp/wt")
    let vm = PatchReviewViewModel(review: review)
    #expect(vm.changedFiles == ["src/a.swift"])
    #expect(vm.diffFiles.first?.path == "src/a.swift")
    #expect(vm.worktreePath == "/tmp/wt")
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test` → build error (review VMs not found).

- [ ] **Step 3: Implement**

`Sources/DetDocViewModels/ReviewViewModels.swift`
```swift
import Observation
import DetDocCore

@MainActor
@Observable
public final class PlanReviewViewModel {
    public let plan: ProposedPlan
    public init(plan: ProposedPlan) { self.plan = plan }
    public var summary: String { plan.summary }
    public var risk: String { plan.risk }
    public var questions: [String] { plan.questions }
    public var changes: [PlanChange] { plan.changes }
}

@MainActor
@Observable
public final class PatchReviewViewModel {
    public let review: PatchReview
    public let diffFiles: [DiffFile]
    public init(review: PatchReview) {
        self.review = review
        self.diffFiles = DiffModel.parse(review.patch)
    }
    public var changedFiles: [String] { review.changedFiles }
    public var worktreePath: String { review.worktreePath }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test` → all green.
- [ ] **Step 5: Commit**
```bash
git add swift/DetDocCore/Sources/DetDocViewModels/ReviewViewModels.swift swift/DetDocCore/Tests/DetDocViewModelsTests/ReviewViewModelsTests.swift
git commit -m "feat(viewmodels): PlanReview and PatchReview view models"
```

---

### Task 10: RunPanelViewModel

**Files:**
- Create: `Sources/DetDocViewModels/RunPanelViewModel.swift`
- Test: `Tests/DetDocViewModelsTests/RunPanelViewModelTests.swift`

**Interfaces:**
- Consumes: `DetDocCore` (`DetDocEngine`, `RunEvent`, `RunPhase`, `ProposedPlan`, `PatchReview`, `RunFlowResult`, `RunMode`, `AgentRunner`, `DetDocError`), `PlanReviewViewModel`/`PatchReviewViewModel` (Task 9).
- Produces:
  - `@MainActor @Observable final class RunPanelViewModel`
  - `enum Stage: Sendable, Equatable { case idle, running, planPending, patchPending, completed, failed }`
  - `init(root: URL, agent: any AgentRunner)`; observable `stage`, `currentPhase: RunPhase?`, `logLines: [String]`, `planReview: PlanReviewViewModel?`, `patchReview: PatchReviewViewModel?`, `result: RunFlowResult?`, `error: DetDocError?`.
  - `func start(mode: RunMode, message: String? = nil)` — creates a `DetDocEngine`, consumes its stream on a `Task`, mapping events to state.
  - `func approvePlan()`, `func rejectPlan()`, `func applyPatch()`, `func discardPatch()`, `func cancel()`.

- [ ] **Step 1: Write the failing test**

`Tests/DetDocViewModelsTests/RunPanelViewModelTests.swift`
```swift
import Foundation
import Testing
@testable import DetDocViewModels
@testable import DetDocCore

@MainActor
@Test func runPanelDrivesRunToCompletion() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    try fx.write("docs/idea.md", "changed idea\n")  // dirty doc drives the run

    let vm = RunPanelViewModel(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "let v = 2\n"))
    vm.start(mode: .run)

    await poll { vm.stage == .planPending }
    #expect(vm.planReview?.summary == "Fake plan")
    vm.approvePlan()

    await poll { vm.stage == .patchPending }
    #expect(vm.patchReview?.changedFiles.contains("src/app.swift") == true)
    vm.applyPatch()

    await poll { vm.stage == .completed }
    #expect(vm.result?.applied == true)
    #expect(FileManager.default.fileExists(atPath: fx.root.appendingPathComponent("src/app.swift").path))
}

@MainActor
@Test func runPanelSurfacesPlanRejection() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    try fx.write("docs/idea.md", "changed\n")
    let vm = RunPanelViewModel(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "x\n"))
    vm.start(mode: .run)
    await poll { vm.stage == .planPending }
    vm.rejectPlan()
    await poll { vm.stage == .failed }
    #expect(vm.error?.code == "PLAN_NOT_APPROVED")
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test` → build error (`RunPanelViewModel` not found).

- [ ] **Step 3: Implement**

`Sources/DetDocViewModels/RunPanelViewModel.swift`
```swift
import Foundation
import Observation
import DetDocCore

@MainActor
@Observable
public final class RunPanelViewModel {
    public enum Stage: Sendable, Equatable {
        case idle, running, planPending, patchPending, completed, failed
    }

    public private(set) var stage: Stage = .idle
    public private(set) var currentPhase: RunPhase?
    public private(set) var logLines: [String] = []
    public private(set) var planReview: PlanReviewViewModel?
    public private(set) var patchReview: PatchReviewViewModel?
    public private(set) var result: RunFlowResult?
    public private(set) var error: DetDocError?

    private let root: URL
    private let agent: any AgentRunner
    private var engine: DetDocEngine?
    private var task: Task<Void, Never>?

    public init(root: URL, agent: any AgentRunner) {
        self.root = root
        self.agent = agent
    }

    public func start(mode: RunMode, message: String? = nil) {
        guard stage == .idle || stage == .completed || stage == .failed else { return }
        reset()
        stage = .running
        let engine = DetDocEngine(root: root, agent: agent)
        self.engine = engine
        task = Task { [weak self] in
            do {
                let stream = await engine.start(mode: mode, message: message)
                for try await event in stream {
                    self?.handle(event)
                }
            } catch let e as DetDocError {
                self?.fail(e)
            } catch {
                self?.fail(DetDocError("ENGINE_FAILED", "\(error)"))
            }
        }
    }

    public func approvePlan() {
        planReview = nil
        stage = .running
        let engine = engine
        Task { await engine?.submitPlanDecision(.approve) }
    }

    public func rejectPlan() {
        let engine = engine
        Task { await engine?.submitPlanDecision(.reject) }
    }

    public func applyPatch() {
        patchReview = nil
        stage = .running
        let engine = engine
        Task { await engine?.submitApplyDecision(.apply) }
    }

    public func discardPatch() {
        let engine = engine
        Task { await engine?.submitApplyDecision(.discard) }
    }

    public func cancel() {
        task?.cancel()
    }

    private func handle(_ event: RunEvent) {
        switch event {
        case .progress(let phase, _):
            currentPhase = phase
        case .log(let line):
            logLines.append(line)
        case .planReady(let plan):
            planReview = PlanReviewViewModel(plan: plan)
            stage = .planPending
        case .patchReady(let review):
            patchReview = PatchReviewViewModel(review: review)
            stage = .patchPending
        case .error(let e):
            fail(e)
        case .complete(let r):
            result = r
            stage = .completed
        }
    }

    private func fail(_ e: DetDocError) {
        error = e
        stage = .failed
    }

    private func reset() {
        currentPhase = nil
        logLines = []
        planReview = nil
        patchReview = nil
        result = nil
        error = nil
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd swift/DetDocCore && swift test`
Expected: PASS — both RunPanel tests green and the whole suite. The `Task` created in `start()` inherits `@MainActor` (the method is MainActor-isolated), so `handle` runs on the main actor and the `@Observable` mutations are safe; gate answers are dispatched via `Task { await engine?.submit… }`. If a test hangs, confirm `poll` is bounded (it fatalErrors on timeout) and that the engine's cancellable gates (Plan 2) are present.

- [ ] **Step 5: Commit**
```bash
git add swift/DetDocCore/Sources/DetDocViewModels/RunPanelViewModel.swift swift/DetDocCore/Tests/DetDocViewModelsTests/RunPanelViewModelTests.swift
git commit -m "feat(viewmodels): RunPanelViewModel driving DetDocEngine + gates"
```

---

### Task 11: Full-suite green gate

**Files:** none (verification only).

- [ ] **Step 1: Run the entire suite** — `cd swift/DetDocCore && swift test` → all DetDocCore + DetDocViewModels tests pass.
- [ ] **Step 2: Warnings-clean build** — `swift build` (both `DetDocCore` and `DetDocViewModels` carry `treatAllWarnings(as: .error)`).
- [ ] **Step 3: Commit any fixes** — `git add -A swift/DetDocCore && git commit -m "test(viewmodels): green gate for DetDocViewModels" --allow-empty`

---

## Self-Review

**1. Spec coverage (app-logic slice):** routing/coordinator → T2; workspace status/docs/runs → T3; doc editor source+preview+save → T4; saved-runs list+apply → T5; settings config edit → T6 (+ `ConfigStore.write`); onboarding/init → T7; patch diff model → T8; plan/patch review → T9; run/fix panel driving the engine + gates → T10. SwiftUI views, XcodeGen project, NSOpenPanel folder picker, and a launch smoke are explicitly **Plan 3b**.

**2. Placeholder scan:** every step has full test + implementation code. No TBD/"handle errors"/"similar to". ✓

**3. Type consistency:** `AppRoute`/`FolderPicking`/`AppCoordinator` (T2) used as defined; every view model is `@MainActor @Observable final class` taking `root: URL` (+ `config`/`agent` where needed); `RunPanelViewModel.Stage` cases match the test; `PlanReviewViewModel(plan:)` / `PatchReviewViewModel(review:)` match T9; `ConfigStore.write(_:root:)` defined in T6 and called there; `DiffModel.parse` / `DiffFile` / `DiffLine` consistent (T8/T9). All DetDocCore calls match Plan 1/2 signatures.

**Risk note:** T10's `RunPanelViewModel` is the one non-mechanical view model (engine stream consumption + gate dispatch on `@MainActor`). The Plan 2 engine's cancellable gates make `cancel()` safe. Keep `start()`'s `Task` inheriting `@MainActor` so `@Observable` mutations stay main-actor-isolated.

---

## Next Plan

- **Plan 3b — DetDocApp (SwiftUI + XcodeGen):** the macOS app target — `@main` App, `NavigationSplitView` + `.inspector` workspace, `DocsExplorerView`, source+preview `DocEditorView`, `DetDocPanelView` (run/fix + progress + gates), `PlanReviewView`, `PatchReviewView` (DiffModel renderer), `RunsView`, `SettingsView`, `OnboardingView`/`PiSetupView`, an `NSOpenPanel`-backed `FolderPicking`, wired to these view models. Built/smoke-tested via `xcodegen generate` + `xcodebuild`. (Consult superpowers' swiftui-expert-skill for the latest macOS 27 SwiftUI APIs.)
