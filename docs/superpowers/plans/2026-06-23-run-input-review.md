# Pre-Run Documentation Diff Review — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After **Run docs**, show a modal with the documentation diff that will drive the run; the run only starts after the user confirms.

**Architecture:** Add a third gate to `DetDocEngine` (alongside the existing plan and apply gates) that fires for `mode == .run` right after the doc diff is computed and *before* any worktree or run artifacts are created. The engine emits `RunEvent.inputReady(diff)` and suspends on a `CheckedContinuation` until the view model submits `submitInputDecision(.confirm/.cancel)`. `RunPanelViewModel` exposes a new `.inputPending` stage; `WorkspaceView` presents the diff as a `.sheet`. The per-file diff renderer is extracted from `PatchReviewView` into a shared `DiffFilesView`.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing (`@Test`/`#expect`), Observation (`@Observable`). Core is the SwiftPM package `DetDocCore`; the app is the Tuist target `DetDoc`.

## Global Constraints

- Every SwiftUI view MUST have a `#Preview` with multiple states (CLAUDE.md).
- Every view MUST have accessibility identifiers (CLAUDE.md).
- `RunEvent.logLine` is content-free for OSLog: never log diff/patch bodies, only counts/sizes/codes.
- This is Slice 1 only. Do NOT add the parallelization analysis, the parallel toggle, or sub-agent execution — that is a separate spec/plan.
- The gate applies to `mode == .run` only. `mode == .fix` flow is unchanged.

## File Structure

| File | Responsibility | Change |
|------|----------------|--------|
| `swift/DetDocCore/Sources/DetDocCore/Engine/RunEvent.swift` | Event + decision enums + content-free log lines | Add `.inputReady`, `InputDecision`, `RunPhase.reviewInput`, logLine case |
| `swift/DetDocCore/Sources/DetDocCore/Engine/DetDocEngine.swift` | Run flow orchestration + gate continuations | Add input continuation + gate before `createRun` |
| `swift/DetDocCore/Tests/DetDocCoreTests/FlowFakeAgentTests.swift` | End-to-end flow tests (fake agent) | Update `drive` to confirm input |
| `swift/DetDocCore/Tests/DetDocCoreTests/FlowCodeLinksTests.swift` | Code-link flow tests | Update 4 stream loops to confirm input |
| `swift/DetDocCore/Tests/DetDocCoreTests/InputReviewGateTests.swift` | New gate-behavior tests | **Create** |
| `swift/DetDocApp/Sources/Workspace/Runs/RunPanelViewModel.swift` | UI-facing run state machine | Add `.inputPending` stage, `inputDiff`, confirm/cancel, cancel→idle mapping |
| `swift/DetDocApp/Sources/Workspace/Runs/RunInspectorView.swift` | Inspector status panel | Add `.inputPending` case |
| `swift/DetDocApp/Tests/RunPanelViewModelTests.swift` | VM behavior tests | Update existing 3 tests + add 2 gate tests |
| `swift/DetDocApp/Sources/Workspace/Review/DiffFilesView.swift` | Shared per-file diff renderer | **Create** (extracted from PatchReviewView) |
| `swift/DetDocApp/Sources/Workspace/Review/PatchReviewView.swift` | Patch review (apply gate) | Use `DiffFilesView` |
| `swift/DetDocApp/Sources/Workspace/Review/InputReviewView.swift` | The pre-run review modal body | **Create** |
| `swift/DetDocApp/Sources/Workspace/WorkspaceView.swift` | Workspace shell + run trigger | Add `.sheet` for `.inputPending` |

**Run core tests:** `swift test --package-path swift/DetDocCore`
**Build/test app:** Xcode MCP — `mcp__xcode__BuildProject`, `mcp__xcode__RunSomeTests`/`RunAllTests`, `mcp__xcode__RenderPreview`.

---

### Task 1: Engine input-review gate (DetDocCore)

