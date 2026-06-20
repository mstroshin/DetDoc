# DetDocCore Process / Git / Flow Implementation Plan (Plan 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the process/git/flow layer of `DetDocCore`: a `git` subprocess wrapper, worktree lifecycle, docs CRUD, normalized doc-diff + dirty policy, validation-command runner, the `AgentRunner` protocol + `FakeAgentRunner`, pi health, saved-run apply, and the `DetDocEngine` orchestrator that streams `RunEvent`s and pauses at plan/apply approval gates — all UI-agnostic and tested headless with Swift Testing.

**Architecture:** Builds on Plan 1's `DetDocCore` foundation (models, config, path policy, validators, artifacts). Everything here stays pure Swift, depends only on Foundation + Yams, and is reusable by a future Swift TUI. Git is driven by shelling out to the `git` binary (as the Rust/TS references do). The engine is an `actor` exposing `AsyncThrowingStream<RunEvent>` plus `submitPlanDecision`/`submitApplyDecision`.

**Tech Stack:** Swift 6.4, SwiftPM, Swift Testing, Foundation (`Process`, `Pipe`, `FileManager`), Yams.

## Global Constraints

- Platform floor **macOS 27**; **pure Swift**; tests use **Swift Testing**; `DetDocCore` stays UI-agnostic (no SwiftUI/AppKit); only external dep is **Yams**.
- All public types `Sendable`; models `Codable`. The `DetDocCore` target keeps `swiftSettings: [.treatAllWarnings(as: .error)]` (Plan 1) — code must be warning-clean.
- Preserve on-disk artifact/config field names & shapes so Rust/TS-produced runs remain readable.
- Stable `DetDocError` codes copied verbatim from the references (listed per task).
- Git invocations always prefix `-c core.quotepath=false` (TS/Rust parity).
- Glob semantics already match globset (Plan 1 C1 fix): `*`/`?` cross `/`.

## Reference Parity Facts (verbatim from src/core/*.ts and src-tauri/src/detdoc/*.rs)

- `git(args)` → `git -c core.quotepath=false <args>`; failure raises `GIT_COMMAND_FAILED` (stderr in message); spawn failure `GIT_SPAWN_FAILED`.
- `headCommit` → `rev-parse HEAD` trimmed.
- `statusPorcelain` → `git status --porcelain -uall`; each non-empty line → `status = line[0..<2]`, `path = line[3...]`.
- `applyPatch(patch)` → `git -c core.quotepath=false apply --binary --whitespace=nowarn -` with `patch` on stdin; failure `GIT_APPLY_FAILED`.
- `diffPaths(paths)` → `git diff --no-color --no-ext-diff --binary -- <paths>` (empty `paths` → `""`).
- `changedFilesFromPatch(patch)` → `git apply --numstat -` with patch on stdin; each line's last tab-field is the path.
- `fileSha256(path)` → SHA-256 hex of the file bytes at `cwd/path`, or `nil` if unreadable.
- WorktreeManager.createFromHead → mkdir `<root>/.worktrees`; base = head; `git worktree add -b <runId> <root>/.worktrees/<runId> <base>`. cleanup → if path exists `git worktree remove --force <path>`, then `git branch -D <runId>`.
- Dirty policy `nonDocOffenders(dirty, config)` = entries where path is NOT `.detdoc/`-prefixed, NOT `.gitignore`, and NOT `isDoc`. Non-empty → `DIRTY_NON_DOC_CHANGES` (offenders joined by `, `).
- `normalizedDocDiff` (run): compute dirty; offenders non-empty → `DIRTY_NON_DOC_CHANGES`; docPaths = `isDoc` entries; empty → `NO_DOC_CHANGES`; `git add -N -- <docPaths>` (ignore failure, to include untracked docs); return `diffPaths(docPaths)`.
- `runValidationCommands(cwd, config)`: for each command append `"\n# {name}\n$ {run}\n"`, run `{run}` via shell in `cwd`; append stdout+stderr; on non-zero exit append output then raise `VALIDATION_FAILED` with `"Validation command failed: {name}\n{log}"`. Return `log` with leading whitespace trimmed.
- `collectPatchForTargets(repo, approvedTargets)`: empty targets → `NO_APPROVED_TARGETS`; `git add -N -- <targets>` (ignore failure); `patch = diffPaths(targets)`; empty → `EMPTY_PATCH`; ensure trailing `\n`.
- AgentRunner: `plan(PlanRequest)->ProposedPlan`; `implement(ImplementRequest)`; optional `repairValidation(RepairRequest)`. `PlanRequest{mode,input,config,cwd}`. `ImplementRequest{mode,input,config,cwd,approvedPlan,approvedTargets,progress}`. `RepairRequest` adds `{validationLog,attempt}`.
- Manifest `touchedFiles: [{path, before:String?, after:String?}]`. Apply guard: HEAD ≠ baseCommit → `APPLY_BASE_MISMATCH`; any `fileSha256(path) != before` → `APPLY_PREIMAGE_MISMATCH`.
- Run flow phases (mirror FlowProgressPhase): loadConfig, collectInput, createRun, createWorktree, applyInputToWorktree, plan, approvePlan, implement, collectPatch, validatePatch, repairValidation, approveApply, applyPatch, postApplyValidation, cleanupRun, commit, cleanupWorktree, done.
- `maxValidationRepairAttempts = 2`.
- Commit step (DetDoc-GUI fixed behavior, NOT TS `add -A`): ensure managed gitignore entries; `git add -- <approvedTargets>`; `git commit -m "DetDoc apply <runId>"`. No clean-tree assert (intent docs stay dirty). When auto-commit is off: `git add -- <approvedTargets>` only, no commit.

## Design Decisions (this plan)

- **RunManifest change:** replace Plan 1's `preImageHashes: [String:String]` with `touchedFiles: [TouchedFile]` where `TouchedFile{path:String, before:String?, after:String?}` (TS shape; closes the replay gap and reads both predecessors). Plan 1's `RunManifestTests` is updated accordingly.
- **Apply commit is scoped** to `approvedTargets` (not `add -A`), with NO `GIT_NOT_CLEAN_AFTER_APPLY` assert. Rationale: the doc-driven flow legitimately leaves the user's intent docs dirty on main; `add -A` would sweep unrelated dirty files (the exact bug the Rust GUI fixed). This diverges from the Swift design doc's "verify clean status" line — flagged for the human at final review.
- **Engine gates:** `DetDocEngine` (actor) emits `.planReady`/`.patchReady` then suspends on a stored `CheckedContinuation`; the consumer resumes it via `submitPlanDecision`/`submitApplyDecision`. UI-agnostic; equally drivable by a TUI.

---

## File Structure

```txt
swift/DetDocCore/Sources/DetDocCore/
  Support/
    ProcessRunner.swift          # async subprocess runner (Process+Pipe)
    GitignoreManager.swift       # ensureManagedEntries(root:)
  Services/
    GitRepository.swift          # git subprocess wrapper
    WorktreeManager.swift        # .worktrees/<runId> lifecycle
    DocsService.swift            # list/read/write/create/rename/delete
    DirtyPolicy.swift            # nonDocOffenders + assertRunDirty/assertFixDirty
    DocDiff.swift                # normalizedDocDiff
    ValidationRunner.swift       # runValidationCommands
    PiHealth.swift               # pi --version probe
    PatchCollector.swift         # collectPatchForTargets
    RunApplier.swift             # applySavedRun
  Agent/
    AgentRunner.swift            # protocol + request/result types + TokenUsage helpers
    FakeAgentRunner.swift        # deterministic test agent
  Engine/
    RunEvent.swift               # RunEvent, RunPhase, PlanDecision, ApplyDecision, PatchReview
    DetDocEngine.swift           # run/fix orchestration
  Models/
    RunManifest.swift            # MODIFIED: touchedFiles + initial(...) factory
swift/DetDocCore/Tests/DetDocCoreTests/
  Support/GitFixture.swift       # temp git repo helper
  GitRepositoryTests.swift
  WorktreeManagerTests.swift
  DocsServiceTests.swift
  DirtyPolicyTests.swift
  DocDiffTests.swift
  ValidationRunnerTests.swift
  PiHealthTests.swift
  AgentRunnerTests.swift
  PatchCollectorTests.swift
  RunApplierTests.swift
  RunManifestTests.swift         # MODIFIED for touchedFiles
  FlowFakeAgentTests.swift       # end-to-end engine flow
```

---

### Task 1: ProcessRunner

**Files:**
- Create: `Sources/DetDocCore/Support/ProcessRunner.swift`
- Test: `Tests/DetDocCoreTests/ProcessRunnerTests.swift`

**Interfaces:**
- Produces:
  - `struct ProcessResult: Sendable { let status: Int32; let stdout: Data; let stderr: Data; var stdoutString: String; var stderrString: String }`
  - `enum ProcessRunner { static func run(_ executable: String, _ arguments: [String], cwd: URL, stdin: String? = nil) async throws -> ProcessResult }`
  - Spawns `/usr/bin/env <executable> <arguments...>` in `cwd`, optionally writing `stdin`, capturing stdout/stderr concurrently. Spawn failure throws `DetDocError("PROCESS_SPAWN_FAILED", ...)`.

- [ ] **Step 1: Write the failing test**

`Tests/DetDocCoreTests/ProcessRunnerTests.swift`
```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func processRunnerCapturesStdoutAndStatus() async throws {
    let result = try await ProcessRunner.run("/bin/sh", ["-c", "printf hello"], cwd: FileManager.default.temporaryDirectory)
    #expect(result.status == 0)
    #expect(result.stdoutString == "hello")
}

@Test func processRunnerCapturesNonZeroStatusAndStderr() async throws {
    let result = try await ProcessRunner.run("/bin/sh", ["-c", "printf oops 1>&2; exit 3"], cwd: FileManager.default.temporaryDirectory)
    #expect(result.status == 3)
    #expect(result.stderrString == "oops")
}

@Test func processRunnerWritesStdin() async throws {
    let result = try await ProcessRunner.run("/bin/sh", ["-c", "cat"], cwd: FileManager.default.temporaryDirectory, stdin: "piped")
    #expect(result.stdoutString == "piped")
}
```

