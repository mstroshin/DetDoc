# DetDocCore Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the UI-agnostic, pure-logic foundation of `DetDocCore` — the domain models, glob matcher, config (Yams), path policy, artifact store, run-id, and plan/patch validators — fully tested with Swift Testing and headless (no subprocess, no git, no SwiftUI).

**Architecture:** `DetDocCore` is a pure-Swift SwiftPM library with zero UI dependencies, reusable by both the SwiftUI GUI and a future Swift TUI. This plan implements only the deterministic, side-effect-light slice (data models + file IO under a temp dir + validation rules). Subprocess/git/flow and the app are separate later plans.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing, Yams (YAML), Foundation (`NSRegularExpression`, `FileManager`, `JSONEncoder`/`JSONDecoder`).

## Global Constraints

- Platform floor: **macOS 27** (`platforms: [.macOS(.v27)]`); requires a toolchain with the macOS 27 SDK.
- Language/tests: **pure Swift**; all tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`/`#require`). No XCTest.
- `DetDocCore` has **zero UI dependencies** (no SwiftUI/AppKit) and the **only** external dependency is **Yams**.
- Preserve existing on-disk **artifact/config field names and shapes** so runs/configs from the Rust/TS implementations remain readable.
- All public model types are `Sendable` and `Codable`.
- Error model: `DetDocError(code, message, …)` with **stable codes copied verbatim** from the reference implementation (listed per task).
- Parity reference lives in `src-tauri/src/detdoc/*.rs` and `src/core/*.ts`; behavior must match it.

## Reference Parity Facts (copied verbatim from `src-tauri/src/detdoc/`)

- `docs.include` default: `["**/*.md"]`; `docs.exclude` default: `[".detdoc/**", "node_modules/**"]`.
- `paths.deny` default: `[".env", ".env.*", "node_modules/**", ".git/**"]`.
- `agent.provider` default: `"pi-rpc"`; `agent.model` default: `null`; `agent.thinking` default: `"high"`.
- `worktree.keepOnFailure` default: `true`; `apply.autoCommit` default: `true`.
- `validation.commands` default: `[]`. Each input item may be a bare string, or an object with `run`, `command`, or `cmd`, plus optional `name`. Normalized to `{ name, run }`; when `name` is absent it defaults to the command string.
- `is_denied_path(p)` = `p` matches any `paths.deny` glob.
- `is_doc_path(p)` = `p` matches any `docs.include` glob AND matches no `docs.exclude` glob.
- Glob semantics (globset-compatible): `*` does not cross `/`; `**` crosses `/`; a `**/` segment also matches zero directories (so `**/*.md` matches both `a.md` and `x/a.md`); `?` matches a single non-`/` char.
- `create_run_id(mode)` = `"{YYYYMMDDTHHMMSSZ}-{run|fix}-{first 8 lowercase hex of a UUID}"`.
- `RunManifest` JSON keys: `runId`, `mode` (`"run"`/`"fix"`), `baseCommit`, `approvedTargets`. This plan additionally writes `preImageHashes` (object) to close the replay gap; it must decode as empty when absent.
- Artifact JSON is pretty-printed with a trailing newline; `ArtifactStore` root is `<project>/.detdoc/runs`.
- `validate_patch_paths`: for each patch line starting with `+++ b/` or `--- a/`, the path is the text after the 6-char prefix; skip `/dev/null`; reject denied (`PATCH_DENIED_PATH`), doc (`PATCH_DOC_PATH`), or unapproved (`PATCH_UNAPPROVED_PATH`) paths.
- `validate_proposed_plan` error codes: `PLAN_EMPTY`, `PLAN_RISK_INVALID`, `PLAN_KIND_INVALID`, `PLAN_CHANGE_NO_TARGETS`, `PLAN_REASON_INVALID`, `PLAN_TARGET_DENIED`, `PLAN_TARGETS_DOC`. Run reasons must start with `doc-diff:`; fix reasons with `intent:`. Valid kinds: `create`, `modify`, `delete`, `rename`. Valid risks: `low`, `medium`, `high`.

---

## File Structure

```txt
swift/DetDocCore/
  Package.swift
  Sources/DetDocCore/
    DetDocCore.swift            # version marker
    Models/
      DetDocError.swift         # DetDocError
      CoreModels.swift          # RunMode, DocFile, DirtyFile, ProjectStatus, RunSummary, RunFlowResult, TokenUsage
      Plan.swift                # PlanChange, ProposedPlan
      RunManifest.swift         # RunManifest
    Support/
      Glob.swift                # Glob matcher (glob -> NSRegularExpression)
      RunID.swift               # RunID.create(mode:now:uuid:)
    Config/
      DetDocConfig.swift        # DetDocConfig + sub-configs + ValidationCommand
      ConfigStore.swift         # load / default YAML / init files / gitignore
    Services/
      PathPolicy.swift          # isDenied / isDoc
      ArtifactStore.swift       # run dir JSON/text read/write/delete
      PlanValidator.swift       # validateProposedPlan / approvedTargets
      PatchValidator.swift      # validatePatchPaths
  Tests/DetDocCoreTests/
    PackageSmokeTests.swift
    DetDocErrorTests.swift
    CoreModelsTests.swift
    PlanModelTests.swift
    RunManifestTests.swift
    GlobTests.swift
    DetDocConfigTests.swift
    ConfigStoreTests.swift
    PathPolicyTests.swift
    ArtifactStoreTests.swift
    PlanValidatorTests.swift
    PatchValidatorTests.swift
    Support/TempDir.swift       # test helper
```

---

### Task 1: Scaffold the DetDocCore SwiftPM package

**Files:**
- Create: `swift/DetDocCore/Package.swift`
- Create: `swift/DetDocCore/Sources/DetDocCore/DetDocCore.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/PackageSmokeTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum DetDocCore { static let version: String }`; a buildable package with a Swift Testing test target depending on `DetDocCore` and `Yams`.

- [ ] **Step 1: Write the failing test**

`swift/DetDocCore/Tests/DetDocCoreTests/PackageSmokeTests.swift`
```swift
import Testing
@testable import DetDocCore

@Test func packageExposesVersion() {
    #expect(DetDocCore.version == "0.1.0")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd swift/DetDocCore && swift test`
Expected: FAIL — build error, no such module `DetDocCore` / no `Package.swift`.

- [ ] **Step 3: Write minimal implementation**