Introduces the gate in the core and keeps the core test suite green. The `DetDocApp` target will not compile until Task 2 (the new `RunEvent` case forces an exhaustive-switch update there); that is expected — verify Task 1 against the **DetDocCore package only**.

**Files:**
- Modify: `swift/DetDocCore/Sources/DetDocCore/Engine/RunEvent.swift`
- Modify: `swift/DetDocCore/Sources/DetDocCore/Engine/DetDocEngine.swift`
- Modify: `swift/DetDocCore/Tests/DetDocCoreTests/FlowFakeAgentTests.swift`
- Modify: `swift/DetDocCore/Tests/DetDocCoreTests/FlowCodeLinksTests.swift`
- Create: `swift/DetDocCore/Tests/DetDocCoreTests/InputReviewGateTests.swift`

**Interfaces:**
- Produces: `RunEvent.inputReady(String)`; `enum InputDecision { case confirm, cancel }`; `DetDocEngine.submitInputDecision(_ decision: InputDecision)`; `RunPhase.reviewInput` (raw `"review_input"`); error code `"RUN_CANCELLED_BY_USER"`.
- Consumes: existing `RunEvent`, `RunPhase`, `DetDocEngine` gate pattern (`submitPlanDecision`, `awaitPlanDecision`, `failPendingPlan`), `FakeAgentRunner`, `GitFixture`, `ConfigStore`.

- [ ] **Step 1: Write the failing gate tests**

Create `swift/DetDocCore/Tests/DetDocCoreTests/InputReviewGateTests.swift`:

```swift
import Foundation
import Testing
@testable import DetDocCore

private func detdocRepo() async throws -> GitFixture {
    let fx = try await GitFixture()
    try ConfigStore().initFiles(root: fx.root)
    try await fx.commitAll("detdoc init")
    return fx
}

@Test func runFlowEmitsInputReadyBeforePlanReady() async throws {
    let fx = try await detdocRepo()
    try fx.write("docs/idea.md", "changed\n")
    let engine = DetDocEngine(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "let v = 9\n"))
    var phases: [String] = []
    let stream = await engine.start(mode: .run)
    for try await event in stream {
        switch event {
        case .inputReady: phases.append("input"); await engine.submitInputDecision(.confirm)
        case .planReady: phases.append("plan"); await engine.submitPlanDecision(.approve)
        case .patchReady: phases.append("patch"); await engine.submitApplyDecision(.apply)
        default: break
        }
    }
    #expect(phases == ["input", "plan", "patch"])
}

@Test func runFlowCancelAtInputGateCreatesNoRun() async throws {
    let fx = try await detdocRepo()
    try fx.write("docs/idea.md", "changed\n")
    let engine = DetDocEngine(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "x\n"))
    await #expect {
        let stream = await engine.start(mode: .run)
        for try await event in stream {
            if case .inputReady = event { await engine.submitInputDecision(.cancel) }
        }
    } throws: { ($0 as? DetDocError)?.code == "RUN_CANCELLED_BY_USER" }
    // Gate precedes createRun: no run artifacts exist.
    let runsDir = fx.root.appendingPathComponent(".detdoc/runs")
    let entries = (try? FileManager.default.contentsOfDirectory(atPath: runsDir.path)) ?? []
    #expect(entries.filter { $0 != ".gitkeep" }.isEmpty)
}

@Test func fixFlowEmitsNoInputReady() async throws {
    let fx = try await detdocRepo()
    let engine = DetDocEngine(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "x\n"))
    var sawInput = false
    let stream = await engine.start(mode: .fix, message: "fix the bug")
    for try await event in stream {
        switch event {
        case .inputReady: sawInput = true
        case .planReady: await engine.submitPlanDecision(.approve)
        case .patchReady: await engine.submitApplyDecision(.apply)
        default: break
        }
    }
    #expect(!sawInput)
}
```

- [ ] **Step 2: Run the new tests to verify they fail to compile**