- [ ] **Step 2: Run to verify it fails** — `cd swift/DetDocCore && swift test` → build error (`ProcessRunner` not found).

- [ ] **Step 3: Implement**

`Sources/DetDocCore/Support/ProcessRunner.swift`
```swift
import Foundation

public struct ProcessResult: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: Data
    public var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrString: String { String(decoding: stderr, as: UTF8.self) }
}

/// Mutable box used to collect pipe data off concurrent reader queues.
private final class DataBox: @unchecked Sendable {
    var value = Data()
}

public enum ProcessRunner {
    public static func run(
        _ executable: String,
        _ arguments: [String],
        cwd: URL,
        stdin: String? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.currentDirectoryURL = cwd

        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        if stdin != nil { process.standardInput = inPipe }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessResult, Error>) in
            let outBox = DataBox()
            let errBox = DataBox()
            let group = DispatchGroup()
            let queue = DispatchQueue(label: "DetDocCore.ProcessRunner", attributes: .concurrent)
            queue.async(group: group) { outBox.value = outPipe.fileHandleForReading.readDataToEndOfFile() }
            queue.async(group: group) { errBox.value = errPipe.fileHandleForReading.readDataToEndOfFile() }

            process.terminationHandler = { proc in
                group.wait()
                continuation.resume(returning: ProcessResult(status: proc.terminationStatus, stdout: outBox.value, stderr: errBox.value))
            }

            do {
                try process.run()
                if let stdin {
                    let handle = inPipe.fileHandleForWriting
                    handle.write(Data(stdin.utf8))
                    try? handle.close()
                }
            } catch {
                continuation.resume(throwing: DetDocError("PROCESS_SPAWN_FAILED", "\(executable): \(error)"))
            }
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test` → all green (3 new tests).
- [ ] **Step 5: Commit** — `git add Sources/DetDocCore/Support/ProcessRunner.swift Tests/DetDocCoreTests/ProcessRunnerTests.swift && git commit -m "feat(core): add async ProcessRunner subprocess helper"`

---

### Task 2: GitRepository + GitFixture test helper

**Files:**
- Create: `Sources/DetDocCore/Services/GitRepository.swift`
- Create: `Tests/DetDocCoreTests/Support/GitFixture.swift`
- Test: `Tests/DetDocCoreTests/GitRepositoryTests.swift`

**Interfaces:**
- Consumes: `ProcessRunner` (T1), `DetDocError`.
- Produces:
  - `struct GitStatusEntry: Sendable, Equatable { let status: String; let path: String }`
  - `struct GitRepository: Sendable { let cwd: URL; init(_ cwd: URL) }`
  - `func git(_ args: [String], stdin: String? = nil) async throws -> String`
  - `func headCommit() async throws -> String`
  - `func statusPorcelain() async throws -> [GitStatusEntry]`
  - `func applyPatch(_ patch: String) async throws`
  - `func diffPaths(_ paths: [String]) async throws -> String`
  - `func changedFilesFromPatch(_ patch: String) async throws -> [String]`
  - `func fileSha256(_ relativePath: String) -> String?`
  - Test helper `GitFixture` with `let root: URL` and `init() async throws` that `git init`s a temp repo with user config, plus `func commitAll(_ message: String) async throws` and `func write(_ path: String, _ contents: String) throws`.

- [ ] **Step 1: Write the failing test**

`Tests/DetDocCoreTests/Support/GitFixture.swift`
```swift
import Foundation
@testable import DetDocCore

/// A throwaway git repository for tests.
final class GitFixture {
    let root: URL
    let repo: GitRepository

    init() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("detdoc-git-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        repo = GitRepository(root)
        _ = try await repo.git(["init", "-q", "-b", "main"])
        _ = try await repo.git(["config", "user.email", "test@detdoc.local"])
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

    func cleanup() { try? FileManager.default.removeItem(at: root) }
    deinit { cleanup() }
}
```

`Tests/DetDocCoreTests/GitRepositoryTests.swift`
```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func headCommitReturnsCommitSha() async throws {
    let fx = try await GitFixture()
    try fx.write("README.md", "hi\n")
    try await fx.commitAll("init")
    let head = try await fx.repo.headCommit()
    #expect(head.count == 40)
}

@Test func statusPorcelainReportsDirtyFiles() async throws {
    let fx = try await GitFixture()
    try fx.write("README.md", "hi\n")
    try await fx.commitAll("init")
    try fx.write("docs/idea.md", "new\n")  // untracked
    let dirty = try await fx.repo.statusPorcelain()
    #expect(dirty.contains { $0.path == "docs/idea.md" && $0.status == "??" })
}

@Test func applyPatchAndChangedFilesRoundTrip() async throws {
    let fx = try await GitFixture()
    try fx.write("src/a.txt", "one\n")
    try await fx.commitAll("init")
    try fx.write("src/a.txt", "two\n")
    let patch = try await fx.repo.diffPaths(["src/a.txt"])
    #expect(try await fx.repo.changedFilesFromPatch(patch) == ["src/a.txt"])
    // revert working tree, then re-apply the patch
    _ = try await fx.repo.git(["checkout", "--", "src/a.txt"])
    try await fx.repo.applyPatch(patch)
    let restored = try String(contentsOf: fx.root.appendingPathComponent("src/a.txt"), encoding: .utf8)
    #expect(restored == "two\n")
}

@Test func fileSha256IsNilForMissingFile() async throws {
    let fx = try await GitFixture()
    #expect(fx.repo.fileSha256("nope.txt") == nil)
}

@Test func failingGitCommandThrowsCommandFailed() async throws {
    let fx = try await GitFixture()
    await #expect(throws: DetDocError.self) {
        _ = try await fx.repo.git(["rev-parse", "does-not-exist"])
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test` → build error (`GitRepository` not found).

- [ ] **Step 3: Implement**

`Sources/DetDocCore/Services/GitRepository.swift`
```swift
import Foundation
import CryptoKit

public struct GitStatusEntry: Sendable, Equatable {
    public let status: String
    public let path: String
    public init(status: String, path: String) {
        self.status = status
        self.path = path
    }
}

public struct GitRepository: Sendable {
    public let cwd: URL
    public init(_ cwd: URL) { self.cwd = cwd }

    @discardableResult
    public func git(_ args: [String], stdin: String? = nil) async throws -> String {
        let result: ProcessResult
        do {
            result = try await ProcessRunner.run("git", ["-c", "core.quotepath=false"] + args, cwd: cwd, stdin: stdin)
        } catch {
            throw DetDocError("GIT_SPAWN_FAILED", "\(error)")
        }
        guard result.status == 0 else {
            throw DetDocError("GIT_COMMAND_FAILED", "git \(args.joined(separator: " ")): \(result.stderrString)")
        }
        return result.stdoutString
    }

    public func headCommit() async throws -> String {
        try await git(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func statusPorcelain() async throws -> [GitStatusEntry] {
        let output = try await git(["status", "--porcelain", "-uall"])
        return output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let text = String(line)
            guard text.count >= 4 else { return nil }
            let status = String(text.prefix(2))
            let path = String(text.dropFirst(3))
            return GitStatusEntry(status: status, path: path)
        }
    }

    public func applyPatch(_ patch: String) async throws {
        let result: ProcessResult
        do {
            result = try await ProcessRunner.run(
                "git", ["-c", "core.quotepath=false", "apply", "--binary", "--whitespace=nowarn", "-"],
                cwd: cwd, stdin: patch
            )
        } catch {
            throw DetDocError("GIT_APPLY_SPAWN_FAILED", "\(error)")
        }
        guard result.status == 0 else {
            throw DetDocError("GIT_APPLY_FAILED", result.stderrString)
        }
    }

    public func diffPaths(_ paths: [String]) async throws -> String {
        guard !paths.isEmpty else { return "" }
        return try await git(["diff", "--no-color", "--no-ext-diff", "--binary", "--"] + paths)
    }

    public func changedFilesFromPatch(_ patch: String) async throws -> [String] {
        let output = try await git(["apply", "--numstat", "-"], stdin: patch)
        return output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            line.split(separator: "\t").last.map(String.init)
        }
    }

    public func fileSha256(_ relativePath: String) -> String? {
        guard let data = try? Data(contentsOf: cwd.appendingPathComponent(relativePath)) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test` → all green.
- [ ] **Step 5: Commit** — `git add Sources/DetDocCore/Services/GitRepository.swift Tests/DetDocCoreTests/Support/GitFixture.swift Tests/DetDocCoreTests/GitRepositoryTests.swift && git commit -m "feat(core): add GitRepository subprocess wrapper + GitFixture"`

---

### Task 3: DocsService

**Files:**
- Create: `Sources/DetDocCore/Services/DocsService.swift`
- Test: `Tests/DetDocCoreTests/DocsServiceTests.swift`

**Interfaces:**
- Consumes: `DetDocConfig`, `PathPolicy`, `DocFile`, `DetDocError`.
- Produces:
  - `struct DocsService: Sendable { let root: URL; let config: DetDocConfig; init(root: URL, config: DetDocConfig) }`
  - `func list() -> [DocFile]` — walk `<root>/docs`, include `.md` files whose repo-relative path `isDoc`, sorted by path; `title` = filename without extension.
  - `func read(_ path: String) throws -> String`
  - `func write(_ path: String, _ markdown: String) throws`
  - `func create(_ path: String, _ markdown: String) throws` — fails `DOC_ALREADY_EXISTS` if present
  - `func rename(_ from: String, to: String) throws`
  - `func delete(_ path: String) throws`

- [ ] **Step 1: Write the failing test**