`swift/DetDocCore/Package.swift`
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DetDocCore",
    platforms: [.macOS(.v27)],
    products: [
        .library(name: "DetDocCore", targets: ["DetDocCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "DetDocCore",
            dependencies: [.product(name: "Yams", package: "Yams")]
        ),
        .testTarget(
            name: "DetDocCoreTests",
            dependencies: ["DetDocCore"]
        ),
    ]
)
```

`swift/DetDocCore/Sources/DetDocCore/DetDocCore.swift`
```swift
/// Namespace + version marker for the DetDocCore library.
public enum DetDocCore {
    public static let version = "0.1.0"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd swift/DetDocCore && swift test`
Expected: PASS (1 test). Note: if the local toolchain predates the macOS 27 SDK, the platform line is the only blocker — the target OS is 27 by spec; do not lower it to make local builds pass without flagging it.

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Package.swift swift/DetDocCore/Sources/DetDocCore/DetDocCore.swift swift/DetDocCore/Tests/DetDocCoreTests/PackageSmokeTests.swift
git commit -m "feat(core): scaffold DetDocCore SwiftPM package with Yams + Swift Testing"
```

---

### Task 2: DetDocError

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Models/DetDocError.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/DetDocErrorTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct DetDocError: Error, Sendable, Equatable, CustomStringConvertible`
  - fields: `code: String`, `message: String`, and optional `details/phase/runId/path/command/suggestedAction: String?`
  - `init(_ code: String, _ message: String)` convenience and a full memberwise `init`
  - `var description: String` → `"\(code): \(message)"`

- [ ] **Step 1: Write the failing test**

`swift/DetDocCore/Tests/DetDocCoreTests/DetDocErrorTests.swift`
```swift
import Testing
@testable import DetDocCore

@Test func errorDescriptionIsCodeColonMessage() {
    let error = DetDocError("CONFIG_MISSING", "DetDoc config is missing")
    #expect(error.code == "CONFIG_MISSING")
    #expect(error.message == "DetDoc config is missing")
    #expect(String(describing: error) == "CONFIG_MISSING: DetDoc config is missing")
    #expect(error.path == nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd swift/DetDocCore && swift test --filter DetDocErrorTests`
Expected: FAIL — build error, `DetDocError` not found.

- [ ] **Step 3: Write minimal implementation**

`swift/DetDocCore/Sources/DetDocCore/Models/DetDocError.swift`
```swift
public struct DetDocError: Error, Sendable, Equatable, CustomStringConvertible {
    public let code: String
    public let message: String
    public var details: String?
    public var phase: String?
    public var runId: String?
    public var path: String?
    public var command: String?
    public var suggestedAction: String?

    public init(
        code: String,
        message: String,
        details: String? = nil,
        phase: String? = nil,
        runId: String? = nil,
        path: String? = nil,
        command: String? = nil,
        suggestedAction: String? = nil
    ) {
        self.code = code
        self.message = message
        self.details = details
        self.phase = phase
        self.runId = runId
        self.path = path
        self.command = command
        self.suggestedAction = suggestedAction
    }

    public init(_ code: String, _ message: String) {
        self.init(code: code, message: message)
    }

    public var description: String { "\(code): \(message)" }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd swift/DetDocCore && swift test --filter DetDocErrorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Models/DetDocError.swift swift/DetDocCore/Tests/DetDocCoreTests/DetDocErrorTests.swift
git commit -m "feat(core): add DetDocError value type"
```

---

### Task 3: Core value models (RunMode + status/doc/run types)

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Models/CoreModels.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/CoreModelsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces (all `Codable, Sendable, Equatable`):
  - `enum RunMode: String { case run, fix }`
  - `struct DocFile { var path: String; var title: String }`
  - `struct DirtyFile { var status: String; var path: String }`
  - `struct ProjectStatus { var root: String; var initialized: Bool; var piAvailable: Bool; var dirtyFiles: [DirtyFile] }`
  - `struct RunSummary { var runId: String; var hasPatch: Bool; var approvedTargets: [String] }`
  - `struct RunFlowResult { var runId: String; var applied: Bool; var patch: String }`
  - `struct TokenUsage { var input, output, cacheRead, cacheWrite, total: Int }`

- [ ] **Step 1: Write the failing test**

`swift/DetDocCore/Tests/DetDocCoreTests/CoreModelsTests.swift`
```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func runModeEncodesAsLowercaseRawValue() throws {
    let data = try JSONEncoder().encode([RunMode.run, RunMode.fix])
    #expect(String(decoding: data, as: UTF8.self) == #"["run","fix"]"#)
}

@Test func projectStatusRoundTripsThroughJSON() throws {
    let status = ProjectStatus(
        root: "/repo",
        initialized: true,
        piAvailable: false,
        dirtyFiles: [DirtyFile(status: " M", path: "docs/idea.md")]
    )
    let data = try JSONEncoder().encode(status)
    let decoded = try JSONDecoder().decode(ProjectStatus.self, from: data)
    #expect(decoded == status)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd swift/DetDocCore && swift test --filter CoreModelsTests`
Expected: FAIL — build error, types not found.

- [ ] **Step 3: Write minimal implementation**

`swift/DetDocCore/Sources/DetDocCore/Models/CoreModels.swift`
```swift
public enum RunMode: String, Codable, Sendable, Equatable {
    case run
    case fix
}

public struct DocFile: Codable, Sendable, Equatable {
    public var path: String
    public var title: String
    public init(path: String, title: String) {
        self.path = path
        self.title = title
    }
}

public struct DirtyFile: Codable, Sendable, Equatable {
    public var status: String
    public var path: String
    public init(status: String, path: String) {
        self.status = status
        self.path = path
    }
}

public struct ProjectStatus: Codable, Sendable, Equatable {
    public var root: String
    public var initialized: Bool
    public var piAvailable: Bool
    public var dirtyFiles: [DirtyFile]
    public init(root: String, initialized: Bool, piAvailable: Bool, dirtyFiles: [DirtyFile]) {
        self.root = root
        self.initialized = initialized
        self.piAvailable = piAvailable
        self.dirtyFiles = dirtyFiles
    }
}

public struct RunSummary: Codable, Sendable, Equatable {
    public var runId: String
    public var hasPatch: Bool
    public var approvedTargets: [String]
    public init(runId: String, hasPatch: Bool, approvedTargets: [String]) {
        self.runId = runId
        self.hasPatch = hasPatch
        self.approvedTargets = approvedTargets
    }
}

public struct RunFlowResult: Codable, Sendable, Equatable {
    public var runId: String
    public var applied: Bool
    public var patch: String
    public init(runId: String, applied: Bool, patch: String) {
        self.runId = runId
        self.applied = applied
        self.patch = patch
    }
}

public struct TokenUsage: Codable, Sendable, Equatable {
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite: Int
    public var total: Int
    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0, total: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.total = total
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd swift/DetDocCore && swift test --filter CoreModelsTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Models/CoreModels.swift swift/DetDocCore/Tests/DetDocCoreTests/CoreModelsTests.swift
git commit -m "feat(core): add RunMode and core value models"
```

---

### Task 4: Plan models (ProposedPlan, PlanChange)

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Models/Plan.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/PlanModelTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces (all `Codable, Sendable, Equatable`):
  - `struct PlanChange { var reason: String; var targetFiles: [String]; var kind: String; var rationale: String }`
  - `struct ProposedPlan { var summary: String; var changes: [PlanChange]; var questions: [String]; var risk: String }` — `questions` decodes to `[]` when absent.

- [ ] **Step 1: Write the failing test**

`swift/DetDocCore/Tests/DetDocCoreTests/PlanModelTests.swift`
```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func planDecodesWithCamelCaseTargetFiles() throws {
    let json = """
    {
      "summary": "do the thing",
      "changes": [
        { "reason": "doc-diff:docs/spec.md:L1-L2", "targetFiles": ["src/app.ts"], "kind": "modify", "rationale": "because" }
      ],
      "risk": "low"
    }
    """
    let plan = try JSONDecoder().decode(ProposedPlan.self, from: Data(json.utf8))
    #expect(plan.summary == "do the thing")
    #expect(plan.changes.first?.targetFiles == ["src/app.ts"])
    #expect(plan.questions == [])  // defaulted when absent
    #expect(plan.risk == "low")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd swift/DetDocCore && swift test --filter PlanModelTests`
Expected: FAIL — build error, `ProposedPlan` not found.

- [ ] **Step 3: Write minimal implementation**

`swift/DetDocCore/Sources/DetDocCore/Models/Plan.swift`
```swift
public struct PlanChange: Codable, Sendable, Equatable {
    public var reason: String
    public var targetFiles: [String]
    public var kind: String
    public var rationale: String
    public init(reason: String, targetFiles: [String], kind: String, rationale: String) {
        self.reason = reason
        self.targetFiles = targetFiles
        self.kind = kind
        self.rationale = rationale
    }
}

public struct ProposedPlan: Codable, Sendable, Equatable {
    public var summary: String
    public var changes: [PlanChange]
    public var questions: [String]
    public var risk: String

    public init(summary: String, changes: [PlanChange], questions: [String] = [], risk: String) {
        self.summary = summary
        self.changes = changes
        self.questions = questions
        self.risk = risk
    }

    enum CodingKeys: String, CodingKey { case summary, changes, questions, risk }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.summary = try c.decode(String.self, forKey: .summary)
        self.changes = try c.decode([PlanChange].self, forKey: .changes)
        self.questions = try c.decodeIfPresent([String].self, forKey: .questions) ?? []
        self.risk = try c.decode(String.self, forKey: .risk)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd swift/DetDocCore && swift test --filter PlanModelTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Models/Plan.swift swift/DetDocCore/Tests/DetDocCoreTests/PlanModelTests.swift
git commit -m "feat(core): add ProposedPlan and PlanChange models"
```

---

### Task 5: RunManifest

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Models/RunManifest.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/RunManifestTests.swift`

**Interfaces:**
- Consumes: `RunMode` (Task 3).
- Produces:
  - `struct RunManifest: Codable, Sendable, Equatable` with `runId: String`, `mode: RunMode`, `baseCommit: String`, `approvedTargets: [String]` (defaults `[]`), `preImageHashes: [String: String]` (defaults `[:]`). Both `approvedTargets` and `preImageHashes` decode to their empty default when absent.

- [ ] **Step 1: Write the failing test**

`swift/DetDocCore/Tests/DetDocCoreTests/RunManifestTests.swift`
```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func manifestDecodesLegacyWithoutOptionalFields() throws {
    let json = """
    { "runId": "20260620T101112Z-run-1a2b3c4d", "mode": "run", "baseCommit": "abc123" }
    """
    let manifest = try JSONDecoder().decode(RunManifest.self, from: Data(json.utf8))
    #expect(manifest.runId == "20260620T101112Z-run-1a2b3c4d")
    #expect(manifest.mode == .run)
    #expect(manifest.baseCommit == "abc123")
    #expect(manifest.approvedTargets == [])
    #expect(manifest.preImageHashes == [:])
}

@Test func manifestRoundTripsWithTargets() throws {
    let manifest = RunManifest(runId: "20260620T101112Z-fix-deadbeef", mode: .fix, baseCommit: "c0ffee", approvedTargets: ["src/a.ts"])
    let data = try JSONEncoder().encode(manifest)
    let decoded = try JSONDecoder().decode(RunManifest.self, from: data)
    #expect(decoded == manifest)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd swift/DetDocCore && swift test --filter RunManifestTests`
Expected: FAIL — build error, `RunManifest` not found.

- [ ] **Step 3: Write minimal implementation**

`swift/DetDocCore/Sources/DetDocCore/Models/RunManifest.swift`
```swift
public struct RunManifest: Codable, Sendable, Equatable {
    public var runId: String
    public var mode: RunMode
    public var baseCommit: String
    public var approvedTargets: [String]
    public var preImageHashes: [String: String]

    public init(
        runId: String,
        mode: RunMode,
        baseCommit: String,
        approvedTargets: [String] = [],
        preImageHashes: [String: String] = [:]
    ) {
        self.runId = runId
        self.mode = mode
        self.baseCommit = baseCommit
        self.approvedTargets = approvedTargets
        self.preImageHashes = preImageHashes
    }

    enum CodingKeys: String, CodingKey { case runId, mode, baseCommit, approvedTargets, preImageHashes }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.runId = try c.decode(String.self, forKey: .runId)
        self.mode = try c.decode(RunMode.self, forKey: .mode)
        self.baseCommit = try c.decode(String.self, forKey: .baseCommit)
        self.approvedTargets = try c.decodeIfPresent([String].self, forKey: .approvedTargets) ?? []
        self.preImageHashes = try c.decodeIfPresent([String: String].self, forKey: .preImageHashes) ?? [:]
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd swift/DetDocCore && swift test --filter RunManifestTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Models/RunManifest.swift swift/DetDocCore/Tests/DetDocCoreTests/RunManifestTests.swift
git commit -m "feat(core): add RunManifest with optional approvedTargets/preImageHashes"
```

---

### Task 6: Glob matcher

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Support/Glob.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/GlobTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct Glob: Sendable { init(_ pattern: String); func matches(_ path: String) -> Bool }`
  - `static func Glob.matchesAny(_ path: String, patterns: [String]) -> Bool`
  - Invalid patterns never match (compile failure → no match), matching the reference's "skip invalid globs" behavior.

- [ ] **Step 1: Write the failing test**

`swift/DetDocCore/Tests/DetDocCoreTests/GlobTests.swift`
```swift
import Testing
@testable import DetDocCore

@Test func globStarStarMatchesAcrossAndZeroDirectories() {
    #expect(Glob("**/*.md").matches("a.md"))
    #expect(Glob("**/*.md").matches("docs/x/a.md"))
    #expect(!Glob("**/*.md").matches("a.txt"))
}

@Test func globSingleStarDoesNotCrossSlash() {
    #expect(Glob("*.md").matches("a.md"))
    #expect(!Glob("*.md").matches("docs/a.md"))
}

@Test func globDirectorySuffixMatchesDescendants() {
    #expect(Glob(".detdoc/**").matches(".detdoc/config.yml"))
    #expect(Glob("node_modules/**").matches("node_modules/x/y.js"))
    #expect(!Glob("node_modules/**").matches("node_modules"))
}

@Test func globDotStarMatchesDottedSuffix() {
    #expect(Glob(".env.*").matches(".env.local"))
    #expect(!Glob(".env.*").matches(".env"))
    #expect(Glob(".env").matches(".env"))
}

@Test func globMatchesAnyAndInvalidNeverMatches() {
    #expect(Glob.matchesAny("src/a.ts", patterns: ["docs/**", "src/*.ts"]))
    #expect(!Glob.matchesAny("README", patterns: ["docs/**", "src/*.ts"]))
    #expect(!Glob("[").matches("anything"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd swift/DetDocCore && swift test --filter GlobTests`
Expected: FAIL — build error, `Glob` not found.

- [ ] **Step 3: Write minimal implementation**

`swift/DetDocCore/Sources/DetDocCore/Support/Glob.swift`
```swift
import Foundation

/// Translates a globset-compatible glob into an anchored regex.
/// Rules: `*` matches any run of non-`/`; `**` matches across `/`; a `**/`
/// segment also matches zero directories; `?` matches one non-`/` char.
public struct Glob: Sendable {
    private let regex: NSRegularExpression?

    public init(_ pattern: String) {
        self.regex = Glob.compile(pattern)
    }

    public func matches(_ path: String) -> Bool {
        guard let regex else { return false }
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        return regex.firstMatch(in: path, options: [], range: range) != nil
    }

    public static func matchesAny(_ path: String, patterns: [String]) -> Bool {
        patterns.contains { Glob($0).matches(path) }
    }

    private static func compile(_ pattern: String) -> NSRegularExpression? {
        let chars = Array(pattern)
        var out = "^"
        var i = 0
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "*":
                if i + 1 < chars.count, chars[i + 1] == "*" {
                    if i + 2 < chars.count, chars[i + 2] == "/" {
                        out += "(?:.*/)?"   // `**/` — zero or more directory segments
                        i += 3
                    } else {
                        out += ".*"         // `**` — any chars incl. `/`
                        i += 2
                    }
                } else {
                    out += "[^/]*"          // `*` — any chars except `/`
                    i += 1
                }
            case "?":
                out += "[^/]"
                i += 1
            case ".", "^", "$", "+", "(", ")", "[", "]", "{", "}", "|", "\\":
                out += "\\" + String(c)
                i += 1
            default:
                out += String(c)
                i += 1
            }
        }
        out += "$"
        return try? NSRegularExpression(pattern: out, options: [])
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd swift/DetDocCore && swift test --filter GlobTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Support/Glob.swift swift/DetDocCore/Tests/DetDocCoreTests/GlobTests.swift
git commit -m "feat(core): add globset-compatible Glob matcher"
```

---

### Task 7: Config models (DetDocConfig + ValidationCommand + defaults)

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Config/DetDocConfig.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/DetDocConfigTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces (all `Codable, Sendable, Equatable`):
  - `struct DocsConfig { var include: [String]; var exclude: [String] }`
  - `struct PathsConfig { var deny: [String] }`
  - `struct ValidationCommand { var name: String; var run: String }` — decodes from a bare string or an object with `run`/`command`/`cmd` (+ optional `name`); encodes as `{ name, run }`.
  - `struct ValidationConfig { var commands: [ValidationCommand] }`
  - `struct AgentConfig { var provider: String; var model: String?; var thinking: String }`
  - `struct WorktreeConfig { var keepOnFailure: Bool }`
  - `struct ApplyConfig { var autoCommit: Bool }`
  - `struct DetDocConfig { var docs; var paths; var validation; var agent; var worktree; var apply }`
  - `static let DetDocConfig.default: DetDocConfig` with the exact reference defaults.
  - All sub-configs decode missing keys to their defaults (matching serde `#[serde(default)]`).

- [ ] **Step 1: Write the failing test**

`swift/DetDocCore/Tests/DetDocCoreTests/DetDocConfigTests.swift`
```swift
import Foundation
import Testing
import Yams
@testable import DetDocCore

@Test func defaultConfigHasReferenceDefaults() {
    let c = DetDocConfig.default
    #expect(c.docs.include == ["**/*.md"])
    #expect(c.docs.exclude == [".detdoc/**", "node_modules/**"])
    #expect(c.paths.deny == [".env", ".env.*", "node_modules/**", ".git/**"])
    #expect(c.validation.commands.isEmpty)
    #expect(c.agent.provider == "pi-rpc")
    #expect(c.agent.model == nil)
    #expect(c.agent.thinking == "high")
    #expect(c.worktree.keepOnFailure == true)
    #expect(c.apply.autoCommit == true)
}

@Test func emptyYAMLMapDecodesToAllDefaults() throws {
    let decoded = try YAMLDecoder().decode(DetDocConfig.self, from: "{}")
    #expect(decoded == DetDocConfig.default)
}

@Test func validationCommandsAcceptStringAndObjectShapes() throws {
    let yaml = """
    validation:
      commands:
        - npm test
        - name: Build
          run: npm run build
        - command: npm run typecheck
        - cmd: swift test
    """
    let decoded = try YAMLDecoder().decode(DetDocConfig.self, from: yaml)
    #expect(decoded.validation.commands == [
        ValidationCommand(name: "npm test", run: "npm test"),
        ValidationCommand(name: "Build", run: "npm run build"),
        ValidationCommand(name: "npm run typecheck", run: "npm run typecheck"),
        ValidationCommand(name: "swift test", run: "swift test"),
    ])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd swift/DetDocCore && swift test --filter DetDocConfigTests`
Expected: FAIL — build error, config types not found.

- [ ] **Step 3: Write minimal implementation**

`swift/DetDocCore/Sources/DetDocCore/Config/DetDocConfig.swift`
```swift
public struct DocsConfig: Codable, Sendable, Equatable {
    public var include: [String]
    public var exclude: [String]
    public init(include: [String], exclude: [String]) {
        self.include = include
        self.exclude = exclude
    }
    enum CodingKeys: String, CodingKey { case include, exclude }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.include = try c.decodeIfPresent([String].self, forKey: .include) ?? ["**/*.md"]
        self.exclude = try c.decodeIfPresent([String].self, forKey: .exclude) ?? [".detdoc/**", "node_modules/**"]
    }
}

public struct PathsConfig: Codable, Sendable, Equatable {
    public var deny: [String]
    public init(deny: [String]) { self.deny = deny }
    enum CodingKeys: String, CodingKey { case deny }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.deny = try c.decodeIfPresent([String].self, forKey: .deny) ?? [".env", ".env.*", "node_modules/**", ".git/**"]
    }
}

public struct ValidationCommand: Codable, Sendable, Equatable {
    public var name: String
    public var run: String
    public init(name: String, run: String) {
        self.name = name
        self.run = run
    }
    enum CodingKeys: String, CodingKey { case name, run, command, cmd }
    public init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let raw = try? single.decode(String.self) {
            self.name = raw
            self.run = raw
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let run = try c.decodeIfPresent(String.self, forKey: .run)
            ?? c.decodeIfPresent(String.self, forKey: .command)
            ?? c.decode(String.self, forKey: .cmd)
        self.run = run
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? run
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(run, forKey: .run)
    }
}

public struct ValidationConfig: Codable, Sendable, Equatable {
    public var commands: [ValidationCommand]
    public init(commands: [ValidationCommand]) { self.commands = commands }
    enum CodingKeys: String, CodingKey { case commands }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.commands = try c.decodeIfPresent([ValidationCommand].self, forKey: .commands) ?? []
    }
}

public struct AgentConfig: Codable, Sendable, Equatable {
    public var provider: String
    public var model: String?
    public var thinking: String
    public init(provider: String, model: String?, thinking: String) {
        self.provider = provider
        self.model = model
        self.thinking = thinking
    }
    enum CodingKeys: String, CodingKey { case provider, model, thinking }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? "pi-rpc"
        self.model = try c.decodeIfPresent(String.self, forKey: .model)
        self.thinking = try c.decodeIfPresent(String.self, forKey: .thinking) ?? "high"
    }
}

public struct WorktreeConfig: Codable, Sendable, Equatable {
    public var keepOnFailure: Bool
    public init(keepOnFailure: Bool) { self.keepOnFailure = keepOnFailure }
    enum CodingKeys: String, CodingKey { case keepOnFailure }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.keepOnFailure = try c.decodeIfPresent(Bool.self, forKey: .keepOnFailure) ?? true
    }
}

public struct ApplyConfig: Codable, Sendable, Equatable {
    public var autoCommit: Bool
    public init(autoCommit: Bool) { self.autoCommit = autoCommit }
    enum CodingKeys: String, CodingKey { case autoCommit }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.autoCommit = try c.decodeIfPresent(Bool.self, forKey: .autoCommit) ?? true
    }
}

public struct DetDocConfig: Codable, Sendable, Equatable {
    public var docs: DocsConfig
    public var paths: PathsConfig
    public var validation: ValidationConfig
    public var agent: AgentConfig
    public var worktree: WorktreeConfig
    public var apply: ApplyConfig

    public init(
        docs: DocsConfig,
        paths: PathsConfig,
        validation: ValidationConfig,
        agent: AgentConfig,
        worktree: WorktreeConfig,
        apply: ApplyConfig
    ) {
        self.docs = docs
        self.paths = paths
        self.validation = validation
        self.agent = agent
        self.worktree = worktree
        self.apply = apply
    }

    enum CodingKeys: String, CodingKey { case docs, paths, validation, agent, worktree, apply }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.docs = try c.decodeIfPresent(DocsConfig.self, forKey: .docs) ?? DetDocConfig.default.docs
        self.paths = try c.decodeIfPresent(PathsConfig.self, forKey: .paths) ?? DetDocConfig.default.paths
        self.validation = try c.decodeIfPresent(ValidationConfig.self, forKey: .validation) ?? DetDocConfig.default.validation
        self.agent = try c.decodeIfPresent(AgentConfig.self, forKey: .agent) ?? DetDocConfig.default.agent
        self.worktree = try c.decodeIfPresent(WorktreeConfig.self, forKey: .worktree) ?? DetDocConfig.default.worktree
        self.apply = try c.decodeIfPresent(ApplyConfig.self, forKey: .apply) ?? DetDocConfig.default.apply
    }

    public static let `default` = DetDocConfig(
        docs: DocsConfig(include: ["**/*.md"], exclude: [".detdoc/**", "node_modules/**"]),
        paths: PathsConfig(deny: [".env", ".env.*", "node_modules/**", ".git/**"]),
        validation: ValidationConfig(commands: []),
        agent: AgentConfig(provider: "pi-rpc", model: nil, thinking: "high"),
        worktree: WorktreeConfig(keepOnFailure: true),
        apply: ApplyConfig(autoCommit: true)
    )
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd swift/DetDocCore && swift test --filter DetDocConfigTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Config/DetDocConfig.swift swift/DetDocCore/Tests/DetDocCoreTests/DetDocConfigTests.swift
git commit -m "feat(core): add DetDocConfig models with serde-parity defaults"
```

---

### Task 8: ConfigStore (load / default YAML / init files / gitignore)

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Config/ConfigStore.swift`
- Create: `swift/DetDocCore/Tests/DetDocCoreTests/Support/TempDir.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/ConfigStoreTests.swift`

**Interfaces:**
- Consumes: `DetDocConfig` (Task 7), `DetDocError` (Task 2), `Yams`.
- Produces:
  - `struct ConfigStore: Sendable { init() }`
  - `func configPath(root: URL) -> URL` → `<root>/.detdoc/config.yml`
  - `func defaultConfigYAML() throws -> String`
  - `func load(root: URL) throws -> DetDocConfig` (throws `CONFIG_READ_FAILED` / `CONFIG_PARSE_FAILED`)
  - `func writeDefault(root: URL) throws`
  - `func initFiles(root: URL) throws` — writes config, `.detdoc/runs/.gitkeep`, the six starter docs, and ensures `.gitignore` entries, each only if missing.
  - Test helper `TempDir` providing an auto-cleaned temporary directory `url`.

- [ ] **Step 1: Write the failing test**

`swift/DetDocCore/Tests/DetDocCoreTests/Support/TempDir.swift`
```swift
import Foundation

/// Creates a unique temporary directory and removes it on `deinit`.
final class TempDir {
    let url: URL
    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("detdoc-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
}
```

`swift/DetDocCore/Tests/DetDocCoreTests/ConfigStoreTests.swift`
```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func loadMissingConfigThrowsReadFailed() {
    let tmp = TempDir()
    #expect(throws: DetDocError.self) {
        try ConfigStore().load(root: tmp.url)
    }
}

@Test func initFilesWritesConfigGitkeepStarterDocsAndGitignore() throws {
    let tmp = TempDir()
    let store = ConfigStore()
    try store.initFiles(root: tmp.url)

    let fm = FileManager.default
    #expect(fm.fileExists(atPath: tmp.url.appendingPathComponent(".detdoc/config.yml").path))
    #expect(fm.fileExists(atPath: tmp.url.appendingPathComponent(".detdoc/runs/.gitkeep").path))
    #expect(fm.fileExists(atPath: tmp.url.appendingPathComponent("docs/idea.md").path))
    #expect(fm.fileExists(atPath: tmp.url.appendingPathComponent("docs/features/example-feature/brief.md").path))

    // config round-trips to defaults
    let loaded = try store.load(root: tmp.url)
    #expect(loaded == DetDocConfig.default)

    // gitignore contains the managed entries
    let gitignore = try String(contentsOf: tmp.url.appendingPathComponent(".gitignore"), encoding: .utf8)
    for entry in [".DS_Store", ".detdoc/runs/*", "!.detdoc/runs/.gitkeep", ".worktrees/"] {
        #expect(gitignore.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == entry })
    }
}

@Test func initFilesIsIdempotentAndPreservesEditedDocs() throws {
    let tmp = TempDir()
    let store = ConfigStore()
    try store.initFiles(root: tmp.url)
    let ideaURL = tmp.url.appendingPathComponent("docs/idea.md")
    try "EDITED".write(to: ideaURL, atomically: true, encoding: .utf8)

    try store.initFiles(root: tmp.url)  // second init must not overwrite
    let idea = try String(contentsOf: ideaURL, encoding: .utf8)
    #expect(idea == "EDITED")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd swift/DetDocCore && swift test --filter ConfigStoreTests`
Expected: FAIL — build error, `ConfigStore` not found.

- [ ] **Step 3: Write minimal implementation**

`swift/DetDocCore/Sources/DetDocCore/Config/ConfigStore.swift`
```swift
import Foundation
import Yams

public struct ConfigStore: Sendable {
    public init() {}

    public func configPath(root: URL) -> URL {
        root.appendingPathComponent(".detdoc").appendingPathComponent("config.yml")
    }

    public func defaultConfigYAML() throws -> String {
        do {
            return try YAMLEncoder().encode(DetDocConfig.default)
        } catch {
            throw DetDocError("CONFIG_SERIALIZE_FAILED", "\(error)")
        }
    }

    public func load(root: URL) throws -> DetDocConfig {
        let path = configPath(root: root)
        let content: String
        do {
            content = try String(contentsOf: path, encoding: .utf8)
        } catch {
            throw DetDocError("CONFIG_READ_FAILED", "\(path.path): \(error)")
        }
        do {
            return try YAMLDecoder().decode(DetDocConfig.self, from: content)
        } catch {
            throw DetDocError("CONFIG_PARSE_FAILED", "\(error)")
        }
    }

    public func writeDefault(root: URL) throws {
        try writeIfMissing(configPath(root: root), try defaultConfigYAML())
    }

    public func initFiles(root: URL) throws {
        try writeIfMissing(configPath(root: root), try defaultConfigYAML())
        try writeIfMissing(root.appendingPathComponent(".detdoc/runs/.gitkeep"), "")
        for (relativePath, content) in Self.starterDocs {
            try writeIfMissing(root.appendingPathComponent(relativePath), content)
        }
        try ensureGitignoreEntries(root: root)
    }

    static let starterDocs: [(String, String)] = [
        ("docs/idea.md", "# Project Idea\n\nDescribe the product in plain language.\n"),
        ("docs/technical-spec.md", "# Technical Specification\n\nKeep durable technical decisions here.\n"),
        ("docs/features/_guide.md", "# Feature Planning Guide\n\nUse this folder for free-form feature planning.\n"),
        ("docs/features/example-feature/brief.md", "# Example Feature Brief\n\n## Goal\n\nDescribe the user-visible behavior.\n"),
        ("docs/features/example-feature/plan.md", "# Example Feature Plan\n\nUse this file for free-form implementation planning.\n"),
        ("docs/features/example-feature/notes.md", "# Example Feature Notes\n\nUse this file for decisions and examples.\n"),
    ]

    private func writeIfMissing(_ url: URL, _ content: String) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { return }
        let parent = url.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            throw DetDocError("WRITE_DIR_FAILED", "\(error)")
        }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw DetDocError("WRITE_FILE_FAILED", "\(url.path): \(error)")
        }
    }

    private func ensureGitignoreEntries(root: URL) throws {
        let url = root.appendingPathComponent(".gitignore")
        var content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let entries = [".DS_Store", ".detdoc/runs/*", "!.detdoc/runs/.gitkeep", ".worktrees/"]
        for entry in entries where !content.split(separator: "\n", omittingEmptySubsequences: false)
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

- [ ] **Step 4: Run test to verify it passes**

Run: `cd swift/DetDocCore && swift test --filter ConfigStoreTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Config/ConfigStore.swift swift/DetDocCore/Tests/DetDocCoreTests/ConfigStoreTests.swift swift/DetDocCore/Tests/DetDocCoreTests/Support/TempDir.swift
git commit -m "feat(core): add ConfigStore with init scaffolding and gitignore management"
```

---

### Task 9: PathPolicy

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Services/PathPolicy.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/PathPolicyTests.swift`

**Interfaces:**
- Consumes: `DetDocConfig` (Task 7), `Glob` (Task 6).
- Produces:
  - `struct PathPolicy: Sendable { init(config: DetDocConfig) }`
  - `func isDenied(_ path: String) -> Bool`
  - `func isDoc(_ path: String) -> Bool` (include match AND not exclude match)

- [ ] **Step 1: Write the failing test**

`swift/DetDocCore/Tests/DetDocCoreTests/PathPolicyTests.swift`
```swift
import Testing
@testable import DetDocCore

@Test func deniedPathsMatchDenyGlobs() {
    let policy = PathPolicy(config: .default)
    #expect(policy.isDenied(".env"))
    #expect(policy.isDenied(".env.local"))
    #expect(policy.isDenied("node_modules/react/index.js"))
    #expect(policy.isDenied(".git/config"))
    #expect(!policy.isDenied("src/app.ts"))
}

@Test func docPathsAreIncludedAndNotExcluded() {
    let policy = PathPolicy(config: .default)
    #expect(policy.isDoc("docs/idea.md"))
    #expect(policy.isDoc("README.md"))
    #expect(!policy.isDoc(".detdoc/notes.md"))    // excluded by .detdoc/**
    #expect(!policy.isDoc("src/app.ts"))           // not a .md
    #expect(!policy.isDoc(".detdoc/config.yml"))   // not a .md, allowed as a target
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd swift/DetDocCore && swift test --filter PathPolicyTests`
Expected: FAIL — build error, `PathPolicy` not found.

- [ ] **Step 3: Write minimal implementation**

`swift/DetDocCore/Sources/DetDocCore/Services/PathPolicy.swift`
```swift
public struct PathPolicy: Sendable {
    private let config: DetDocConfig

    public init(config: DetDocConfig) {
        self.config = config
    }

    public func isDenied(_ path: String) -> Bool {
        Glob.matchesAny(path, patterns: config.paths.deny)
    }

    public func isDoc(_ path: String) -> Bool {
        Glob.matchesAny(path, patterns: config.docs.include)
            && !Glob.matchesAny(path, patterns: config.docs.exclude)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd swift/DetDocCore && swift test --filter PathPolicyTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Services/PathPolicy.swift swift/DetDocCore/Tests/DetDocCoreTests/PathPolicyTests.swift
git commit -m "feat(core): add PathPolicy (denied/doc path classification)"
```

---

### Task 10: ArtifactStore

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Services/ArtifactStore.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/ArtifactStoreTests.swift`

**Interfaces:**
- Consumes: `RunManifest` (Task 5), `DetDocError` (Task 2).
- Produces:
  - `struct ArtifactStore: Sendable { init(projectRoot: URL) }`
  - `func runDir(_ runId: String) -> URL` → `<root>/.detdoc/runs/<runId>`
  - `func createRun(_ manifest: RunManifest) throws` (mkdir + write `manifest.json`)
  - `func writeJSON<T: Encodable>(_ runId: String, _ name: String, _ value: T) throws` (pretty + trailing `\n`)
  - `func readJSON<T: Decodable>(_ type: T.Type, _ runId: String, _ name: String) throws -> T`
  - `func writeText(_ runId: String, _ name: String, _ content: String) throws`
  - `func readText(_ runId: String, _ name: String) throws -> String`
  - `func deleteRun(_ runId: String) throws`

- [ ] **Step 1: Write the failing test**

`swift/DetDocCore/Tests/DetDocCoreTests/ArtifactStoreTests.swift`
```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func createRunWritesManifestThatReadsBack() throws {
    let tmp = TempDir()
    let store = ArtifactStore(projectRoot: tmp.url)
    let manifest = RunManifest(runId: "20260620T101112Z-run-1a2b3c4d", mode: .run, baseCommit: "abc123", approvedTargets: ["src/a.ts"])

    try store.createRun(manifest)

    let manifestURL = store.runDir(manifest.runId).appendingPathComponent("manifest.json")
    #expect(FileManager.default.fileExists(atPath: manifestURL.path))
    let raw = try String(contentsOf: manifestURL, encoding: .utf8)
    #expect(raw.hasSuffix("\n"))  // pretty JSON + trailing newline

    let readBack: RunManifest = try store.readJSON(RunManifest.self, manifest.runId, "manifest.json")
    #expect(readBack == manifest)
}

@Test func writeAndReadTextRoundTrips() throws {
    let tmp = TempDir()
    let store = ArtifactStore(projectRoot: tmp.url)
    let manifest = RunManifest(runId: "r1", mode: .fix, baseCommit: "h")
    try store.createRun(manifest)
    try store.writeText("r1", "changes.patch", "diff --git a/x b/x\n")
    #expect(try store.readText("r1", "changes.patch") == "diff --git a/x b/x\n")
}

@Test func deleteRunRemovesDirectory() throws {
    let tmp = TempDir()
    let store = ArtifactStore(projectRoot: tmp.url)
    try store.createRun(RunManifest(runId: "r2", mode: .run, baseCommit: "h"))
    try store.deleteRun("r2")
    #expect(!FileManager.default.fileExists(atPath: store.runDir("r2").path))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd swift/DetDocCore && swift test --filter ArtifactStoreTests`
Expected: FAIL — build error, `ArtifactStore` not found.

- [ ] **Step 3: Write minimal implementation**

`swift/DetDocCore/Sources/DetDocCore/Services/ArtifactStore.swift`
```swift
import Foundation

public struct ArtifactStore: Sendable {
    private let root: URL

    public init(projectRoot: URL) {
        self.root = projectRoot.appendingPathComponent(".detdoc/runs")
    }

    public func runDir(_ runId: String) -> URL {
        root.appendingPathComponent(runId)
    }

    public func createRun(_ manifest: RunManifest) throws {
        do {
            try FileManager.default.createDirectory(at: runDir(manifest.runId), withIntermediateDirectories: true)
        } catch {
            throw DetDocError("ARTIFACT_DIR_FAILED", "\(error)")
        }
        try writeJSON(manifest.runId, "manifest.json", manifest)
    }

    public func writeJSON<T: Encodable>(_ runId: String, _ name: String, _ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw DetDocError("ARTIFACT_JSON_FAILED", "\(error)")
        }
        let text = String(decoding: data, as: UTF8.self) + "\n"
        try writeText(runId, name, text)
    }

    public func readJSON<T: Decodable>(_ type: T.Type, _ runId: String, _ name: String) throws -> T {
        let text = try readText(runId, name)
        do {
            return try JSONDecoder().decode(T.self, from: Data(text.utf8))
        } catch {
            throw DetDocError("ARTIFACT_PARSE_FAILED", "\(error)")
        }
    }

    public func writeText(_ runId: String, _ name: String, _ content: String) throws {
        let url = runDir(runId).appendingPathComponent(name)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw DetDocError("ARTIFACT_WRITE_FAILED", "\(error)")
        }
    }

    public func readText(_ runId: String, _ name: String) throws -> String {
        let url = runDir(runId).appendingPathComponent(name)
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw DetDocError("ARTIFACT_READ_FAILED", "\(error)")
        }
    }

    public func deleteRun(_ runId: String) throws {
        do {
            try FileManager.default.removeItem(at: runDir(runId))
        } catch {
            throw DetDocError("ARTIFACT_DELETE_FAILED", "\(error)")
        }
    }
}
```

> Parity note: the reference uses `serde_json::to_string_pretty` (struct field order). Swift's `.sortedKeys` produces key-sorted pretty JSON instead. Both are valid JSON with identical field names and are read back by key, so functional parity holds; byte-for-byte order is intentionally not asserted.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd swift/DetDocCore && swift test --filter ArtifactStoreTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Services/ArtifactStore.swift swift/DetDocCore/Tests/DetDocCoreTests/ArtifactStoreTests.swift
git commit -m "feat(core): add ArtifactStore for .detdoc/runs artifacts"
```

---

### Task 11: RunID

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Support/RunID.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/RunIDTests.swift`

**Interfaces:**
- Consumes: `RunMode` (Task 3).
- Produces:
  - `enum RunID { static func create(mode: RunMode, now: Date = Date(), uuid: UUID = UUID()) -> String }`
  - Format: `"{yyyyMMdd'T'HHmmss'Z'}-{run|fix}-{first 8 lowercase hex of uuid}"`, timestamp in UTC.

- [ ] **Step 1: Write the failing test**

`swift/DetDocCore/Tests/DetDocCoreTests/RunIDTests.swift`
```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func runIdHasTimestampModeAndHexSuffix() {
    let date = Date(timeIntervalSince1970: 1_750_000_000)  // fixed instant
    let uuid = UUID(uuidString: "1A2B3C4D-0000-0000-0000-000000000000")!
    let id = RunID.create(mode: .run, now: date, uuid: uuid)
    #expect(id.hasSuffix("-run-1a2b3c4d"))
    #expect(id.range(of: #"^\d{8}T\d{6}Z-run-[0-9a-f]{8}$"#, options: .regularExpression) != nil)
}

@Test func runIdUsesFixPrefixForFixMode() {
    let id = RunID.create(mode: .fix)
    #expect(id.range(of: #"^\d{8}T\d{6}Z-fix-[0-9a-f]{8}$"#, options: .regularExpression) != nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd swift/DetDocCore && swift test --filter RunIDTests`
Expected: FAIL — build error, `RunID` not found.

- [ ] **Step 3: Write minimal implementation**

`swift/DetDocCore/Sources/DetDocCore/Support/RunID.swift`
```swift
import Foundation

public enum RunID {
    public static func create(mode: RunMode, now: Date = Date(), uuid: UUID = UUID()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let timestamp = formatter.string(from: now)
        let prefix = mode == .run ? "run" : "fix"
        let hex = uuid.uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
            .prefix(8)
        return "\(timestamp)-\(prefix)-\(hex)"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd swift/DetDocCore && swift test --filter RunIDTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Support/RunID.swift swift/DetDocCore/Tests/DetDocCoreTests/RunIDTests.swift
git commit -m "feat(core): add RunID generator matching reference format"
```

---

### Task 12: PlanValidator

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Services/PlanValidator.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/PlanValidatorTests.swift`

**Interfaces:**
- Consumes: `ProposedPlan`/`PlanChange` (Task 4), `RunMode` (Task 3), `DetDocConfig` (Task 7), `PathPolicy` (Task 9), `DetDocError` (Task 2).
- Produces:
  - `enum PlanValidator`
  - `static func validate(_ plan: ProposedPlan, config: DetDocConfig, mode: RunMode) throws -> ProposedPlan`
  - `static func approvedTargets(from plan: ProposedPlan) -> [String]` (sorted, de-duplicated)
  - Error codes (verbatim): `PLAN_EMPTY`, `PLAN_RISK_INVALID`, `PLAN_KIND_INVALID`, `PLAN_CHANGE_NO_TARGETS`, `PLAN_REASON_INVALID`, `PLAN_TARGET_DENIED`, `PLAN_TARGETS_DOC`.

- [ ] **Step 1: Write the failing test**

`swift/DetDocCore/Tests/DetDocCoreTests/PlanValidatorTests.swift`
```swift
import Testing
@testable import DetDocCore

private func change(_ reason: String, _ targets: [String], kind: String = "modify") -> PlanChange {
    PlanChange(reason: reason, targetFiles: targets, kind: kind, rationale: "because")
}

private func plan(_ changes: [PlanChange], risk: String = "low") -> ProposedPlan {
    ProposedPlan(summary: "s", changes: changes, risk: risk)
}

@Test func validRunPlanPasses() throws {
    let p = plan([change("doc-diff:docs/spec.md:L1-L2", ["src/app.ts"])])
    let out = try PlanValidator.validate(p, config: .default, mode: .run)
    #expect(out == p)
}

@Test func emptyChangesIsRejected() {
    let p = ProposedPlan(summary: "s", changes: [], risk: "low")
    #expect { try PlanValidator.validate(p, config: .default, mode: .run) }
        throws: { ($0 as? DetDocError)?.code == "PLAN_EMPTY" }
}

@Test func invalidRiskIsRejected() {
    let p = plan([change("doc-diff:x", ["src/a.ts"])], risk: "extreme")
    #expect { try PlanValidator.validate(p, config: .default, mode: .run) }
        throws: { ($0 as? DetDocError)?.code == "PLAN_RISK_INVALID" }
}

@Test func invalidKindIsRejected() {
    let p = plan([change("doc-diff:x", ["src/a.ts"], kind: "refactor")])
    #expect { try PlanValidator.validate(p, config: .default, mode: .run) }
        throws: { ($0 as? DetDocError)?.code == "PLAN_KIND_INVALID" }
}

@Test func emptyTargetsIsRejected() {
    let p = plan([change("doc-diff:x", [])])
    #expect { try PlanValidator.validate(p, config: .default, mode: .run) }
        throws: { ($0 as? DetDocError)?.code == "PLAN_CHANGE_NO_TARGETS" }
}

@Test func runReasonMustStartWithDocDiff() {
    let p = plan([change("intent:fix", ["src/a.ts"])])
    #expect { try PlanValidator.validate(p, config: .default, mode: .run) }
        throws: { ($0 as? DetDocError)?.code == "PLAN_REASON_INVALID" }
}

@Test func fixReasonMustStartWithIntent() {
    let p = plan([change("doc-diff:x", ["src/a.ts"])])
    #expect { try PlanValidator.validate(p, config: .default, mode: .fix) }
        throws: { ($0 as? DetDocError)?.code == "PLAN_REASON_INVALID" }
}

@Test func deniedTargetIsRejected() {
    let p = plan([change("doc-diff:x", [".env"])])
    #expect { try PlanValidator.validate(p, config: .default, mode: .run) }
        throws: { ($0 as? DetDocError)?.code == "PLAN_TARGET_DENIED" }
}

@Test func docTargetIsRejected() {
    let p = plan([change("doc-diff:x", ["docs/idea.md"])])
    #expect { try PlanValidator.validate(p, config: .default, mode: .run) }
        throws: { ($0 as? DetDocError)?.code == "PLAN_TARGETS_DOC" }
}

@Test func approvedTargetsAreSortedAndDeduplicated() {
    let p = plan([
        change("doc-diff:x", ["src/b.ts", "src/a.ts"]),
        change("doc-diff:y", ["src/a.ts"]),
    ])
    #expect(PlanValidator.approvedTargets(from: p) == ["src/a.ts", "src/b.ts"])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd swift/DetDocCore && swift test --filter PlanValidatorTests`
Expected: FAIL — build error, `PlanValidator` not found.

- [ ] **Step 3: Write minimal implementation**

`swift/DetDocCore/Sources/DetDocCore/Services/PlanValidator.swift`
```swift
public enum PlanValidator {
    private static let validKinds: Set<String> = ["create", "modify", "delete", "rename"]
    private static let validRisks: Set<String> = ["low", "medium", "high"]

    public static func validate(_ plan: ProposedPlan, config: DetDocConfig, mode: RunMode) throws -> ProposedPlan {
        if plan.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || plan.changes.isEmpty {
            throw DetDocError("PLAN_EMPTY", "Plan summary and changes are required")
        }
        if !validRisks.contains(plan.risk) {
            throw DetDocError("PLAN_RISK_INVALID", "Invalid risk: \(plan.risk)")
        }
        let policy = PathPolicy(config: config)
        for change in plan.changes {
            if !validKinds.contains(change.kind) {
                throw DetDocError("PLAN_KIND_INVALID", "Invalid change kind: \(change.kind)")
            }
            if change.targetFiles.isEmpty {
                throw DetDocError("PLAN_CHANGE_NO_TARGETS", "plan change must list at least one target file")
            }
            switch mode {
            case .run where !change.reason.hasPrefix("doc-diff:"):
                throw DetDocError("PLAN_REASON_INVALID", "run plan change must use doc-diff reason: \(change.reason)")
            case .fix where !change.reason.hasPrefix("intent:"):
                throw DetDocError("PLAN_REASON_INVALID", "fix plan change must use intent reason: \(change.reason)")
            default:
                break
            }
            for target in change.targetFiles {
                if policy.isDenied(target) {
                    throw DetDocError("PLAN_TARGET_DENIED", "plan targets denied path: \(target)")
                }
                if policy.isDoc(target) {
                    throw DetDocError("PLAN_TARGETS_DOC", "plans must not target documentation files: \(target)")
                }
            }
        }
        return plan
    }

    public static func approvedTargets(from plan: ProposedPlan) -> [String] {
        var set = Set<String>()
        for change in plan.changes { set.formUnion(change.targetFiles) }
        return set.sorted()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd swift/DetDocCore && swift test --filter PlanValidatorTests`
Expected: PASS (10 tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Services/PlanValidator.swift swift/DetDocCore/Tests/DetDocCoreTests/PlanValidatorTests.swift
git commit -m "feat(core): add PlanValidator with reference parity rules"
```

---

### Task 13: PatchValidator

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Services/PatchValidator.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/PatchValidatorTests.swift`

**Interfaces:**
- Consumes: `DetDocConfig` (Task 7), `PathPolicy` (Task 9), `DetDocError` (Task 2).
- Produces:
  - `enum PatchValidator`
  - `static func validatePaths(_ patch: String, approvedTargets: [String], config: DetDocConfig) throws`
  - Inspects only lines starting with `+++ b/` or `--- a/`; path is the text after the 6-char prefix; `/dev/null` is skipped.
  - Error codes (verbatim): `PATCH_DENIED_PATH`, `PATCH_DOC_PATH`, `PATCH_UNAPPROVED_PATH`.

- [ ] **Step 1: Write the failing test**

`swift/DetDocCore/Tests/DetDocCoreTests/PatchValidatorTests.swift`
```swift
import Testing
@testable import DetDocCore

@Test func patchTouchingOnlyApprovedTargetsPasses() throws {
    let patch = """
    diff --git a/src/app.ts b/src/app.ts
    --- a/src/app.ts
    +++ b/src/app.ts
    @@ -1 +1 @@
    -old
    +new
    """
    try PatchValidator.validatePaths(patch, approvedTargets: ["src/app.ts"], config: .default)
}

@Test func newFileAgainstDevNullIsAllowedWhenApproved() throws {
    let patch = """
    diff --git a/src/new.ts b/src/new.ts
    --- /dev/null
    +++ b/src/new.ts
    @@ -0,0 +1 @@
    +created
    """
    try PatchValidator.validatePaths(patch, approvedTargets: ["src/new.ts"], config: .default)
}

@Test func unapprovedPathIsRejected() {
    let patch = """
    --- a/src/other.ts
    +++ b/src/other.ts
    """
    #expect { try PatchValidator.validatePaths(patch, approvedTargets: ["src/app.ts"], config: .default) }
        throws: { ($0 as? DetDocError)?.code == "PATCH_UNAPPROVED_PATH" }
}

@Test func deniedPathIsRejected() {
    let patch = """
    --- a/.env
    +++ b/.env
    """
    #expect { try PatchValidator.validatePaths(patch, approvedTargets: [".env"], config: .default) }
        throws: { ($0 as? DetDocError)?.code == "PATCH_DENIED_PATH" }
}

@Test func docPathIsRejected() {
    let patch = """
    --- a/docs/idea.md
    +++ b/docs/idea.md
    """
    #expect { try PatchValidator.validatePaths(patch, approvedTargets: ["docs/idea.md"], config: .default) }
        throws: { ($0 as? DetDocError)?.code == "PATCH_DOC_PATH" }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd swift/DetDocCore && swift test --filter PatchValidatorTests`
Expected: FAIL — build error, `PatchValidator` not found.

- [ ] **Step 3: Write minimal implementation**

`swift/DetDocCore/Sources/DetDocCore/Services/PatchValidator.swift`
```swift
public enum PatchValidator {
    public static func validatePaths(_ patch: String, approvedTargets: [String], config: DetDocConfig) throws {
        let policy = PathPolicy(config: config)
        for line in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            guard text.hasPrefix("+++ b/") || text.hasPrefix("--- a/") else { continue }
            let path = String(text.dropFirst(6))
            if path == "/dev/null" { continue }
            if policy.isDenied(path) { throw DetDocError("PATCH_DENIED_PATH", path) }
            if policy.isDoc(path) { throw DetDocError("PATCH_DOC_PATH", path) }
            if !approvedTargets.contains(path) { throw DetDocError("PATCH_UNAPPROVED_PATH", path) }
        }
    }
}
```

> Parity note: the reference matches the 6-char prefixes `"+++ b/"` / `"--- a/"` and slices `line[6..]`. The `--- /dev/null` line does not start with `--- a/`, so it is never inspected; only the `+++ b/...` side of a new file is checked (and skipped when it is `/dev/null`).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd swift/DetDocCore && swift test --filter PatchValidatorTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Services/PatchValidator.swift swift/DetDocCore/Tests/DetDocCoreTests/PatchValidatorTests.swift
git commit -m "feat(core): add PatchValidator path-policy enforcement"
```

---

### Task 14: Full-suite green gate

**Files:**
- Modify: none (verification only).

**Interfaces:**
- Consumes: every prior task.
- Produces: a confirmed all-green `DetDocCore` foundation.

- [ ] **Step 1: Run the entire test suite**

Run: `cd swift/DetDocCore && swift test`
Expected: PASS — all tests from Tasks 1–13 (no failures, no skips).

- [ ] **Step 2: Confirm a clean build with warnings surfaced**

Run: `cd swift/DetDocCore && swift build -Xswiftc -warnings-as-errors`
Expected: build succeeds with no warnings. If a warning appears, fix it (do not suppress) and re-run.

- [ ] **Step 3: Commit any fixes**

```bash
git add -A swift/DetDocCore
git commit -m "test(core): green gate for DetDocCore foundation" --allow-empty
```

---

## Self-Review

**1. Spec coverage (foundation slice of `docs/superpowers/specs/2026-06-20-detdoc-gui-swift-rewrite-design.md`):**
- DetDocCore module layout → Task 1. ✓
- Domain models (`DetDocConfig`, `ProposedPlan`/`PlanChange`, `RunManifest` incl. preimage hashes, `RunMode`, `ProjectStatus`/`DirtyFile`, `DocFile`, `RunSummary`, `RunFlowResult`, `TokenUsage`, `DetDocError`) → Tasks 2–5, 7. ✓ (`RunEvent` belongs to the engine — deferred to Plan 2, noted below.)
- `ConfigStore` (read/init/gitignore) → Task 8. ✓
- `PathPolicy` (isDenied/isDoc, glob) → Tasks 6, 9. ✓
- `ArtifactStore` → Task 10. ✓
- `PlanValidator` / `PatchValidator` → Tasks 12, 13. ✓
- Run-id format → Task 11. ✓
- Yams as the only external core dependency → Task 1. ✓
- Out of scope for this plan (correctly, per the subsystem split): `GitRepository`, `WorktreeManager`, `DocsService`, `DocDiff`, `ValidationRunner`, `AgentRunner`/`FakeAgentRunner`, `DetDocEngine`/`RunEvent`, `PiHealth`/`PiAgentRunner`, and the entire `DetDocApp` MVVM+C layer. These are Plans 2–4.

**2. Placeholder scan:** No `TBD`/`TODO`/"handle edge cases"/"similar to Task N". Every code step shows full code; every test step shows full test code. ✓

**3. Type consistency:** `RunMode` (`.run`/`.fix`) consistent across Tasks 3/5/11/12. `DetDocConfig.default` defined in Task 7 and reused in Tasks 8/9/12/13. `PathPolicy(config:)` signature consistent in Tasks 9/12/13. `DetDocError(_:_:)` convenience init used uniformly. `ArtifactStore.readJSON(_:_:_:)` signature matches its call in the test. ✓

---

## Next Plans (roadmap, not part of this plan)

- **Plan 2 — DetDocCore process/git/flow:** `GitRepository` (Process shell-out, TS git semantics), `WorktreeManager`, `DocsService`, `DocDiff`, `ValidationRunner`, `AgentRunner`+`FakeAgentRunner`, `DetDocEngine` (`AsyncThrowingStream<RunEvent>` + approval gates), `PiHealth`. Git-fixture + flow tests.
- **Plan 3 — DetDocApp:** XcodeGen project, MVVM+C, `NavigationSplitView` + `.inspector`, docs explorer/editor (source+preview), run/fix panel, plan/patch review, runs, settings, onboarding.
- **Plan 4 — PiAgentRunner:** pin the `pi --mode rpc` JSONL wire schema; real planning/implementation/repair.

---

## Post-implementation corrections (applied during execution)

These supersede the corresponding text above; the implemented code reflects them.

1. **Glob semantics (Task 6 + Reference Parity Facts) — corrected.** The Rust reference uses
   `globset` with its default `literal_separator = false`, where **`*` and `?` match across `/`**
   (verified empirically against `globset` 0.4 via `Glob::regex`). The earlier "Reference Parity
   Facts" bullet wrongly described picomatch/TS semantics (`*` not crossing `/`). The shipped
   `Glob.compile` therefore emits `*` → `.*` and `?` → `.` (not `[^/]*` / `[^/]`); `**/` →
   `(?:.*/)?` and bare `**` → `.*` are unchanged. `GlobTests` assert the globset behavior
   (`*.md` matches `docs/a.md`; `.env.*` matches `.env.config/leaked`; `secrets/*` matches
   `secrets/sub/key`; `a?c` matches `a/c`). This keeps `PathPolicy` fail-closed and at parity
   with the Rust deny/doc checks.
2. **Package.swift (Task 1) — `swift-tools-version` is `6.4`, not `6.0`** (`.macOS(.v27)` requires
   PackageDescription 6.4+). The `DetDocCore` target carries
   `swiftSettings: [.treatAllWarnings(as: .error)]` as the warnings gate.
3. **Warnings gate (Task 14 Step 2) — corrected.** `swift build -Xswiftc -warnings-as-errors` is
   unrunnable here: the global flag conflicts with the `-suppress-warnings` SwiftPM applies to the
   Yams dependency. The gate is instead the per-target `treatAllWarnings(as: .error)` above, plus
   `swift test`. (To spot-check warnings ad hoc: `swift package clean && swift build 2>&1 | grep -i 'warning:'`.)
4. **Test filtering note.** Swift Testing's `swift test --filter <X>` matches `@Test` function /
   `@Suite` names, not file/struct names, so the per-task `--filter <TestsFileName>` commands print
   "no matching tests". RED is confirmed by the build error; GREEN by a full `swift test`.

Final state: full suite **42 tests green**, clean warnings-gated build, final whole-branch review
clean after the C1 fix.