Run: `swift test --package-path swift/DetDocCore --filter InputReviewGate`
Expected: FAIL — compile error, `inputReady`/`submitInputDecision`/`InputDecision` not found.

- [ ] **Step 3: Add the event, decision enum, phase, and log line**

In `swift/DetDocCore/Sources/DetDocCore/Engine/RunEvent.swift`:

Add to `RunPhase`, immediately after `case collectInput = "collect_input"`:

```swift
    case reviewInput = "review_input"
```

Add a case to `enum RunEvent`, after `case progress(...)`:

```swift
    case inputReady(String)
```

Add to `RunEvent.logLine`'s switch (it is exhaustive), before `case .error`:

```swift
        case .inputReady(let diff): return "inputReady bytes=\(diff.utf8.count)"
```

Add the decision enum next to the others at the bottom of the file:

```swift
public enum InputDecision: Sendable { case confirm, cancel }
```

- [ ] **Step 4: Add the gate continuation to the engine**

In `swift/DetDocCore/Sources/DetDocCore/Engine/DetDocEngine.swift`, add a stored continuation next to `pendingPlan`/`pendingApply`:

```swift
    private var pendingInput: CheckedContinuation<InputDecision, Error>?
```

Add the submit method next to `submitPlanDecision`:

```swift
    public func submitInputDecision(_ decision: InputDecision) {
        pendingInput?.resume(returning: decision)
        pendingInput = nil
    }
```

Add the await + fail helpers next to `awaitPlanDecision`/`failPendingPlan`:

```swift
    private func awaitInputDecision() async throws -> InputDecision {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<InputDecision, Error>) in
                self.pendingInput = c
            }
        } onCancel: {
            Task { await self.failPendingInput() }
        }
    }

    private func failPendingInput() {
        pendingInput?.resume(throwing: CancellationError())
        pendingInput = nil
    }
```

- [ ] **Step 5: Insert the gate into the flow**

In `DetDocEngine.runFlow`, immediately after the `taskInput` `if mode == .run { ... } else { ... }` block and **before** `emit(.progress(phase: .createRun, ...))`, insert:

```swift
        if mode == .run {
            emit(.progress(phase: .reviewInput, message: "Waiting for diff review"))
            emit(.inputReady(taskInput))
            if try await awaitInputDecision() == .cancel {
                throw DetDocError("RUN_CANCELLED_BY_USER", "Run cancelled before start.")
            }
        }
```

- [ ] **Step 6: Update existing core flow consumers to confirm input**

In `swift/DetDocCore/Tests/DetDocCoreTests/FlowFakeAgentTests.swift`, in the `drive` helper's `switch event`, add a case (the engine now suspends at the input gate; without this the stream never advances):

```swift
        case .inputReady: await engine.submitInputDecision(.confirm)
```

In `swift/DetDocCore/Tests/DetDocCoreTests/FlowCodeLinksTests.swift`, every `for try await event in stream` loop (there are 4) has a `switch event` with `case .planReady` / `case .patchReady`. Add this case to each of the 4 switches:

```swift
        case .inputReady: await engine.submitInputDecision(.confirm)
```

- [ ] **Step 7: Run the full core suite**

Run: `swift test --package-path swift/DetDocCore`
Expected: PASS — new `InputReviewGate` tests pass; `FlowFakeAgent` and `FlowCodeLinks` tests still pass (they now confirm the gate). No test hangs.

- [ ] **Step 8: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Engine/RunEvent.swift \
        swift/DetDocCore/Sources/DetDocCore/Engine/DetDocEngine.swift \
        swift/DetDocCore/Tests/DetDocCoreTests/FlowFakeAgentTests.swift \
        swift/DetDocCore/Tests/DetDocCoreTests/FlowCodeLinksTests.swift \
        swift/DetDocCore/Tests/DetDocCoreTests/InputReviewGateTests.swift