`Tests/DetDocCoreTests/DocsServiceTests.swift`
```swift
import Foundation
import Testing
@testable import DetDocCore

private func docsService() -> (TempDir, DocsService) {
    let tmp = TempDir()
    return (tmp, DocsService(root: tmp.url, config: .default))
}

@Test func listReturnsOnlyMarkdownDocsSorted() throws {
    let (tmp, svc) = docsService()
    try FileManager.default.createDirectory(at: tmp.url.appendingPathComponent("docs/sub"), withIntermediateDirectories: true)
    try "a".write(to: tmp.url.appendingPathComponent("docs/b.md"), atomically: true, encoding: .utf8)
    try "a".write(to: tmp.url.appendingPathComponent("docs/sub/a.md"), atomically: true, encoding: .utf8)
    try "a".write(to: tmp.url.appendingPathComponent("docs/notes.txt"), atomically: true, encoding: .utf8)
    let docs = svc.list()
    #expect(docs.map(\.path) == ["docs/b.md", "docs/sub/a.md"])
    #expect(docs.first?.title == "b")
}

@Test func writeReadCreateRenameDelete() throws {
    let (_, svc) = docsService()
    try svc.create("docs/x.md", "# X\n")
    #expect(try svc.read("docs/x.md") == "# X\n")
    #expect(throws: DetDocError.self) { try svc.create("docs/x.md", "dup") }
    try svc.write("docs/x.md", "# X2\n")
    #expect(try svc.read("docs/x.md") == "# X2\n")
    try svc.rename("docs/x.md", to: "docs/y.md")
    #expect(svc.list().map(\.path) == ["docs/y.md"])
    try svc.delete("docs/y.md")
    #expect(svc.list().isEmpty)
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test` → build error (`DocsService` not found).

- [ ] **Step 3: Implement**

`Sources/DetDocCore/Services/DocsService.swift`
```swift
import Foundation

public struct DocsService: Sendable {
    private let root: URL
    private let config: DetDocConfig
    private var policy: PathPolicy { PathPolicy(config: config) }

    public init(root: URL, config: DetDocConfig) {
        self.root = root
        self.config = config
    }

    public func list() -> [DocFile] {
        let docsDir = root.appendingPathComponent("docs")
        guard let enumerator = FileManager.default.enumerator(at: docsDir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        var docs: [DocFile] = []
        for case let url as URL in enumerator where url.pathExtension == "md" {
            let relative = relativePath(url)
            guard policy.isDoc(relative) else { continue }
            docs.append(DocFile(path: relative, title: url.deletingPathExtension().lastPathComponent))
        }
        return docs.sorted { $0.path < $1.path }
    }

    public func read(_ path: String) throws -> String {
        do {
            return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        } catch {
            throw DetDocError("DOC_READ_FAILED", "\(path): \(error)")
        }
    }

    public func write(_ path: String, _ markdown: String) throws {
        let url = root.appendingPathComponent(path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try markdown.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw DetDocError("DOC_WRITE_FAILED", "\(path): \(error)")
        }
    }

    public func create(_ path: String, _ markdown: String) throws {
        if FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) {
            throw DetDocError("DOC_ALREADY_EXISTS", path)
        }
        try write(path, markdown)
    }

    public func rename(_ from: String, to: String) throws {
        let toURL = root.appendingPathComponent(to)
        do {
            try FileManager.default.createDirectory(at: toURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: root.appendingPathComponent(from), to: toURL)
        } catch {
            throw DetDocError("DOC_RENAME_FAILED", "\(from) -> \(to): \(error)")
        }
    }

    public func delete(_ path: String) throws {
        do {
            try FileManager.default.removeItem(at: root.appendingPathComponent(path))
        } catch {
            throw DetDocError("DOC_DELETE_FAILED", "\(path): \(error)")
        }
    }

    private func relativePath(_ url: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        return urlComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test` → all green.
- [ ] **Step 5: Commit** — `git add Sources/DetDocCore/Services/DocsService.swift Tests/DetDocCoreTests/DocsServiceTests.swift && git commit -m "feat(core): add DocsService for markdown CRUD"`

---

### Task 4: ValidationRunner

**Files:**
- Create: `Sources/DetDocCore/Services/ValidationRunner.swift`
- Test: `Tests/DetDocCoreTests/ValidationRunnerTests.swift`

**Interfaces:**
- Consumes: `ProcessRunner` (T1), `DetDocConfig`, `ValidationCommand`, `DetDocError`.
- Produces:
  - `struct ValidationRunner: Sendable { init() }`
  - `func run(commands: [ValidationCommand], cwd: URL) async throws -> String` — for each command append `"\n# {name}\n$ {run}\n"`, run via `/bin/sh -c`, append stdout+stderr; on non-zero status append output and throw `VALIDATION_FAILED` with `"Validation command failed: {name}\n{log}"`. Returns the log with leading whitespace trimmed.

- [ ] **Step 1: Write the failing test**

`Tests/DetDocCoreTests/ValidationRunnerTests.swift`
```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func validationRunnerConcatenatesCommandLogs() async throws {
    let log = try await ValidationRunner().run(
        commands: [ValidationCommand(name: "echo", run: "printf done")],
        cwd: FileManager.default.temporaryDirectory
    )
    #expect(log.contains("# echo"))
    #expect(log.contains("done"))
}

@Test func validationRunnerThrowsValidationFailedOnNonZeroExit() async throws {
    await #expect {
        _ = try await ValidationRunner().run(
            commands: [ValidationCommand(name: "boom", run: "exit 1")],
            cwd: FileManager.default.temporaryDirectory
        )
    } throws: { ($0 as? DetDocError)?.code == "VALIDATION_FAILED" }
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test` → build error (`ValidationRunner` not found).

- [ ] **Step 3: Implement**

`Sources/DetDocCore/Services/ValidationRunner.swift`
```swift
import Foundation

public struct ValidationRunner: Sendable {
    public init() {}

    public func run(commands: [ValidationCommand], cwd: URL) async throws -> String {
        var log = ""
        for command in commands {
            log += "\n# \(command.name)\n$ \(command.run)\n"
            let result = try await ProcessRunner.run("/bin/sh", ["-c", command.run], cwd: cwd)
            log += result.stdoutString
            log += result.stderrString
            if result.status != 0 {
                throw DetDocError("VALIDATION_FAILED", "Validation command failed: \(command.name)\n\(log)")
            }
        }
        return String(log.drop { $0 == "\n" || $0 == " " || $0 == "\t" })
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test` → all green.
- [ ] **Step 5: Commit** — `git add Sources/DetDocCore/Services/ValidationRunner.swift Tests/DetDocCoreTests/ValidationRunnerTests.swift && git commit -m "feat(core): add ValidationRunner for config validation commands"`

---

### Task 5: AgentRunner protocol + FakeAgentRunner

**Files:**
- Create: `Sources/DetDocCore/Agent/AgentRunner.swift`
- Create: `Sources/DetDocCore/Agent/FakeAgentRunner.swift`
- Test: `Tests/DetDocCoreTests/AgentRunnerTests.swift`

**Interfaces:**
- Consumes: `RunMode`, `ProposedPlan`, `DetDocConfig`, `TokenUsage` (Plan 1).
- Produces:
  - `enum AgentImplementationProgress: Sendable { case edit(path: String); case write(path: String); case bash(command: String) }`
  - `struct PlanRequest: Sendable { mode, input, config, cwd: URL }`
  - `struct ImplementRequest: Sendable { mode, input, config, cwd: URL, approvedPlan, approvedTargets, progress: (@Sendable (AgentImplementationProgress) -> Void)? }`
  - `struct RepairRequest: Sendable { ...ImplementRequest fields..., validationLog: String, attempt: Int }`
  - `struct AgentPlanResult: Sendable { plan: ProposedPlan; usage: TokenUsage }`
  - `struct AgentRunResult: Sendable { usage: TokenUsage }`
  - `protocol AgentRunner: Sendable { func plan(_:) async throws -> AgentPlanResult; func implement(_:) async throws -> AgentRunResult; func repairValidation(_:) async throws -> AgentRunResult }` with a default `repairValidation` returning `AgentRunResult(usage: .init())` and `var supportsRepair: Bool { get }` defaulting `false`.
  - `extension TokenUsage { static func + }` (sum) — for accumulation.
  - `struct FakeAgentRunner: AgentRunner` — `init(target: String, content: String)`; `plan` returns a single-change plan (`doc-diff:...` for run, `intent:fix` for fix) targeting `target`; `implement`/`repairValidation` write `content` to `cwd/target`.

- [ ] **Step 1: Write the failing test**

`Tests/DetDocCoreTests/AgentRunnerTests.swift`
```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func fakeAgentPlanTargetsFileWithModeAppropriateReason() async throws {
    let agent = FakeAgentRunner(target: "src/app.swift", content: "let x = 2\n")
    let run = try await agent.plan(PlanRequest(mode: .run, input: "diff", config: .default, cwd: FileManager.default.temporaryDirectory))
    #expect(run.plan.changes.first?.targetFiles == ["src/app.swift"])
    #expect(run.plan.changes.first?.reason.hasPrefix("doc-diff:") == true)
    let fix = try await agent.plan(PlanRequest(mode: .fix, input: "msg", config: .default, cwd: FileManager.default.temporaryDirectory))
    #expect(fix.plan.changes.first?.reason == "intent:fix")
}

@Test func fakeAgentImplementWritesContent() async throws {
    let tmp = TempDir()
    let agent = FakeAgentRunner(target: "src/app.swift", content: "let x = 2\n")
    _ = try await agent.implement(ImplementRequest(mode: .run, input: "diff", config: .default, cwd: tmp.url, approvedPlan: ProposedPlan(summary: "s", changes: [], risk: "low"), approvedTargets: ["src/app.swift"], progress: nil))
    let written = try String(contentsOf: tmp.url.appendingPathComponent("src/app.swift"), encoding: .utf8)
    #expect(written == "let x = 2\n")
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test` → build error.