git commit -m "feat(core): input-review gate before run starts"
```

---

### Task 2: View-model + inspector wiring (DetDocApp)

Restores the `DetDocApp` build (the new `RunEvent` case forces a `handle` update) and adds the `.inputPending` stage and confirm/cancel behavior, including mapping the pre-run cancel back to `.idle` rather than `.failed`.

**Files:**
- Modify: `swift/DetDocApp/Sources/Workspace/Runs/RunPanelViewModel.swift`
- Modify: `swift/DetDocApp/Sources/Workspace/Runs/RunInspectorView.swift`
- Modify: `swift/DetDocApp/Tests/RunPanelViewModelTests.swift`

**Interfaces:**
- Consumes: `RunEvent.inputReady`, `InputDecision`, `DetDocEngine.submitInputDecision` (Task 1).
- Produces: `RunPanelViewModel.Stage.inputPending`; `RunPanelViewModel.inputDiff: String?`; `RunPanelViewModel.confirmInput()`; `RunPanelViewModel.cancelInput()`.

- [ ] **Step 1: Update existing VM tests + add gate tests (failing)**

In `swift/DetDocApp/Tests/RunPanelViewModelTests.swift`, the three existing tests call `vm.start(mode: .run)` then `await poll { await vm.stage == .planPending }`. After each `vm.start(mode: .run)` line, insert the input-gate confirm:

```swift
    await poll { await vm.stage == .inputPending }
    vm.confirmInput()
```

So, for example, `runPanelDrivesRunToCompletion` becomes:

```swift
    vm.start(mode: .run)
    await poll { await vm.stage == .inputPending }
    vm.confirmInput()
    await poll { await vm.stage == .planPending }
```

Apply the same two-line insertion in `runPanelSurfacesPlanRejection` and `runPanelCancelEndsInFailedStateWithStableCode`.

Then append two new tests:

```swift
@MainActor
@Test func runPanelOpensInputReviewBeforePlan() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    try fx.write("docs/idea.md", "changed idea\n")
    let vm = RunPanelViewModel(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "x\n"))
    vm.start(mode: .run)
    await poll { await vm.stage == .inputPending }
    #expect(vm.inputDiff?.isEmpty == false)
    vm.confirmInput()
    await poll { await vm.stage == .planPending }
    #expect(vm.inputDiff == nil)
}

@MainActor
@Test func runPanelCancelInputReturnsToIdle() async throws {
    let fx = try await VMGitFixture()
    try await fx.detdocInit()
    try fx.write("docs/idea.md", "changed idea\n")
    let vm = RunPanelViewModel(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "x\n"))
    vm.start(mode: .run)
    await poll { await vm.stage == .inputPending }
    vm.cancelInput()
    await poll { await vm.stage == .idle }
    #expect(vm.error == nil)
    #expect(vm.inputDiff == nil)
}
```

- [ ] **Step 2: Build to verify failure**

Run: `mcp__xcode__BuildProject` (DetDoc scheme).
Expected: FAIL — `RunPanelViewModel.handle` switch not exhaustive (`inputReady` unhandled); `RunInspectorView` switch not exhaustive (`.inputPending`); `confirmInput`/`cancelInput`/`inputDiff` undefined.

- [ ] **Step 3: Add the stage, state, and event handling to the VM**

In `swift/DetDocApp/Sources/Workspace/Runs/RunPanelViewModel.swift`:

Add `inputPending` to the `Stage` enum:

```swift
        case idle, running, inputPending, planPending, patchPending, completed, failed
```

Add the published diff property after `public private(set) var stage: Stage = .idle`:

```swift
    public private(set) var inputDiff: String?
```

Add the handling case in `handle(_:)`, before `case .planReady`:

```swift
        case .inputReady(let diff):
            inputDiff = diff
            stage = .inputPending