- [ ] **Step 3: Implement**

`Sources/DetDocCore/Agent/AgentRunner.swift`
```swift
public enum AgentImplementationProgress: Sendable {
    case edit(path: String)
    case write(path: String)
    case bash(command: String)
}

public struct PlanRequest: Sendable {
    public let mode: RunMode
    public let input: String
    public let config: DetDocConfig
    public let cwd: URL
    public init(mode: RunMode, input: String, config: DetDocConfig, cwd: URL) {
        self.mode = mode; self.input = input; self.config = config; self.cwd = cwd
    }
}

public struct ImplementRequest: Sendable {
    public let mode: RunMode
    public let input: String
    public let config: DetDocConfig
    public let cwd: URL
    public let approvedPlan: ProposedPlan
    public let approvedTargets: [String]
    public let progress: (@Sendable (AgentImplementationProgress) -> Void)?
    public init(mode: RunMode, input: String, config: DetDocConfig, cwd: URL, approvedPlan: ProposedPlan, approvedTargets: [String], progress: (@Sendable (AgentImplementationProgress) -> Void)?) {
        self.mode = mode; self.input = input; self.config = config; self.cwd = cwd
        self.approvedPlan = approvedPlan; self.approvedTargets = approvedTargets; self.progress = progress
    }
}

public struct RepairRequest: Sendable {
    public let base: ImplementRequest
    public let validationLog: String
    public let attempt: Int
    public init(base: ImplementRequest, validationLog: String, attempt: Int) {
        self.base = base; self.validationLog = validationLog; self.attempt = attempt
    }
}

public struct AgentPlanResult: Sendable {
    public let plan: ProposedPlan
    public let usage: TokenUsage
    public init(plan: ProposedPlan, usage: TokenUsage = TokenUsage()) {
        self.plan = plan; self.usage = usage
    }
}

public struct AgentRunResult: Sendable {
    public let usage: TokenUsage
    public init(usage: TokenUsage = TokenUsage()) { self.usage = usage }
}

public protocol AgentRunner: Sendable {
    var supportsRepair: Bool { get }
    func plan(_ request: PlanRequest) async throws -> AgentPlanResult
    func implement(_ request: ImplementRequest) async throws -> AgentRunResult
    func repairValidation(_ request: RepairRequest) async throws -> AgentRunResult
}

public extension AgentRunner {
    var supportsRepair: Bool { false }
    func repairValidation(_ request: RepairRequest) async throws -> AgentRunResult { AgentRunResult() }
}

public extension TokenUsage {
    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            total: lhs.total + rhs.total
        )
    }
}
```

`Sources/DetDocCore/Agent/FakeAgentRunner.swift`
```swift
import Foundation

public struct FakeAgentRunner: AgentRunner {
    private let target: String
    private let content: String

    public init(target: String, content: String) {
        self.target = target
        self.content = content
    }

    public var supportsRepair: Bool { true }

    public func plan(_ request: PlanRequest) async throws -> AgentPlanResult {
        let reason = request.mode == .run ? "doc-diff:docs/technical-spec.md:L1-L2" : "intent:fix"
        let change = PlanChange(reason: reason, targetFiles: [target], kind: "modify", rationale: "Fake agent writes target")
        return AgentPlanResult(plan: ProposedPlan(summary: "Fake plan", changes: [change], risk: "low"))
    }

    public func implement(_ request: ImplementRequest) async throws -> AgentRunResult {
        try writeTarget(into: request.cwd)
        request.progress?(.write(path: target))
        return AgentRunResult()
    }

    public func repairValidation(_ request: RepairRequest) async throws -> AgentRunResult {
        try writeTarget(into: request.base.cwd)
        return AgentRunResult()
    }

    private func writeTarget(into cwd: URL) throws {
        let url = cwd.appendingPathComponent(target)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test` → all green.
- [ ] **Step 5: Commit** — `git add Sources/DetDocCore/Agent Tests/DetDocCoreTests/AgentRunnerTests.swift && git commit -m "feat(core): add AgentRunner protocol and FakeAgentRunner"`

---

### Task 6: PiHealth

**Files:**
- Create: `Sources/DetDocCore/Services/PiHealth.swift`
- Test: `Tests/DetDocCoreTests/PiHealthTests.swift`

**Interfaces:**
- Consumes: `ProcessRunner` (T1).
- Produces:
  - `enum PiHealth { static func isAvailable() async -> Bool }` — runs `pi --version`; returns true iff status 0. Never throws.

- [ ] **Step 1: Write the failing test**

`Tests/DetDocCoreTests/PiHealthTests.swift`
```swift
import Testing
@testable import DetDocCore

@Test func piHealthReturnsBoolWithoutThrowing() async {
    // pi is installed in this environment, but the contract is "never throws".
    let available = await PiHealth.isAvailable()
    #expect(available == true || available == false)
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test` → build error (`PiHealth` not found).

- [ ] **Step 3: Implement**

`Sources/DetDocCore/Services/PiHealth.swift`
```swift
import Foundation

public enum PiHealth {
    public static func isAvailable() async -> Bool {
        guard let result = try? await ProcessRunner.run("pi", ["--version"], cwd: FileManager.default.temporaryDirectory) else {
            return false
        }
        return result.status == 0
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test` → all green.
- [ ] **Step 5: Commit** — `git add Sources/DetDocCore/Services/PiHealth.swift Tests/DetDocCoreTests/PiHealthTests.swift && git commit -m "feat(core): add PiHealth availability probe"`

---

### Task 7: RunManifest refactor (touchedFiles) + factory + RunEvent types

**Files:**
- Modify: `Sources/DetDocCore/Models/RunManifest.swift`
- Modify: `Tests/DetDocCoreTests/RunManifestTests.swift`
- Create: `Sources/DetDocCore/Engine/RunEvent.swift`
- Test: `Tests/DetDocCoreTests/RunEventTests.swift`

**Interfaces:**
- Consumes: `RunMode`, `RunID`, `ProposedPlan`, `RunFlowResult`, `DetDocError`.
- Produces:
  - `struct TouchedFile: Codable, Sendable, Equatable { var path: String; var before: String?; var after: String? }`
  - `RunManifest` with `runId, mode, baseCommit, approvedTargets, touchedFiles: [TouchedFile]` (replaces `preImageHashes`); `approvedTargets`/`touchedFiles` default to `[]` when absent on decode.
  - `static func RunManifest.initial(mode: RunMode, baseCommit: String, now: Date = Date(), uuid: UUID = UUID()) -> RunManifest`
  - `enum RunPhase: String, Sendable` with the cases listed in Reference Parity Facts.
  - `struct PatchReview: Sendable { let runId: String; let changedFiles: [String]; let patch: String; let worktreePath: String }`
  - `enum RunEvent: Sendable { case progress(phase: RunPhase, message: String); case log(String); case planReady(ProposedPlan); case patchReady(PatchReview); case error(DetDocError); case complete(RunFlowResult) }`
  - `enum PlanDecision: Sendable { case approve, reject }`
  - `enum ApplyDecision: Sendable { case apply, discard }`

- [ ] **Step 1: Update the RunManifest test for touchedFiles**

Replace `Tests/DetDocCoreTests/RunManifestTests.swift` with:
```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func manifestDecodesLegacyWithoutOptionalFields() throws {
    let json = """
    { "runId": "20260620T101112Z-run-1a2b3c4d", "mode": "run", "baseCommit": "abc123" }
    """
    let manifest = try JSONDecoder().decode(RunManifest.self, from: Data(json.utf8))
    #expect(manifest.approvedTargets == [])
    #expect(manifest.touchedFiles == [])
}

@Test func manifestRoundTripsWithTouchedFiles() throws {
    var manifest = RunManifest.initial(mode: .fix, baseCommit: "c0ffee")
    manifest.approvedTargets = ["src/a.swift"]
    manifest.touchedFiles = [TouchedFile(path: "src/a.swift", before: "h1", after: "h2")]
    let data = try JSONEncoder().encode(manifest)
    let decoded = try JSONDecoder().decode(RunManifest.self, from: data)
    #expect(decoded == manifest)
}

@Test func manifestInitialHasFreshRunIdAndEmptyCollections() {
    let manifest = RunManifest.initial(mode: .run, baseCommit: "base")
    #expect(manifest.mode == .run)
    #expect(manifest.baseCommit == "base")
    #expect(manifest.approvedTargets.isEmpty)
    #expect(manifest.touchedFiles.isEmpty)
    #expect(manifest.runId.range(of: #"^\d{8}T\d{6}Z-run-[0-9a-f]{8}$"#, options: .regularExpression) != nil)
}
```

`Tests/DetDocCoreTests/RunEventTests.swift`
```swift
@testable import DetDocCore
import Testing

@Test func runPhaseHasStableRawValues() {
    #expect(RunPhase.plan.rawValue == "plan")
    #expect(RunPhase.approveApply.rawValue == "approve_apply")
    #expect(RunPhase.done.rawValue == "done")
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test` → build error (`preImageHashes` gone / `TouchedFile`, `RunPhase` not found).

- [ ] **Step 3: Implement**

Replace `Sources/DetDocCore/Models/RunManifest.swift` with:
```swift
import Foundation

public struct TouchedFile: Codable, Sendable, Equatable {
    public var path: String
    public var before: String?
    public var after: String?
    public init(path: String, before: String?, after: String?) {
        self.path = path; self.before = before; self.after = after
    }
}

public struct RunManifest: Codable, Sendable, Equatable {
    public var runId: String
    public var mode: RunMode
    public var baseCommit: String
    public var approvedTargets: [String]
    public var touchedFiles: [TouchedFile]

    public init(runId: String, mode: RunMode, baseCommit: String, approvedTargets: [String] = [], touchedFiles: [TouchedFile] = []) {
        self.runId = runId; self.mode = mode; self.baseCommit = baseCommit
        self.approvedTargets = approvedTargets; self.touchedFiles = touchedFiles
    }

    enum CodingKeys: String, CodingKey { case runId, mode, baseCommit, approvedTargets, touchedFiles }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.runId = try c.decode(String.self, forKey: .runId)
        self.mode = try c.decode(RunMode.self, forKey: .mode)
        self.baseCommit = try c.decode(String.self, forKey: .baseCommit)
        self.approvedTargets = try c.decodeIfPresent([String].self, forKey: .approvedTargets) ?? []
        self.touchedFiles = try c.decodeIfPresent([TouchedFile].self, forKey: .touchedFiles) ?? []
    }

    public static func initial(mode: RunMode, baseCommit: String, now: Date = Date(), uuid: UUID = UUID()) -> RunManifest {
        RunManifest(runId: RunID.create(mode: mode, now: now, uuid: uuid), mode: mode, baseCommit: baseCommit)
    }
}
```

`Sources/DetDocCore/Engine/RunEvent.swift`
```swift
public enum RunPhase: String, Sendable {
    case loadConfig = "load_config"
    case collectInput = "collect_input"
    case createRun = "create_run"
    case createWorktree = "create_worktree"
    case applyInputToWorktree = "apply_input_to_worktree"
    case plan
    case approvePlan = "approve_plan"
    case implement
    case collectPatch = "collect_patch"
    case validatePatch = "validate_patch"
    case repairValidation = "repair_validation"
    case approveApply = "approve_apply"
    case applyPatch = "apply_patch"
    case postApplyValidation = "post_apply_validation"
    case cleanupRun = "cleanup_run"
    case commit
    case cleanupWorktree = "cleanup_worktree"
    case done
}

public struct PatchReview: Sendable {
    public let runId: String
    public let changedFiles: [String]
    public let patch: String
    public let worktreePath: String
    public init(runId: String, changedFiles: [String], patch: String, worktreePath: String) {
        self.runId = runId; self.changedFiles = changedFiles; self.patch = patch; self.worktreePath = worktreePath
    }
}

public enum RunEvent: Sendable {
    case progress(phase: RunPhase, message: String)
    case log(String)
    case planReady(ProposedPlan)
    case patchReady(PatchReview)
    case error(DetDocError)
    case complete(RunFlowResult)
}

public enum PlanDecision: Sendable { case approve, reject }
public enum ApplyDecision: Sendable { case apply, discard }
```

- [ ] **Step 4: Run to verify it passes** — `swift test` → all green (ArtifactStore tests still pass; they never referenced `preImageHashes`).
- [ ] **Step 5: Commit** — `git add Sources/DetDocCore/Models/RunManifest.swift Sources/DetDocCore/Engine/RunEvent.swift Tests/DetDocCoreTests/RunManifestTests.swift Tests/DetDocCoreTests/RunEventTests.swift && git commit -m "feat(core): manifest touchedFiles + factory, RunEvent/phase/decision types"`

---

### Task 8: WorktreeManager

**Files:**
- Create: `Sources/DetDocCore/Services/WorktreeManager.swift`
- Test: `Tests/DetDocCoreTests/WorktreeManagerTests.swift`

**Interfaces:**
- Consumes: `GitRepository` (T2), `DetDocError`.
- Produces:
  - `struct WorktreeHandle: Sendable { let path: URL; let branchName: String; var repo: GitRepository { GitRepository(path) } }`
  - `struct WorktreeManager: Sendable { init() }`
  - `func createFromHead(_ repo: GitRepository, runId: String) async throws -> WorktreeHandle` — mkdir `<root>/.worktrees`; base = head; `git worktree add -b <runId> <path> <base>`.
  - `func cleanup(_ repo: GitRepository, _ handle: WorktreeHandle) async throws` — if path exists `worktree remove --force <path>`; `branch -D <branch>`.

- [ ] **Step 1: Write the failing test**

`Tests/DetDocCoreTests/WorktreeManagerTests.swift`
```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func createAndCleanupWorktree() async throws {
    let fx = try await GitFixture()
    try fx.write("README.md", "hi\n")
    try await fx.commitAll("init")

    let handle = try await WorktreeManager().createFromHead(fx.repo, runId: "20260620T101112Z-run-1a2b3c4d")
    #expect(FileManager.default.fileExists(atPath: handle.path.appendingPathComponent("README.md").path))

    try await WorktreeManager().cleanup(fx.repo, handle)
    #expect(!FileManager.default.fileExists(atPath: handle.path.path))
    let branches = try await fx.repo.git(["branch", "--list", handle.branchName])
    #expect(branches.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test` → build error (`WorktreeManager` not found).

- [ ] **Step 3: Implement**

`Sources/DetDocCore/Services/WorktreeManager.swift`
```swift
import Foundation

public struct WorktreeHandle: Sendable {
    public let path: URL
    public let branchName: String
    public var repo: GitRepository { GitRepository(path) }
    public init(path: URL, branchName: String) {
        self.path = path; self.branchName = branchName
    }
}

public struct WorktreeManager: Sendable {
    public init() {}

    public func createFromHead(_ repo: GitRepository, runId: String) async throws -> WorktreeHandle {
        let worktreesDir = repo.cwd.appendingPathComponent(".worktrees")
        do {
            try FileManager.default.createDirectory(at: worktreesDir, withIntermediateDirectories: true)
        } catch {
            throw DetDocError("WORKTREE_DIR_FAILED", "\(error)")
        }
        let path = worktreesDir.appendingPathComponent(runId)
        let base = try await repo.headCommit()
        _ = try await repo.git(["worktree", "add", "-b", runId, path.path, base])
        return WorktreeHandle(path: path, branchName: runId)
    }

    public func cleanup(_ repo: GitRepository, _ handle: WorktreeHandle) async throws {
        if FileManager.default.fileExists(atPath: handle.path.path) {
            _ = try await repo.git(["worktree", "remove", "--force", handle.path.path])
        }
        _ = try await repo.git(["branch", "-D", handle.branchName])
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test` → all green.
- [ ] **Step 5: Commit** — `git add Sources/DetDocCore/Services/WorktreeManager.swift Tests/DetDocCoreTests/WorktreeManagerTests.swift && git commit -m "feat(core): add WorktreeManager run-worktree lifecycle"`

---

### Task 9: DirtyPolicy + DocDiff

**Files:**
- Create: `Sources/DetDocCore/Services/DirtyPolicy.swift`
- Create: `Sources/DetDocCore/Services/DocDiff.swift`
- Test: `Tests/DetDocCoreTests/DirtyPolicyTests.swift`
- Test: `Tests/DetDocCoreTests/DocDiffTests.swift`

**Interfaces:**
- Consumes: `GitRepository` (T2), `PathPolicy` (Plan 1), `DetDocConfig`, `GitStatusEntry`, `DetDocError`.
- Produces:
  - `enum DirtyPolicy { static func nonDocOffenders(_ entries: [GitStatusEntry], config: DetDocConfig) -> [GitStatusEntry]; static func assertClean(_ entries: [GitStatusEntry], config: DetDocConfig, mode: RunMode) throws }` — offenders = entries whose path is not `.detdoc/`-prefixed, not `.gitignore`, and not `isDoc`. Non-empty → `DIRTY_NON_DOC_CHANGES` (offending paths joined `, `).
  - `enum DocDiff { static func normalized(_ repo: GitRepository, config: DetDocConfig) async throws -> String }` — assertClean(run); docPaths = `isDoc` entries; empty → `NO_DOC_CHANGES`; `git add -N -- <docPaths>` (ignore failure); return `repo.diffPaths(docPaths)`.

- [ ] **Step 1: Write the failing test**

`Tests/DetDocCoreTests/DirtyPolicyTests.swift`
```swift
import Testing
@testable import DetDocCore

@Test func nonDocOffendersExcludeDocsDetdocAndGitignore() {
    let entries = [
        GitStatusEntry(status: " M", path: "docs/idea.md"),
        GitStatusEntry(status: " M", path: ".detdoc/config.yml"),
        GitStatusEntry(status: " M", path: ".gitignore"),
        GitStatusEntry(status: " M", path: "src/app.swift"),
    ]
    let offenders = DirtyPolicy.nonDocOffenders(entries, config: .default)
    #expect(offenders.map(\.path) == ["src/app.swift"])
}

@Test func assertCleanThrowsOnNonDocChanges() {
    let entries = [GitStatusEntry(status: " M", path: "src/app.swift")]
    #expect { try DirtyPolicy.assertClean(entries, config: .default, mode: .fix) }
        throws: { ($0 as? DetDocError)?.code == "DIRTY_NON_DOC_CHANGES" }
}
```

`Tests/DetDocCoreTests/DocDiffTests.swift`
```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func normalizedDocDiffReturnsDocChangesAndIncludesUntracked() async throws {
    let fx = try await GitFixture()
    try fx.write("docs/idea.md", "old\n")
    try await fx.commitAll("init")
    try fx.write("docs/idea.md", "new line\n")       // tracked-modified doc
    try fx.write("docs/extra.md", "brand new\n")     // untracked doc
    let diff = try await DocDiff.normalized(fx.repo, config: .default)
    #expect(diff.contains("docs/idea.md"))
    #expect(diff.contains("docs/extra.md"))           // untracked picked up via add -N
}

@Test func normalizedDocDiffRejectsDirtyNonDoc() async throws {
    let fx = try await GitFixture()
    try fx.write("docs/idea.md", "x\n")
    try await fx.commitAll("init")
    try fx.write("src/app.swift", "code\n")
    await #expect { _ = try await DocDiff.normalized(fx.repo, config: .default) }
        throws: { ($0 as? DetDocError)?.code == "DIRTY_NON_DOC_CHANGES" }
}

@Test func normalizedDocDiffRequiresDocChanges() async throws {
    let fx = try await GitFixture()
    try fx.write("docs/idea.md", "x\n")
    try await fx.commitAll("init")
    await #expect { _ = try await DocDiff.normalized(fx.repo, config: .default) }
        throws: { ($0 as? DetDocError)?.code == "NO_DOC_CHANGES" }
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test` → build error (`DirtyPolicy` / `DocDiff` not found).