```

Add the confirm/cancel methods next to `approvePlan()`:

```swift
    public func confirmInput() {
        DetDocLog.run.notice("user confirmed input diff")
        inputDiff = nil
        stage = .running
        let engine = engine
        Task { await engine?.submitInputDecision(.confirm) }
    }

    public func cancelInput() {
        DetDocLog.run.notice("user cancelled input diff")
        let engine = engine
        Task { await engine?.submitInputDecision(.cancel) }
    }
```

- [ ] **Step 4: Map the pre-run cancel to idle, and clear `inputDiff` on reset**

In `RunPanelViewModel.fail(_:)`, add the cancel mapping at the top (a pre-run cancel is not a failure):

```swift
    private func fail(_ e: DetDocError) {
        if e.code == "RUN_CANCELLED_BY_USER" {
            DetDocLog.run.notice("run cancelled at input gate")
            inputDiff = nil
            error = nil
            stage = .idle
            return
        }
        DetDocLog.run.error("run failed code=\(e.code, privacy: .public) \(e.message, privacy: .public)")
        error = e
        stage = .failed
    }
```

In `RunPanelViewModel.reset()`, add:

```swift
        inputDiff = nil
```

- [ ] **Step 5: Handle `.inputPending` in the inspector**

In `swift/DetDocApp/Sources/Workspace/Runs/RunInspectorView.swift`, add a case to the `content` switch, before `case .planPending`:

```swift
        case .inputPending:
            Label("Review the diff in the dialog to start the run.", systemImage: "doc.text.magnifyingglass")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("inspector-input-pending")
```

- [ ] **Step 6: Build and run the VM tests**

Run: `mcp__xcode__BuildProject` then `mcp__xcode__RunSomeTests` filtered to `RunPanelViewModelTests`.
Expected: PASS — all five VM tests pass (three updated, two new).

- [ ] **Step 7: Commit**

```bash
git add swift/DetDocApp/Sources/Workspace/Runs/RunPanelViewModel.swift \
        swift/DetDocApp/Sources/Workspace/Runs/RunInspectorView.swift \
        swift/DetDocApp/Tests/RunPanelViewModelTests.swift
git commit -m "feat(app): input-pending stage + confirm/cancel in run panel"
```

---

### Task 3: The review modal (DetDocApp UI)

Extracts the shared diff renderer, builds the modal body, and presents it as a sheet. SwiftUI views are verified by build + `RenderPreview` (live GUI automation is unreliable per project notes).

**Files:**
- Create: `swift/DetDocApp/Sources/Workspace/Review/DiffFilesView.swift`
- Modify: `swift/DetDocApp/Sources/Workspace/Review/PatchReviewView.swift`
- Create: `swift/DetDocApp/Sources/Workspace/Review/InputReviewView.swift`
- Modify: `swift/DetDocApp/Sources/Workspace/WorkspaceView.swift`

**Interfaces:**
- Consumes: `DiffModel.parse`, `DiffFile`, `DiffLineKind` (existing); `RunPanelViewModel.inputDiff`, `.confirmInput()`, `.cancelInput()`, `.stage == .inputPending` (Task 2).
- Produces: `DiffFilesView(files: [DiffFile])`; `InputReviewView(diff:onRun:onCancel:)`.

- [ ] **Step 1: Create the shared `DiffFilesView`**

Create `swift/DetDocApp/Sources/Workspace/Review/DiffFilesView.swift` (the per-file render + colors moved out of `PatchReviewView`; the caller applies any `maxHeight`):

```swift
import SwiftUI