- [ ] **Step 3: Implement**

`Sources/DetDocCore/Services/DirtyPolicy.swift`
```swift
public enum DirtyPolicy {
    public static func nonDocOffenders(_ entries: [GitStatusEntry], config: DetDocConfig) -> [GitStatusEntry] {
        let policy = PathPolicy(config: config)
        return entries.filter { entry in
            !entry.path.hasPrefix(".detdoc/") && entry.path != ".gitignore" && !policy.isDoc(entry.path)
        }
    }

    public static func assertClean(_ entries: [GitStatusEntry], config: DetDocConfig, mode: RunMode) throws {
        let offenders = nonDocOffenders(entries, config: config)
        if !offenders.isEmpty {
            throw DetDocError("DIRTY_NON_DOC_CHANGES", offenders.map(\.path).joined(separator: ", "))
        }
    }
}
```

`Sources/DetDocCore/Services/DocDiff.swift`
```swift
public enum DocDiff {
    public static func normalized(_ repo: GitRepository, config: DetDocConfig) async throws -> String {
        let entries = try await repo.statusPorcelain()
        try DirtyPolicy.assertClean(entries, config: config, mode: .run)
        let policy = PathPolicy(config: config)
        let docPaths = entries.filter { policy.isDoc($0.path) }.map(\.path)
        if docPaths.isEmpty {
            throw DetDocError("NO_DOC_CHANGES", "No documentation changes found")
        }
        _ = try? await repo.git(["add", "-N", "--"] + docPaths)  // include untracked docs
        return try await repo.diffPaths(docPaths)
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test` → all green.
- [ ] **Step 5: Commit** — `git add Sources/DetDocCore/Services/DirtyPolicy.swift Sources/DetDocCore/Services/DocDiff.swift Tests/DetDocCoreTests/DirtyPolicyTests.swift Tests/DetDocCoreTests/DocDiffTests.swift && git commit -m "feat(core): add DirtyPolicy and normalized DocDiff"`

---

### Task 10: PatchCollector

**Files:**
- Create: `Sources/DetDocCore/Services/PatchCollector.swift`
- Test: `Tests/DetDocCoreTests/PatchCollectorTests.swift`

**Interfaces:**
- Consumes: `GitRepository` (T2), `DetDocError`.
- Produces:
  - `enum PatchCollector { static func collect(_ repo: GitRepository, approvedTargets: [String]) async throws -> String }` — empty targets → `NO_APPROVED_TARGETS`; `git add -N -- <targets>` (ignore failure); `patch = repo.diffPaths(targets)`; blank → `EMPTY_PATCH`; ensure trailing `\n`.

- [ ] **Step 1: Write the failing test**

`Tests/DetDocCoreTests/PatchCollectorTests.swift`
```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func collectReturnsPatchForNewTargetFile() async throws {
    let fx = try await GitFixture()
    try fx.write("README.md", "hi\n")
    try await fx.commitAll("init")
    try fx.write("src/new.swift", "let x = 1\n")  // untracked target
    let patch = try await PatchCollector.collect(fx.repo, approvedTargets: ["src/new.swift"])
    #expect(patch.contains("src/new.swift"))
    #expect(patch.hasSuffix("\n"))
}

@Test func collectRejectsEmptyTargets() async throws {
    let fx = try await GitFixture()
    await #expect { _ = try await PatchCollector.collect(fx.repo, approvedTargets: []) }
        throws: { ($0 as? DetDocError)?.code == "NO_APPROVED_TARGETS" }
}

@Test func collectRejectsEmptyPatch() async throws {
    let fx = try await GitFixture()
    try fx.write("src/x.swift", "same\n")
    try await fx.commitAll("init")  // target unchanged → empty diff
    await #expect { _ = try await PatchCollector.collect(fx.repo, approvedTargets: ["src/x.swift"]) }
        throws: { ($0 as? DetDocError)?.code == "EMPTY_PATCH" }
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test` → build error (`PatchCollector` not found).

- [ ] **Step 3: Implement**

`Sources/DetDocCore/Services/PatchCollector.swift`
```swift
public enum PatchCollector {
    public static func collect(_ repo: GitRepository, approvedTargets: [String]) async throws -> String {
        if approvedTargets.isEmpty {
            throw DetDocError("NO_APPROVED_TARGETS", "Approved plan contains no target files.")
        }
        _ = try? await repo.git(["add", "-N", "--"] + approvedTargets)
        let patch = try await repo.diffPaths(approvedTargets)
        if patch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DetDocError("EMPTY_PATCH", "Agent produced no code changes for approved target files.")
        }
        return patch.hasSuffix("\n") ? patch : patch + "\n"
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test` → all green.
- [ ] **Step 5: Commit** — `git add Sources/DetDocCore/Services/PatchCollector.swift Tests/DetDocCoreTests/PatchCollectorTests.swift && git commit -m "feat(core): add PatchCollector (collect approved-target patch)"`

---

### Task 11: GitignoreManager + RunApplier

**Files:**
- Create: `Sources/DetDocCore/Support/GitignoreManager.swift`
- Create: `Sources/DetDocCore/Services/RunApplier.swift`
- Test: `Tests/DetDocCoreTests/RunApplierTests.swift`

**Interfaces:**
- Consumes: `GitRepository` (T2), `ArtifactStore` (Plan 1), `RunManifest`/`TouchedFile` (T7), `ValidationRunner` (T4), `ConfigStore` (Plan 1), `DetDocError`.
- Produces:
  - `enum GitignoreManager { static func ensureManagedEntries(root: URL) throws }` — same 4 entries as `ConfigStore` (`.DS_Store`, `.detdoc/runs/*`, `!.detdoc/runs/.gitkeep`, `.worktrees/`), appended if missing.
  - `struct RunApplier: Sendable { init() }`
  - `func apply(root: URL, runId: String, autoCommit: Bool) async throws -> RunFlowResult` — read manifest+patch; HEAD≠baseCommit → `APPLY_BASE_MISMATCH`; per touchedFile `fileSha256(path) != before` → `APPLY_PREIMAGE_MISMATCH`; `repo.applyPatch(patch)`; post-apply validation (load config; if commands run them, write `post-apply-validation.log`); then commit-or-stage: ensure gitignore; `git add -- <approvedTargets>`; if autoCommit: `git commit -m "DetDoc apply <runId>"` and `store.deleteRun(runId)`. Returns `RunFlowResult(runId, applied: true, patch)`.

- [ ] **Step 1: Write the failing test**

`Tests/DetDocCoreTests/RunApplierTests.swift`
```swift
import Foundation
import Testing
@testable import DetDocCore

/// Build a saved run whose patch creates `src/new.swift`, with a correct base + preimage.
private func seedSavedRun(_ fx: GitFixture, autoCommitConfig: Bool = true) async throws -> String {
    try fx.write("README.md", "hi\n")
    try await fx.commitAll("init")
    let base = try await fx.repo.headCommit()
    // produce a patch that adds src/new.swift
    try fx.write("src/new.swift", "let x = 1\n")
    let patch = try await PatchCollector.collect(fx.repo, approvedTargets: ["src/new.swift"])
    _ = try await fx.repo.git(["checkout", "--", "."])  // revert working tree to clean base
    try? FileManager.default.removeItem(at: fx.root.appendingPathComponent("src/new.swift"))

    var manifest = RunManifest.initial(mode: .run, baseCommit: base)
    manifest.approvedTargets = ["src/new.swift"]
    manifest.touchedFiles = [TouchedFile(path: "src/new.swift", before: nil, after: "x")]  // before=nil: file absent at base
    let store = ArtifactStore(projectRoot: fx.root)
    try store.createRun(manifest)
    try store.writeText(manifest.runId, "changes.patch", patch)
    return manifest.runId
}

@Test func applySavedRunCommitsPatchAndRemovesArtifacts() async throws {
    let fx = try await GitFixture()
    let runId = try await seedSavedRun(fx)
    let result = try await RunApplier().apply(root: fx.root, runId: runId, autoCommit: true)
    #expect(result.applied)
    #expect(FileManager.default.fileExists(atPath: fx.root.appendingPathComponent("src/new.swift").path))
    let log = try await fx.repo.git(["log", "--oneline", "-1"])
    #expect(log.contains("DetDoc apply \(runId)"))
    #expect(!FileManager.default.fileExists(atPath: ArtifactStore(projectRoot: fx.root).runDir(runId).path))
}

@Test func applyRejectsMovedHead() async throws {
    let fx = try await GitFixture()
    let runId = try await seedSavedRun(fx)
    try fx.write("other.txt", "x\n"); try await fx.commitAll("move head")  // HEAD now != baseCommit
    await #expect { _ = try await RunApplier().apply(root: fx.root, runId: runId, autoCommit: true) }
        throws: { ($0 as? DetDocError)?.code == "APPLY_BASE_MISMATCH" }
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test` → build error (`RunApplier` / `GitignoreManager` not found).

- [ ] **Step 3: Implement**

`Sources/DetDocCore/Support/GitignoreManager.swift`
```swift
import Foundation

public enum GitignoreManager {
    public static let managedEntries = [".DS_Store", ".detdoc/runs/*", "!.detdoc/runs/.gitkeep", ".worktrees/"]

    public static func ensureManagedEntries(root: URL) throws {
        let url = root.appendingPathComponent(".gitignore")
        var content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        for entry in managedEntries where !content.split(separator: "\n", omittingEmptySubsequences: false)
            .contains(where: { $0.trimmingCharacters(in: .whitespaces) == entry }) {
            if !content.isEmpty && !content.hasSuffix("\n") { content += "\n" }
            content += entry + "\n"
        }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw DetDocError("GITIGNORE_WRITE_FAILED", "\(error)")
        }
    }
}
```