/// Scrollable per-file unified-diff renderer shared by the patch-apply gate and the
/// pre-run input review. One source of truth for diff line colors/backgrounds.
struct DiffFilesView: View {
    let files: [DiffFile]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(files, id: \.path) { file in
                    Text(file.path)
                        .font(.system(.caption, design: .monospaced)).bold()
                        .accessibilityIdentifier("diff-file-\(file.path)")
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(file.lines.enumerated()), id: \.offset) { _, line in
                            Text(line.text)
                                .font(.system(.caption2, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(color(for: line.kind))
                                .background(background(for: line.kind))
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("diff-files")
    }

    private func color(for kind: DiffLineKind) -> Color {
        switch kind {
        case .addition: .green
        case .deletion: .red
        case .hunk: .purple
        case .header: .secondary
        case .context: .primary
        }
    }
    private func background(for kind: DiffLineKind) -> Color {
        switch kind {
        case .addition: .green.opacity(0.12)
        case .deletion: .red.opacity(0.12)
        default: .clear
        }
    }
}

#Preview("Two files") {
    DiffFilesView(files: DiffModel.parse("""
    diff --git a/docs/api.md b/docs/api.md
    --- a/docs/api.md
    +++ b/docs/api.md
    @@ -1,2 +1,2 @@
    -old line
    +new line
     context
    diff --git a/docs/guide.md b/docs/guide.md
    --- a/docs/guide.md
    +++ b/docs/guide.md
    @@ -1 +1,2 @@
     intro
    +added paragraph
    """))
    .frame(width: 480, height: 240)
}
```

- [ ] **Step 2: Point `PatchReviewView` at `DiffFilesView`**

Replace the `ScrollView { ... }.frame(maxHeight: 280)` block and the two private `color`/`background` helpers in `swift/DetDocApp/Sources/Workspace/Review/PatchReviewView.swift` so the file reads:

```swift
import SwiftUI

struct PatchReviewView: View {
    let patch: PatchReviewViewModel
    let onApply: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Review changes").font(.headline)
            Text("\(patch.changedFiles.count) file(s)").font(.caption).foregroundStyle(.secondary)
            DiffFilesView(files: patch.diffFiles).frame(maxHeight: 280)
            if !patch.worktreePath.isEmpty {
                Text("Worktree: \(patch.worktreePath)").font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
            }
            HStack {
                Button("Apply", action: onApply).buttonStyle(.borderedProminent)
                Button("Discard", role: .destructive, action: onDiscard)
            }.padding(.top, 4)
        }
    }
}
```

- [ ] **Step 3: Create `InputReviewView`**

Create `swift/DetDocApp/Sources/Workspace/Review/InputReviewView.swift`:

```swift
import SwiftUI

/// Pre-run modal: shows the documentation diff that will drive the run and gates the start.
struct InputReviewView: View {
    let diff: String
    let onRun: () -> Void
    let onCancel: () -> Void

    private var files: [DiffFile] { DiffModel.parse(diff) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review changes before running").font(.headline)
            Text("\(files.count) documentation file(s) will drive this run.")
                .font(.caption).foregroundStyle(.secondary)
            DiffFilesView(files: files).frame(maxHeight: 320)
            HStack {
                Button("Run", action: onRun)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("input-review-run")
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("input-review-cancel")
            }.padding(.top, 4)
        }
        .padding()
        .frame(minWidth: 480, minHeight: 360)
        .accessibilityIdentifier("input-review-sheet")
    }
}

private let oneFileDiff = """
diff --git a/docs/idea.md b/docs/idea.md
--- a/docs/idea.md
+++ b/docs/idea.md
@@ -1,2 +1,2 @@
-old idea
+new idea
 unchanged
"""

private let manyFilesDiff = oneFileDiff + "\n" + """
diff --git a/docs/api.md b/docs/api.md
--- a/docs/api.md
+++ b/docs/api.md
@@ -1 +1,2 @@
 intro
+added line
"""

private let largeDiff = "diff --git a/docs/big.md b/docs/big.md\n--- a/docs/big.md\n+++ b/docs/big.md\n@@ -1,40 +1,40 @@\n"
    + (1...40).map { "+line \($0)" }.joined(separator: "\n")

#Preview("Single file") {
    InputReviewView(diff: oneFileDiff, onRun: {}, onCancel: {})
}