`Sources/DetDocCore/Services/RunApplier.swift`
```swift
import Foundation

public struct RunApplier: Sendable {
    public init() {}

    public func apply(root: URL, runId: String, autoCommit: Bool) async throws -> RunFlowResult {
        let store = ArtifactStore(projectRoot: root)
        let manifest: RunManifest = try store.readJSON(RunManifest.self, runId, "manifest.json")
        let patch = try store.readText(runId, "changes.patch")
        let repo = GitRepository(root)

        let head = try await repo.headCommit()
        if head != manifest.baseCommit {
            throw DetDocError("APPLY_BASE_MISMATCH", "HEAD (\(head)) does not match the saved run base commit (\(manifest.baseCommit))")
        }
        for file in manifest.touchedFiles where repo.fileSha256(file.path) != file.before {
            throw DetDocError("APPLY_PREIMAGE_MISMATCH", "preimage hash mismatch for \(file.path)")
        }

        try await repo.applyPatch(patch)
        try await runPostApplyValidation(root: root, store: store, runId: runId)
        try await commitOrStage(repo: repo, approvedTargets: manifest.approvedTargets, runId: runId, autoCommit: autoCommit, store: store)
        return RunFlowResult(runId: runId, applied: true, patch: patch)
    }

    func runPostApplyValidation(root: URL, store: ArtifactStore, runId: String) async throws {
        let config = try ConfigStore().load(root: root)
        guard !config.validation.commands.isEmpty else { return }
        let log = try await ValidationRunner().run(commands: config.validation.commands, cwd: root)
        try store.writeText(runId, "post-apply-validation.log", log)
    }

    func commitOrStage(repo: GitRepository, approvedTargets: [String], runId: String, autoCommit: Bool, store: ArtifactStore) async throws {
        try GitignoreManager.ensureManagedEntries(root: repo.cwd)
        _ = try await repo.git(["add", "--"] + approvedTargets)
        if autoCommit {
            _ = try await repo.git(["commit", "-m", "DetDoc apply \(runId)"])
            try store.deleteRun(runId)
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test` → all green.
- [ ] **Step 5: Commit** — `git add Sources/DetDocCore/Support/GitignoreManager.swift Sources/DetDocCore/Services/RunApplier.swift Tests/DetDocCoreTests/RunApplierTests.swift && git commit -m "feat(core): add GitignoreManager and RunApplier (saved-run apply)"`

---

### Task 12: DetDocEngine (run/fix orchestration + approval gates)

**Files:**
- Create: `Sources/DetDocCore/Engine/DetDocEngine.swift`
- Test: `Tests/DetDocCoreTests/FlowFakeAgentTests.swift`

**Interfaces:**
- Consumes: everything above + `ConfigStore`, `ArtifactStore`, `PlanValidator`, `PatchValidator`, `RunManifest`, `RunEvent`.
- Produces:
  - `actor DetDocEngine`
  - `init(root: URL, agent: any AgentRunner)`
  - `func start(mode: RunMode, message: String? = nil) -> AsyncThrowingStream<RunEvent, Error>` — runs the flow on a child task, yields `RunEvent`s, finishes on completion/error.
  - `func submitPlanDecision(_ decision: PlanDecision)` and `func submitApplyDecision(_ decision: ApplyDecision)` — resume the engine's pending continuation at a gate.
  - Behavior mirrors the TS `runFlow`: collect input (run = DocDiff.normalized; fix = message + DirtyPolicy + non-empty `EMPTY_FIX_MESSAGE`); create run + artifacts; create worktree; (run) apply doc diff into worktree; plan → validate → `planReady` gate; on `.reject` → `PLAN_NOT_APPROVED`; write approved plan + manifest; implement; repair loop (collect patch via `PatchCollector`, `PatchValidator.validatePaths`, `ValidationRunner` in worktree, up to `maxValidationRepairAttempts` repairs when `agent.supportsRepair`, saving `validation-failure-<n>.log`); compute `touchedFiles` (before from main repo, after from worktree repo); write `changes.patch` + `validation.log`; `patchReady` gate; on `.discard` → complete(applied:false); else apply to main, post-apply validation, delete artifacts, scoped commit; cleanup worktree unless kept on failure.

- [ ] **Step 1: Write the failing test**

`Tests/DetDocCoreTests/FlowFakeAgentTests.swift`
```swift
import Foundation
import Testing
@testable import DetDocCore

/// Drive the engine to completion, auto-answering both gates.
private func drive(_ engine: DetDocEngine, mode: RunMode, message: String? = nil,
                   plan: PlanDecision, apply: ApplyDecision) async throws -> RunFlowResult? {
    let stream = await engine.start(mode: mode, message: message)
    var result: RunFlowResult?
    for try await event in stream {
        switch event {
        case .planReady: await engine.submitPlanDecision(plan)
        case .patchReady: await engine.submitApplyDecision(apply)
        case .complete(let r): result = r
        default: break
        }
    }
    return result
}

private func detdocRepo() async throws -> GitFixture {
    let fx = try await GitFixture()
    try ConfigStore().initFiles(root: fx.root)
    try await fx.commitAll("detdoc init")
    return fx
}

@Test func runFlowAppliesAndCommitsWithFakeAgent() async throws {
    let fx = try await detdocRepo()
    try fx.write("docs/idea.md", "changed idea\n")   // dirty doc drives the run
    let engine = DetDocEngine(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "let v = 2\n"))
    let result = try await drive(engine, mode: .run, plan: .approve, apply: .apply)
    #expect(result?.applied == true)
    #expect(FileManager.default.fileExists(atPath: fx.root.appendingPathComponent("src/app.swift").path))
    let log = try await fx.repo.git(["log", "--oneline", "-1"])
    #expect(log.contains("DetDoc apply"))
}

@Test func runFlowStopsWhenApplyDiscarded() async throws {
    let fx = try await detdocRepo()
    try fx.write("docs/idea.md", "changed\n")
    let engine = DetDocEngine(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "let v = 3\n"))
    let result = try await drive(engine, mode: .run, plan: .approve, apply: .discard)
    #expect(result?.applied == false)
    // patch saved, not applied to main
    #expect(!FileManager.default.fileExists(atPath: fx.root.appendingPathComponent("src/app.swift").path))
}

@Test func runFlowRejectsWhenPlanRejected() async throws {
    let fx = try await detdocRepo()
    try fx.write("docs/idea.md", "changed\n")
    let engine = DetDocEngine(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "x\n"))
    await #expect { _ = try await drive(engine, mode: .run, plan: .reject, apply: .apply) }
        throws: { ($0 as? DetDocError)?.code == "PLAN_NOT_APPROVED" }
}

@Test func fixFlowRequiresNonEmptyMessage() async throws {
    let fx = try await detdocRepo()
    let engine = DetDocEngine(root: fx.root, agent: FakeAgentRunner(target: "src/app.swift", content: "x\n"))
    await #expect { _ = try await drive(engine, mode: .fix, message: "   ", plan: .approve, apply: .apply) }
        throws: { ($0 as? DetDocError)?.code == "EMPTY_FIX_MESSAGE" }
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test` → build error (`DetDocEngine` not found).

- [ ] **Step 3: Implement**