#Preview("Many files") {
    InputReviewView(diff: manyFilesDiff, onRun: {}, onCancel: {})
}

#Preview("Large diff (scrolls)") {
    InputReviewView(diff: largeDiff, onRun: {}, onCancel: {})
}
```

- [ ] **Step 4: Present the modal from `WorkspaceView`**

In `swift/DetDocApp/Sources/Workspace/WorkspaceView.swift`, add a sheet next to the existing `.sheet(...)` modifiers (after the `showSettings` sheet on line 147). The binding maps `.inputPending` to presentation and treats system dismissal (Esc / click-away) as cancel:

```swift
        .sheet(isPresented: Binding(
            get: { panel.stage == .inputPending },
            set: { presented in
                if !presented && panel.stage == .inputPending { panel.cancelInput() }
            }
        )) {
            InputReviewView(
                diff: panel.inputDiff ?? "",
                onRun: { panel.confirmInput() },
                onCancel: { panel.cancelInput() }
            )
        }
```

- [ ] **Step 5: Build, run all app tests, render previews**

Run: `mcp__xcode__BuildProject`
Expected: build succeeds.
Run: `mcp__xcode__RunAllTests` (or `RunSomeTests` for `DocEditorViewModelTests`, `RunPanelViewModelTests`, `ReviewViewModelsTests`).
Expected: PASS — no regressions.
Run: `mcp__xcode__RenderPreview` for `InputReviewView` ("Single file", "Many files", "Large diff (scrolls)") and `DiffFilesView` ("Two files").
Expected: each renders; the large diff scrolls within `maxHeight: 320`.

- [ ] **Step 6: Commit**

```bash
git add swift/DetDocApp/Sources/Workspace/Review/DiffFilesView.swift \
        swift/DetDocApp/Sources/Workspace/Review/PatchReviewView.swift \
        swift/DetDocApp/Sources/Workspace/Review/InputReviewView.swift \
        swift/DetDocApp/Sources/Workspace/WorkspaceView.swift
git commit -m "feat(app): pre-run documentation diff review modal"
```

---

## Self-Review

**Spec coverage:**
- "Show the doc diff in a modal after Run docs, before the run starts" → Task 1 gate (emits diff before `createRun`) + Task 3 sheet. ✓
- "Confirm / cancel from the modal" → Task 2 `confirmInput`/`cancelInput`, Task 3 buttons. ✓
- "No worktree/artifacts until confirm" → gate placed before `createRun`/`createWorktree`; `runFlowCancelAtInputGateCreatesNoRun` asserts it. ✓
- "Reuse the existing diff renderer" → Task 3 `DiffFilesView` extraction, used by both gates. ✓
- "Gate in the engine; every `.run` entry gets it" → Task 1 in `runFlow` (covers the toolbar button, `DETDOC_AUTORUN`, and any future caller). ✓
- "No fix-mode gate" → gate guarded by `if mode == .run`; `fixFlowEmitsNoInputReady` asserts it. ✓
- "Cancel returns to idle, not failed" → Task 2 `fail` mapping; `runPanelCancelInputReturnsToIdle` asserts it. ✓
- "NO_DOC_CHANGES / dirty non-doc unchanged" → `DocDiff.normalized` throws during `collectInput`, before the gate; not modified. ✓
- Previews + a11y IDs (CLAUDE.md) → Task 3 previews and identifiers on every new view. ✓

**Placeholder scan:** No TBD/TODO; all steps contain concrete code and exact commands. ✓

**Type consistency:** `inputReady(String)`, `InputDecision`, `submitInputDecision`, `RunPhase.reviewInput`, `Stage.inputPending`, `inputDiff`, `confirmInput()`/`cancelInput()`, `DiffFilesView(files:)`, `InputReviewView(diff:onRun:onCancel:)`, and code `"RUN_CANCELLED_BY_USER"` are used identically across tasks. ✓