`Sources/DetDocCore/Engine/DetDocEngine.swift`
```swift
import Foundation

public actor DetDocEngine {
    private let root: URL
    private let agent: any AgentRunner
    private let maxRepairAttempts = 2

    private var pendingPlan: CheckedContinuation<PlanDecision, Never>?
    private var pendingApply: CheckedContinuation<ApplyDecision, Never>?

    public init(root: URL, agent: any AgentRunner) {
        self.root = root
        self.agent = agent
    }

    public func submitPlanDecision(_ decision: PlanDecision) {
        pendingPlan?.resume(returning: decision)
        pendingPlan = nil
    }

    public func submitApplyDecision(_ decision: ApplyDecision) {
        pendingApply?.resume(returning: decision)
        pendingApply = nil
    }

    private func awaitPlanDecision() async -> PlanDecision {
        await withCheckedContinuation { pendingPlan = $0 }
    }

    private func awaitApplyDecision() async -> ApplyDecision {
        await withCheckedContinuation { pendingApply = $0 }
    }

    public func start(mode: RunMode, message: String? = nil) -> AsyncThrowingStream<RunEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await self.runFlow(mode: mode, message: message) { event in
                        continuation.yield(event)
                    }
                    continuation.yield(.complete(result))
                    continuation.finish()
                } catch let error as DetDocError {
                    continuation.yield(.error(error))
                    continuation.finish(throwing: error)
                } catch {
                    let wrapped = DetDocError("ENGINE_FAILED", "\(error)")
                    continuation.yield(.error(wrapped))
                    continuation.finish(throwing: wrapped)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runFlow(mode: RunMode, message: String?, emit: @Sendable (RunEvent) -> Void) async throws -> RunFlowResult {
        emit(.progress(phase: .loadConfig, message: "Loading DetDoc config"))
        let config = try ConfigStore().load(root: root)
        let mainRepo = GitRepository(root)

        emit(.progress(phase: .collectInput, message: mode == .run ? "Collecting documentation changes" : "Collecting fix intent"))
        let taskInput: String
        if mode == .run {
            taskInput = try await DocDiff.normalized(mainRepo, config: config)
        } else {
            try DirtyPolicy.assertClean(try await mainRepo.statusPorcelain(), config: config, mode: .fix)
            let msg = message ?? ""
            if msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw DetDocError("EMPTY_FIX_MESSAGE", "detdoc fix requires a non-empty message.")
            }
            taskInput = msg
        }

        emit(.progress(phase: .createRun, message: "Creating run artifacts"))
        var manifest = RunManifest.initial(mode: mode, baseCommit: try await mainRepo.headCommit())
        let store = ArtifactStore(projectRoot: root)
        try store.createRun(manifest)
        try store.writeText(manifest.runId, mode == .run ? "input.diff.md" : "intent.md", taskInput)

        emit(.progress(phase: .createWorktree, message: "Creating isolated worktree"))
        let worktree = try await WorktreeManager().createFromHead(mainRepo, runId: manifest.runId)
        var keepWorktree = config.worktree.keepOnFailure
        do {
            let result = try await runInsideWorktree(mode: mode, taskInput: taskInput, config: config,
                                                     mainRepo: mainRepo, worktree: worktree, store: store,
                                                     manifest: &manifest, keepWorktree: &keepWorktree, emit: emit)
            if !keepWorktree {
                emit(.progress(phase: .cleanupWorktree, message: "Cleaning up isolated worktree"))
                try? await WorktreeManager().cleanup(mainRepo, worktree)
            }
            emit(.progress(phase: .done, message: "Run complete"))
            return result
        } catch {
            if !keepWorktree {
                try? await WorktreeManager().cleanup(mainRepo, worktree)
            }
            throw error
        }
    }

    private func runInsideWorktree(mode: RunMode, taskInput: String, config: DetDocConfig,
                                   mainRepo: GitRepository, worktree: WorktreeHandle, store: ArtifactStore,
                                   manifest: inout RunManifest, keepWorktree: inout Bool,
                                   emit: @Sendable (RunEvent) -> Void) async throws -> RunFlowResult {
        let worktreeRepo = worktree.repo
        if mode == .run {
            emit(.progress(phase: .applyInputToWorktree, message: "Applying documentation changes to worktree"))
            try await worktreeRepo.applyPatch(taskInput)
        }

        emit(.progress(phase: .plan, message: "Agent is planning code changes"))
        let planResult = try await agent.plan(PlanRequest(mode: mode, input: taskInput, config: config, cwd: worktree.path))
        let proposed = try PlanValidator.validate(planResult.plan, config: config, mode: mode)
        try store.writeJSON(manifest.runId, "plan.proposed.json", proposed)

        emit(.progress(phase: .approvePlan, message: "Waiting for plan approval"))
        emit(.planReady(proposed))
        if await awaitPlanDecision() == .reject {
            throw DetDocError("PLAN_NOT_APPROVED", "Plan was not approved.")
        }
        try store.writeJSON(manifest.runId, "plan.approved.json", proposed)
        let approvedTargets = PlanValidator.approvedTargets(from: proposed)
        manifest.approvedTargets = approvedTargets
        try store.writeJSON(manifest.runId, "manifest.json", manifest)

        emit(.progress(phase: .implement, message: "Agent is editing approved files"))
        _ = try await agent.implement(ImplementRequest(mode: mode, input: taskInput, config: config, cwd: worktree.path,
                                                        approvedPlan: proposed, approvedTargets: approvedTargets, progress: nil))

        var patch = ""
        var changedFiles: [String] = []
        var validationLog = ""
        var attempt = 0
        while true {
            emit(.progress(phase: .collectPatch, message: "Collecting generated patch"))
            patch = try await PatchCollector.collect(worktreeRepo, approvedTargets: approvedTargets)
            emit(.progress(phase: .validatePatch, message: "Validating generated patch"))
            try PatchValidator.validatePaths(patch, approvedTargets: approvedTargets, config: config)
            changedFiles = try await worktreeRepo.changedFilesFromPatch(patch).sorted()
            do {
                let worktreeConfig = try ConfigStore().load(root: worktree.path)
                validationLog = try await ValidationRunner().run(commands: worktreeConfig.validation.commands, cwd: worktree.path)
                break
            } catch let error as DetDocError where error.code == "VALIDATION_FAILED" && agent.supportsRepair && attempt < maxRepairAttempts {
                attempt += 1
                try store.writeText(manifest.runId, "validation-failure-\(attempt).log", error.message)
                emit(.progress(phase: .repairValidation, message: "Agent is fixing validation failure (\(attempt)/\(maxRepairAttempts))"))
                let base = ImplementRequest(mode: mode, input: taskInput, config: config, cwd: worktree.path,
                                            approvedPlan: proposed, approvedTargets: approvedTargets, progress: nil)
                _ = try await agent.repairValidation(RepairRequest(base: base, validationLog: error.message, attempt: attempt))
            }
        }

        manifest.touchedFiles = changedFiles.map { path in
            TouchedFile(path: path, before: mainRepo.fileSha256(path), after: worktreeRepo.fileSha256(path))
        }
        try store.writeText(manifest.runId, "changes.patch", patch)
        try store.writeText(manifest.runId, "validation.log", validationLog)
        try store.writeJSON(manifest.runId, "manifest.json", manifest)

        emit(.progress(phase: .approveApply, message: "Waiting for apply approval"))
        emit(.patchReady(PatchReview(runId: manifest.runId, changedFiles: changedFiles, patch: patch, worktreePath: worktree.path.path)))
        if await awaitApplyDecision() == .discard {
            keepWorktree = false
            return RunFlowResult(runId: manifest.runId, applied: false, patch: patch)
        }

        emit(.progress(phase: .applyPatch, message: "Merging validated worktree changes into main"))
        try await mainRepo.applyPatch(patch)
        keepWorktree = false
        emit(.progress(phase: .postApplyValidation, message: "Running validation in main worktree"))
        try await RunApplier().runPostApplyValidation(root: root, store: store, runId: manifest.runId)
        emit(.progress(phase: .cleanupRun, message: "Removing run artifacts"))
        emit(.progress(phase: .commit, message: "Committing applied changes"))
        try await RunApplier().commitOrStage(repo: mainRepo, approvedTargets: approvedTargets, runId: manifest.runId, autoCommit: config.apply.autoCommit, store: store)
        return RunFlowResult(runId: manifest.runId, applied: true, patch: patch)
    }
}
```

> Note: `RunApplier.runPostApplyValidation` and `commitOrStage` are reused from Task 11; if Swift access control requires it, mark them `public` (the test target uses `@testable`, but the engine calls them across files in the same module, so `internal` suffices — they are declared without `private` in Task 11).

- [ ] **Step 4: Run to verify it passes**

Run: `cd swift/DetDocCore && swift test`
Expected: PASS — all FlowFakeAgentTests green (and the whole suite). If the actor/continuation gate deadlocks, confirm the test drives the stream in a single `for try await` loop that calls `submit...` on receiving `.planReady`/`.patchReady` (as written).

- [ ] **Step 5: Commit** — `git add Sources/DetDocCore/Engine/DetDocEngine.swift Tests/DetDocCoreTests/FlowFakeAgentTests.swift && git commit -m "feat(core): add DetDocEngine run/fix orchestration with approval gates"`

---

### Task 13: Full-suite green gate

**Files:** none (verification only).

- [ ] **Step 1: Run the entire suite** — `cd swift/DetDocCore && swift test` → all Plan 1 + Plan 2 tests pass, no failures/skips.
- [ ] **Step 2: Warnings-clean build** — `swift build` (the `DetDocCore` target carries `treatAllWarnings(as: .error)`, so a warning fails the build). If it fails on a warning, fix it (do not suppress).
- [ ] **Step 3: Commit any fixes** — `git add -A swift/DetDocCore && git commit -m "test(core): green gate for DetDocCore flow layer" --allow-empty`

---

## Self-Review

**1. Spec coverage (Plan 2 slice of the design spec):**
- `GitRepository` (Process shell-out, TS git semantics) → T2. ✓
- `WorktreeManager` → T8. ✓
- `DocsService` (CRUD + include/exclude) → T3. ✓
- `DocDiff` (+ untracked via `add -N`, dirty policy) → T9. ✓
- `ValidationRunner` → T4. ✓
- `AgentRunner` + `FakeAgentRunner` → T5. ✓
- `PiHealth` → T6. ✓
- `RunEvent`/gates + `DetDocEngine` (run/fix, validation/repair, touchedFiles, apply, post-apply, commit) → T7, T12. ✓
- Saved-run apply (`APPLY_BASE_MISMATCH` + preimage guard) → T11. ✓
- Manifest closes the replay gap (`touchedFiles`) → T7. ✓
- Deferred (later plans, correctly out of scope): `PiAgentRunner` (Plan 4), the entire `DetDocApp` (Plan 3), `replayRun` as a GUI action (design defers it).

**2. Placeholder scan:** Every step shows full code (tests + implementation). No TBD/"handle errors"/"similar to". ✓

**3. Type consistency:** `GitRepository(_ cwd: URL)` / `git(_:stdin:)` used consistently (T2/T8/T9/T10/T11/T12). `RunManifest.touchedFiles`/`TouchedFile(before:after:)` consistent (T7/T11/T12). `PlanValidator.validate`/`approvedTargets`, `PatchValidator.validatePaths`, `ArtifactStore.writeJSON/readJSON/writeText`, `ConfigStore().load(root:)`, `ValidationRunner().run(commands:cwd:)` all match their Plan 1 / earlier-task signatures. Engine reuses `RunApplier.runPostApplyValidation`/`commitOrStage` (declared non-private in T11). ✓

**Risk note for the implementer:** Task 12's actor + `CheckedContinuation` gate is the one non-mechanical piece. The flow stores a single pending continuation per gate and resumes it from `submit...`; the test drives the stream and answers gates inline. If Swift 6 strict-concurrency flags the `emit` closure or `ProcessRunner`'s `DataBox`, prefer the smallest fix that preserves behavior (e.g. capture lists, `@Sendable`), never weakening the safety checks.

---

## Next Plans (roadmap)

- **Plan 3 — DetDocApp:** XcodeGen macOS app, MVVM+C, `NavigationSplitView` + `.inspector`, docs explorer/editor (source+preview), run/fix panel consuming `DetDocEngine`'s stream, plan/patch review gates, runs list, settings, onboarding.
- **Plan 4 — PiAgentRunner:** pin the `pi --mode rpc` JSONL wire schema; real planning/implementation/repair behind the `AgentRunner` protocol.
