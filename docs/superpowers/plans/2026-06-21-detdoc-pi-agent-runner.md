# DetDocCore Pi Agent Runner Implementation Plan (Plan 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `PiAgentRunner` — the real `AgentRunner` that drives the installed `pi` binary as a subprocess over strict LF-delimited JSONL (`pi --mode rpc`), replacing `FakeAgentRunner` in the running app while keeping the fake for offline/tests. Implements the two-phase DetDoc protocol (read-only planning → scoped implementation) with validation-repair support, fully tested headless via an injected transport.

**Architecture:** A new `Agent/PiRpc/` group inside `DetDocCore`. The RPC concern is split into pure, unit-testable pieces (JSONL codec, event/message decoding, prompt builders, plan/usage parsing) and one I/O piece (`PiProcessTransport`) hidden behind a `PiRpcTransport` protocol. `PiAgentRunner` composes them: it builds spawn args + prompts, sends `set_thinking_level` then `prompt`, consumes events until `agent_end`, and extracts the plan (planning) or just token usage (implement/repair). Tests inject a `FakePiTransport` (canned JSONL) so the whole runner is verifiable without `pi`; one integration test exercises the real `PiProcessTransport` against a fake-`pi` shell script through a real pipe.

**Tech Stack:** Swift 6.4, SwiftPM, Swift Testing, Foundation (`Process`, `Pipe`, `FileHandle`, `JSONEncoder`/`JSONDecoder`), `DetDocCore` (existing), XcodeGen + `xcodebuild` (app wiring only).

## Global Constraints

- Platform floor **macOS 27**; **pure Swift**; tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`/`#require`). No XCTest.
- `DetDocCore` stays **UI-agnostic** (no SwiftUI/AppKit); the only external runtime dependency remains **Yams**. `PiAgentRunner` adds **no** new dependency (no JS artifact, no pi SDK).
- The `DetDocCore` target keeps `swiftSettings: [.treatAllWarnings(as: .error)]` — all new source must be warning-clean.
- All public types are `Sendable`; serialized models are `Codable`. `PiAgentRunner` conforms to the existing `AgentRunner` protocol unchanged (do not modify the protocol).
- Preserve on-disk artifact/config field names & shapes; plan JSON keys match `ProposedPlan`/`PlanChange` exactly (`summary`, `changes`, `targetFiles`, `kind`, `rationale`, `questions`, `risk`).
- Stable `DetDocError` codes (new ones introduced here, listed per task): `PI_RPC_UTF8_INVALID` (parity with Rust `pi_rpc.rs`), `PI_RPC_ENCODE_FAILED`, `PI_RPC_SPAWN_FAILED`, `PI_RPC_WRITE_FAILED`, `PI_RPC_COMMAND_FAILED`, `PI_RPC_NO_RESULT`, `PI_PLAN_PARSE_FAILED`.
- Construct errors with the existing 2-arg initializer `DetDocError("CODE", "message")` (as `ProcessRunner` does).
- Run core tests from `swift/DetDocCore` with `swift test`; run the app build from `swift/DetDocApp` with the XcodeGen + `xcodebuild` line in Task 8.
- Swift Testing's `--filter` matches `@Test`/`@Suite` names, **not file names**. The per-task `--filter <File>Tests` commands below are shorthand for "run this task's new tests"; if a name filter returns no tests, run plain `swift test` (fast once the package is built/cached) — the compile-fail-then-pass expectations hold either way.

## Key Decision (pinning the uncertain module)

The design spec leaves the exact `pi --mode rpc` wire schema "pinned during implementation" and the reference `src-tauri/src/detdoc/pi_rpc.rs` is a stub (only `check_pi_available` + `split_jsonl_records`). Two ways exist to get a structured plan back from pi:

1. Inject a `submit_plan` **custom tool** via a `pi -e <extension>` file and read its args from `tool_execution_*` events.
2. Instruct pi to **emit the plan as a single JSON object in its final assistant text** and parse it.

**This plan pins option 2.** `pi --mode rpc` has no command to register a custom tool, so option 1 would force a JavaScript/TypeScript extension artifact into a pure-Swift app — a cross-language dependency for the one module the design says to keep isolated. Option 2 needs no extra artifact, is the path the TS runner already falls back to (`pi-sdk-runner.ts:262-263` parses `extractLastAssistantText` as JSON when no tool fired), and keeps everything testable in Swift. Implementation/repair phases need no structured return at all — pi edits files in the worktree and the engine collects the patch via git afterward (`PatchCollector`), so those phases only extract token usage. The planning prompt is therefore **adapted** from the verbatim TS prompt (the "call submit_plan" lines become "output a single JSON object"); the implementation and repair prompts are ported **verbatim**.

## Pinned pi RPC Wire Schema (Reference Parity Facts)

Verbatim from `node_modules/@earendil-works/pi-coding-agent/docs/rpc.md`, `src/core/agent/pi-sdk-runner.ts`, and `src-tauri/src/detdoc/pi_rpc.rs`:

- **Spawn:** `pi --mode rpc --no-session --tools <csv>` with `cwd` = the run worktree path. Append `--model <pattern>` only when `config.agent.model` is non-nil/non-empty. Do **not** pass `--provider` (DetDoc's `agent.provider` selects the runner, not pi's provider; the TS runner sets neither provider nor model and relies on pi's default). Tool sets: planning `read,grep,find,ls`; implementation/repair `read,grep,find,ls,bash,edit,write` (`--tools` is the documented narrowing flag; defense-in-depth — safety is still enforced by worktree isolation + `PatchValidator`).
- **Framing:** strict JSONL — split records on `\n` **only**, strip a trailing `\r`, drop empty records, preserve `U+2028`/`U+2029` inside JSON strings (parity with Rust `split_jsonl_records`). Commands are one JSON object per line on stdin; events/responses are one JSON object per line on stdout.
- **Commands sent (in order):** `{"type":"set_thinking_level","level":"<high|…>"}` then `{"id":"…","type":"prompt","message":"<built prompt>"}`. Levels: `off|minimal|low|medium|high|xhigh`.
- **Responses:** `{"type":"response","command":"<cmd>","success":<bool>,"error":"<msg?>","id":"<echoed?>"}`. `prompt` with `success:false` ⇒ rejected before acceptance.
- **Events (stdout, no `id`):** discriminated by `type`. Relevant ones: `agent_start`; `tool_execution_start` `{toolName, args:{path?,command?}}`; `agent_end` `{messages:[AssistantMessage…]}` (terminal — contains all messages for the run). All other types (`turn_*`, `message_*`, `queue_update`, `compaction_*`, `auto_retry_*`, `extension_error`) are ignored by DetDoc.
- **AssistantMessage:** `{role:"assistant", content: String | [{type,text?}…], usage?:{input,output,cacheRead,cacheWrite,cost?}, …}`. Token usage is summed across assistant messages; `total` is computed as `input+output+cacheRead+cacheWrite` (the wire has no `total`).
- **Plan extraction:** the last `assistant` message's concatenated text is parsed as a JSON `ProposedPlan` (tolerating surrounding prose/code fences by slicing from first `{` to last `}`). The **engine** validates the plan (`PlanValidator.validate` in `DetDocEngine`), so the runner only parses.
- **Patches are never sent over RPC:** pi writes files directly in the worktree; `DetDocEngine`/`PatchCollector` produce `changes.patch` with git afterward.

## File Structure

- Create: `swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiRpcCodec.swift` — JSONL split + command encode (pure).
- Create: `swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiRpcEvent.swift` — `PiRpcEvent`/`PiRpcMessage`/`PiRpcUsage` + decoding (pure).
- Create: `swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiAgentPrompts.swift` — planning/implementation/repair prompt builders (pure).
- Create: `swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiPlanParsing.swift` — plan + token-usage extraction (pure).
- Create: `swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiRpcTransport.swift` — `PiRpcTransport` protocol (pure interface).
- Create: `swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiProcessTransport.swift` — live `pi --mode rpc` subprocess (I/O).
- Create: `swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiAgentRunner.swift` — the `AgentRunner` conformance.
- Create: `swift/DetDocCore/Sources/DetDocCore/Agent/AgentRunnerFactory.swift` — runner selection by `config.agent.provider`.
- Modify: `swift/DetDocCore/Package.swift` — add test resources to `DetDocCoreTests`.
- Modify: `swift/DetDocApp/Sources/WorkspaceView.swift:20-29` — use the factory instead of hardcoding `FakeAgentRunner`.
- Tests (create): `PiRpcCodecTests.swift`, `PiRpcEventTests.swift`, `PiAgentPromptsTests.swift`, `PiPlanParsingTests.swift`, `PiAgentRunnerTests.swift`, `PiProcessTransportTests.swift`, `AgentRunnerFactoryTests.swift` under `swift/DetDocCore/Tests/DetDocCoreTests/`.
- Test support (create): `Tests/DetDocCoreTests/Support/FakePiTransport.swift`, `Tests/DetDocCoreTests/Support/PiTestBoxes.swift`, `Tests/DetDocCoreTests/Support/fake-pi.sh`, `Tests/DetDocCoreTests/Support/fake-pi-plan.jsonl`.

---

## Task 1: PiRpcCodec — JSONL framing + command encoding

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiRpcCodec.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/PiRpcCodecTests.swift`

**Interfaces:**
- Consumes: `DetDocError("CODE","message")` (Plan 1).
- Produces:
  - `enum PiRpcCodec` with:
    - `static func splitRecords(_ data: Data) throws -> [String]`
    - `static func encode<C: Encodable>(_ command: C) throws -> String`
    - `static func drainCompleteRecords(_ buffer: inout Data) -> [String]`

- [ ] **Step 1: Write the failing tests**

```swift
// swift/DetDocCore/Tests/DetDocCoreTests/PiRpcCodecTests.swift
import Foundation
import Testing
@testable import DetDocCore

@Test func splitsOnLineFeedOnlyAndPreservesUnicodeSeparators() throws {
    // Parity with Rust split_jsonl_records: LF-only split, strip trailing CR, keep U+2028 inside JSON.
    // Bytes: {"t":"a<U+2028>b}\n{"ok":true}\r\n
    let input = Data([0x7B,0x22,0x74,0x22,0x3A,0x22,0x61,0xE2,0x80,0xA8,0x62,0x22,0x7D,0x0A,
                      0x7B,0x22,0x6F,0x6B,0x22,0x3A,0x74,0x72,0x75,0x65,0x7D,0x0D,0x0A])
    let records = try PiRpcCodec.splitRecords(input)
    #expect(records == ["{\"t\":\"a\u{2028}b\"}", "{\"ok\":true}"])
}

@Test func splitRecordsThrowsOnInvalidUTF8() {
    let input = Data([0xFF, 0xFE, 0x0A])  // 0xFF/0xFE are not valid UTF-8 lead bytes
    #expect(throws: DetDocError.self) { _ = try PiRpcCodec.splitRecords(input) }
}

@Test func encodesCommandAsSingleLineWithoutEscapingSlashes() throws {
    struct Cmd: Encodable { let type = "prompt"; let message: String }
    let line = try PiRpcCodec.encode(Cmd(message: "docs/a.md"))
    #expect(!line.contains("\n"))
    #expect(line.contains("\"type\":\"prompt\""))
    #expect(line.contains("\"message\":\"docs/a.md\""))  // slash not escaped to \/
}

@Test func drainsOnlyCompleteRecordsAndKeepsRemainder() {
    var buffer = Data("{\"a\":1}\n{\"b\":2}\n{\"partial".utf8)
    let records = PiRpcCodec.drainCompleteRecords(&buffer)
    #expect(records == ["{\"a\":1}", "{\"b\":2}"])
    #expect(String(decoding: buffer, as: UTF8.self) == "{\"partial")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd swift/DetDocCore && swift test --filter PiRpcCodecTests`
Expected: FAIL — `cannot find 'PiRpcCodec' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiRpcCodec.swift
import Foundation

/// Strict JSONL framing + command encoding for the `pi --mode rpc` wire protocol.
///
/// Parity anchor: Rust `split_jsonl_records` (src-tauri/src/detdoc/pi_rpc.rs) — split on
/// LF (`0x0A`) only, strip a trailing CR (`0x0D`), drop empty records, and never split on
/// Unicode separators (U+2028/U+2029) that are valid inside JSON strings.
public enum PiRpcCodec {
    /// Split a UTF-8 byte buffer into JSONL records. Operates on bytes so framing matches
    /// the Rust reference exactly. Throws `PI_RPC_UTF8_INVALID` on invalid UTF-8.
    public static func splitRecords(_ data: Data) throws -> [String] {
        var records: [String] = []
        for chunk in data.split(separator: 0x0A, omittingEmptySubsequences: false) {
            var bytes = chunk
            if bytes.last == 0x0D { bytes = bytes.dropLast() }  // strip a trailing CR
            if bytes.isEmpty { continue }
            guard let line = String(bytes: bytes, encoding: .utf8) else {
                throw DetDocError("PI_RPC_UTF8_INVALID", "pi emitted invalid UTF-8 on stdout")
            }
            records.append(line)
        }
        return records
    }

    /// Encode an `Encodable` command as a single-line JSON string (no trailing newline;
    /// the transport appends the LF delimiter). Slashes are not escaped so paths stay readable.
    public static func encode<C: Encodable>(_ command: C) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(command)
        guard let line = String(data: data, encoding: .utf8) else {
            throw DetDocError("PI_RPC_ENCODE_FAILED", "Failed to encode pi RPC command")
        }
        return line
    }

    /// Extract complete LF-terminated records from `buffer`, leaving any trailing partial
    /// record behind. Used by the streaming transport to emit lines as they arrive. LF never
    /// falls inside a multi-byte UTF-8 sequence, so complete portions always decode cleanly.
    public static func drainCompleteRecords(_ buffer: inout Data) -> [String] {
        guard let lastLF = buffer.lastIndex(of: 0x0A) else { return [] }
        let complete = Data(buffer[..<buffer.index(after: lastLF)])
        let remainder = Data(buffer[buffer.index(after: lastLF)...])
        buffer = remainder
        return (try? splitRecords(complete)) ?? []
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd swift/DetDocCore && swift test --filter PiRpcCodecTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiRpcCodec.swift swift/DetDocCore/Tests/DetDocCoreTests/PiRpcCodecTests.swift
git commit -m "feat(core): pi RPC JSONL codec (framing + command encode)"
```

---

## Task 2: PiRpcEvent — event/message decoding model

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiRpcEvent.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/PiRpcEventTests.swift`

**Interfaces:**
- Consumes: `DetDocError` (Plan 1).
- Produces:
  - `enum PiRpcEvent: Sendable, Equatable` cases: `.agentEnd(messages: [PiRpcMessage])`, `.toolExecutionStart(toolName: String, path: String?, command: String?)`, `.response(command: String, success: Bool, error: String?)`, `.other(type: String)`; `static func decode(_ line: String) throws -> PiRpcEvent`.
  - `struct PiRpcMessage: Sendable, Equatable` `{ let role: String?; let text: String; let usage: PiRpcUsage? }` with public memberwise init.
  - `struct PiRpcUsage: Sendable, Equatable` `{ let input, output, cacheRead, cacheWrite: Int }` with public memberwise init.

- [ ] **Step 1: Write the failing tests**

```swift
// swift/DetDocCore/Tests/DetDocCoreTests/PiRpcEventTests.swift
import Foundation
import Testing
@testable import DetDocCore

@Test func decodesAgentEndWithAssistantTextAndUsage() throws {
    let line = "{\"type\":\"agent_end\",\"messages\":[{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}],\"usage\":{\"input\":10,\"output\":5,\"cacheRead\":1,\"cacheWrite\":2}}]}"
    guard case .agentEnd(let messages) = try PiRpcEvent.decode(line) else {
        Issue.record("expected .agentEnd"); return
    }
    #expect(messages.count == 1)
    #expect(messages[0].role == "assistant")
    #expect(messages[0].text == "hi")
    #expect(messages[0].usage == PiRpcUsage(input: 10, output: 5, cacheRead: 1, cacheWrite: 2))
}

@Test func decodesStringContentMessages() throws {
    let line = "{\"type\":\"agent_end\",\"messages\":[{\"role\":\"assistant\",\"content\":\"plain\"}]}"
    guard case .agentEnd(let messages) = try PiRpcEvent.decode(line) else {
        Issue.record("expected .agentEnd"); return
    }
    #expect(messages[0].text == "plain")
    #expect(messages[0].usage == nil)
}

@Test func decodesPromptFailureResponse() throws {
    let event = try PiRpcEvent.decode("{\"type\":\"response\",\"command\":\"prompt\",\"success\":false,\"error\":\"boom\"}")
    #expect(event == .response(command: "prompt", success: false, error: "boom"))
}

@Test func decodesToolExecutionStart() throws {
    let event = try PiRpcEvent.decode("{\"type\":\"tool_execution_start\",\"toolName\":\"write\",\"args\":{\"path\":\"src/app.swift\"}}")
    #expect(event == .toolExecutionStart(toolName: "write", path: "src/app.swift", command: nil))
}

@Test func decodesUnknownEventAsOther() throws {
    #expect(try PiRpcEvent.decode("{\"type\":\"turn_start\"}") == .other(type: "turn_start"))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd swift/DetDocCore && swift test --filter PiRpcEventTests`
Expected: FAIL — `cannot find 'PiRpcEvent' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiRpcEvent.swift
import Foundation

/// A minimal decoded view of the pi RPC event/response stream — only the fields DetDoc needs.
public enum PiRpcEvent: Sendable, Equatable {
    case agentEnd(messages: [PiRpcMessage])
    case toolExecutionStart(toolName: String, path: String?, command: String?)
    case response(command: String, success: Bool, error: String?)
    case other(type: String)

    public static func decode(_ line: String) throws -> PiRpcEvent {
        guard let data = line.data(using: .utf8) else {
            throw DetDocError("PI_RPC_UTF8_INVALID", "pi RPC line was not valid UTF-8")
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        switch envelope.type {
        case "agent_end":
            return .agentEnd(messages: envelope.messages ?? [])
        case "tool_execution_start":
            return .toolExecutionStart(toolName: envelope.toolName ?? "",
                                       path: envelope.args?.path,
                                       command: envelope.args?.command)
        case "response":
            return .response(command: envelope.command ?? "",
                             success: envelope.success ?? false,
                             error: envelope.error)
        default:
            return .other(type: envelope.type)
        }
    }

    private struct Envelope: Decodable {
        let type: String
        let messages: [PiRpcMessage]?
        let toolName: String?
        let args: ToolArgs?
        let command: String?
        let success: Bool?
        let error: String?
    }

    private struct ToolArgs: Decodable {
        let path: String?
        let command: String?
    }
}

/// An assistant/user/tool message as carried in `agent_end`. `content` (string or block array)
/// is flattened to concatenated text; only assistant `usage` is relevant to DetDoc.
public struct PiRpcMessage: Sendable, Equatable {
    public let role: String?
    public let text: String
    public let usage: PiRpcUsage?

    public init(role: String?, text: String, usage: PiRpcUsage?) {
        self.role = role
        self.text = text
        self.usage = usage
    }
}

extension PiRpcMessage: Decodable {
    enum CodingKeys: String, CodingKey { case role, content, usage }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        usage = try container.decodeIfPresent(PiRpcUsage.self, forKey: .usage)
        if let string = try? container.decode(String.self, forKey: .content) {
            text = string
        } else if let blocks = try? container.decode([ContentBlock].self, forKey: .content) {
            text = blocks.compactMap(\.text).joined()
        } else {
            text = ""
        }
    }

    private struct ContentBlock: Decodable {
        let type: String?
        let text: String?
    }
}

/// Token usage as reported on an assistant message's `usage` field (the wire has no `total`).
public struct PiRpcUsage: Sendable, Equatable {
    public let input: Int
    public let output: Int
    public let cacheRead: Int
    public let cacheWrite: Int

    public init(input: Int, output: Int, cacheRead: Int, cacheWrite: Int) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }
}

extension PiRpcUsage: Decodable {
    enum CodingKeys: String, CodingKey { case input, output, cacheRead, cacheWrite }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = try container.decodeIfPresent(Int.self, forKey: .input) ?? 0
        output = try container.decodeIfPresent(Int.self, forKey: .output) ?? 0
        cacheRead = try container.decodeIfPresent(Int.self, forKey: .cacheRead) ?? 0
        cacheWrite = try container.decodeIfPresent(Int.self, forKey: .cacheWrite) ?? 0
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd swift/DetDocCore && swift test --filter PiRpcEventTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiRpcEvent.swift swift/DetDocCore/Tests/DetDocCoreTests/PiRpcEventTests.swift
git commit -m "feat(core): pi RPC event/message decoding model"
```

---

## Task 3: PiAgentPrompts — planning / implementation / repair prompts

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiAgentPrompts.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/PiAgentPromptsTests.swift`

**Interfaces:**
- Consumes: `PlanRequest`, `ImplementRequest`, `RepairRequest` (Plan 2 — `Agent/AgentRunner.swift`); `RunMode.rawValue`; `DetDocConfig.paths.deny: [String]`, `ProposedPlan` (Plan 1); `PiRpcCodec.encode` (Task 1).
- Produces:
  - `enum PiAgentPrompts` with `static func planningPrompt(_ request: PlanRequest) -> String`, `static func implementationPrompt(_ request: ImplementRequest) -> String`, `static func validationRepairPrompt(_ request: RepairRequest) -> String`.

- [ ] **Step 1: Write the failing tests**

```swift
// swift/DetDocCore/Tests/DetDocCoreTests/PiAgentPromptsTests.swift
import Foundation
import Testing
@testable import DetDocCore

private let cwd = URL(fileURLWithPath: "/tmp")

@Test func planningPromptRunModeRequiresDocDiffReason() {
    let request = PlanRequest(mode: .run, input: "DIFF", config: .default, cwd: cwd)
    let prompt = PiAgentPrompts.planningPrompt(request)
    #expect(prompt.contains("You are DetDoc planning phase."))
    #expect(prompt.contains("output the implementation plan as a single JSON object"))
    #expect(prompt.contains("Every changes[].reason MUST start with `doc-diff:`."))
    #expect(prompt.contains("Mode: run"))
    #expect(prompt.hasSuffix("Input:\n\nDIFF"))
}

@Test func planningPromptFixModeRequiresIntentFix() {
    let request = PlanRequest(mode: .fix, input: "make tests pass", config: .default, cwd: cwd)
    let prompt = PiAgentPrompts.planningPrompt(request)
    #expect(prompt.contains("Every changes[].reason MUST be `intent:fix`."))
    #expect(prompt.contains("Fix mode MUST NOT target documentation files."))
}

@Test func planningPromptEmbedsDeniedPaths() {
    let prompt = PiAgentPrompts.planningPrompt(PlanRequest(mode: .run, input: "x", config: .default, cwd: cwd))
    #expect(prompt.contains("\".env\""))  // paths.deny default includes ".env"
}

@Test func implementationPromptEmbedsApprovedPlanAndInput() {
    let plan = ProposedPlan(summary: "S", changes: [PlanChange(reason: "doc-diff:docs/a.md:L1", targetFiles: ["src/a.swift"], kind: "modify", rationale: "r")], risk: "low")
    let request = ImplementRequest(mode: .run, input: "IN", config: .default, cwd: cwd, approvedPlan: plan, approvedTargets: ["src/a.swift"], progress: nil)
    let prompt = PiAgentPrompts.implementationPrompt(request)
    #expect(prompt.contains("You are DetDoc implementation phase."))
    #expect(prompt.contains("\"summary\""))
    #expect(prompt.contains("src/a.swift"))
    #expect(prompt.hasSuffix("Original input:\n\nIN"))
}

@Test func validationRepairPromptEmbedsLogAndAttempt() {
    let plan = ProposedPlan(summary: "S", changes: [PlanChange(reason: "doc-diff:docs/a.md:L1", targetFiles: ["src/a.swift"], kind: "modify", rationale: "r")], risk: "low")
    let base = ImplementRequest(mode: .run, input: "IN", config: .default, cwd: cwd, approvedPlan: plan, approvedTargets: ["src/a.swift"], progress: nil)
    let prompt = PiAgentPrompts.validationRepairPrompt(RepairRequest(base: base, validationLog: "FAILED: grep", attempt: 1))
    #expect(prompt.contains("You are DetDoc validation repair phase."))
    #expect(prompt.contains("Validation failed on attempt 1."))
    #expect(prompt.contains("FAILED: grep"))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd swift/DetDocCore && swift test --filter PiAgentPromptsTests`
Expected: FAIL — `cannot find 'PiAgentPrompts' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiAgentPrompts.swift
import Foundation

/// Builds the DetDoc two-phase prompts sent to `pi`. Implementation/repair prompts are ported
/// verbatim from the TS reference (src/core/agent/pi-sdk-runner.ts); the planning prompt is
/// adapted to request a single JSON object instead of a `submit_plan` tool call (see Key Decision).
public enum PiAgentPrompts {
    public static func planningPrompt(_ request: PlanRequest) -> String {
        let reasonRule: String
        switch request.mode {
        case .run:
            reasonRule = [
                "Every changes[].reason MUST start with `doc-diff:`.",
                "Example: `doc-diff:docs/spec.md:L1-L20`.",
                "Use the changed Markdown file path and approximate changed line range from the diff.",
            ].joined(separator: "\n")
        case .fix:
            reasonRule = [
                "Every changes[].reason MUST be `intent:fix`.",
                "Fix mode MUST NOT target documentation files.",
            ].joined(separator: "\n")
        }
        let denied = (try? PiRpcCodec.encode(request.config.paths.deny)) ?? "[]"
        return [
            "You are DetDoc planning phase.",
            "Inspect the repository using read-only tools only.",
            "Do not modify files.",
            "When ready, output the implementation plan as a single JSON object and nothing else.",
            "Do not wrap the JSON in prose or Markdown code fences; do not call any tool to submit it.",
            "Plan schema constraints:",
            "- summary: short string.",
            "- changes: non-empty array.",
            "- changes[].targetFiles: exact repository-relative paths that implementation may edit/create/delete.",
            "- changes[].kind: one of create, modify, delete, rename.",
            "- changes[].rationale: explain why the target follows from the input.",
            "- \(reasonRule)",
            "Do not use free-form prose in changes[].reason; it must follow the exact prefix/value rule above.",
            "If the documentation names validation or generation commands that DetDoc should run after applying changes, inspect `.detdoc/config.yml`; if those commands are missing, include `.detdoc/config.yml` in targetFiles and update validation.commands. Prefer validation.commands entries shaped as `{ name, run }`.",
            "Do not target documentation files such as `docs/**`; documentation is read-only input for implementation.",
            "Denied paths from config must never be targeted:",
            denied,
            "Mode: \(request.mode.rawValue)",
            "Input:",
            request.input,
        ].joined(separator: "\n\n")
    }

    public static func implementationPrompt(_ request: ImplementRequest) -> String {
        [
            "You are DetDoc implementation phase.",
            "Implement only the approved plan.",
            "Use bash for diagnostics, generation, builds, and tests inside the isolated worktree.",
            "Use edit/write only for approved target paths.",
            "Documentation files are read-only; never edit files under docs/.",
            "If another source file is required, stop and explain instead of editing it.",
            "Mode: \(request.mode.rawValue)",
            "Approved plan:",
            prettyJSON(request.approvedPlan),
            "Original input:",
            request.input,
        ].joined(separator: "\n\n")
    }

    public static func validationRepairPrompt(_ request: RepairRequest) -> String {
        [
            "You are DetDoc validation repair phase.",
            "Validation failed on attempt \(request.attempt).",
            "Use bash to inspect and reproduce the validation failure inside the isolated worktree.",
            "Fix the failure by editing only approved target paths.",
            "Do not edit documentation files under docs/.",
            "Do not broaden scope or add unapproved files.",
            "Mode: \(request.base.mode.rawValue)",
            "Approved plan:",
            prettyJSON(request.base.approvedPlan),
            "Validation log:",
            request.validationLog,
            "Original input:",
            request.base.input,
        ].joined(separator: "\n\n")
    }

    private static func prettyJSON<E: Encodable>(_ value: E) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd swift/DetDocCore && swift test --filter PiAgentPromptsTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiAgentPrompts.swift swift/DetDocCore/Tests/DetDocCoreTests/PiAgentPromptsTests.swift
git commit -m "feat(core): pi agent prompt builders (plan/implement/repair)"
```

---

## Task 4: PiPlanParsing — plan + token-usage extraction

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiPlanParsing.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/PiPlanParsingTests.swift`

**Interfaces:**
- Consumes: `PiRpcMessage`, `PiRpcUsage` (Task 2); `ProposedPlan` (Plan 1); `TokenUsage` (Plan 1 — `Models/CoreModels.swift`, fields `input/output/cacheRead/cacheWrite/total`); `DetDocError`.
- Produces:
  - `enum PiPlanParsing` with `static func parsePlan(fromAssistantText text: String) throws -> ProposedPlan`, `static func lastAssistantText(_ messages: [PiRpcMessage]) -> String`, `static func tokenUsage(_ messages: [PiRpcMessage]) -> TokenUsage`.

- [ ] **Step 1: Write the failing tests**

```swift
// swift/DetDocCore/Tests/DetDocCoreTests/PiPlanParsingTests.swift
import Foundation
import Testing
@testable import DetDocCore

@Test func parsesPlainPlanJSON() throws {
    let text = "{\"summary\":\"S\",\"changes\":[{\"reason\":\"doc-diff:docs/a.md:L1\",\"targetFiles\":[\"src/a.swift\"],\"kind\":\"modify\",\"rationale\":\"r\"}],\"questions\":[],\"risk\":\"low\"}"
    let plan = try PiPlanParsing.parsePlan(fromAssistantText: text)
    #expect(plan.summary == "S")
    #expect(plan.changes.first?.targetFiles == ["src/a.swift"])
}

@Test func parsesPlanJSONWrappedInProseAndFences() throws {
    let text = "Here is the plan:\n```json\n{\"summary\":\"S\",\"changes\":[{\"reason\":\"intent:fix\",\"targetFiles\":[\"src/a.swift\"],\"kind\":\"modify\",\"rationale\":\"r\"}],\"risk\":\"low\"}\n```\n"
    let plan = try PiPlanParsing.parsePlan(fromAssistantText: text)
    #expect(plan.risk == "low")
    #expect(plan.questions == [])  // ProposedPlan defaults questions
}

@Test func parsePlanThrowsForNonJSON() {
    #expect(throws: DetDocError.self) { _ = try PiPlanParsing.parsePlan(fromAssistantText: "no json here") }
}

@Test func lastAssistantTextPicksLatestAssistant() {
    let messages = [
        PiRpcMessage(role: "user", text: "u", usage: nil),
        PiRpcMessage(role: "assistant", text: "first", usage: nil),
        PiRpcMessage(role: "assistant", text: "second", usage: nil),
    ]
    #expect(PiPlanParsing.lastAssistantText(messages) == "second")
}

@Test func tokenUsageSumsAssistantMessagesAndComputesTotal() {
    let messages = [
        PiRpcMessage(role: "assistant", text: "", usage: PiRpcUsage(input: 10, output: 5, cacheRead: 1, cacheWrite: 2)),
        PiRpcMessage(role: "user", text: "", usage: nil),
        PiRpcMessage(role: "assistant", text: "", usage: PiRpcUsage(input: 3, output: 4, cacheRead: 0, cacheWrite: 0)),
    ]
    let usage = PiPlanParsing.tokenUsage(messages)
    #expect(usage.input == 13)
    #expect(usage.output == 9)
    #expect(usage.cacheRead == 1)
    #expect(usage.cacheWrite == 2)
    #expect(usage.total == 13 + 9 + 1 + 2)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd swift/DetDocCore && swift test --filter PiPlanParsingTests`
Expected: FAIL — `cannot find 'PiPlanParsing' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiPlanParsing.swift
import Foundation

/// Extracts the structured plan and token usage from pi's `agent_end` messages.
/// Ports `extractLastAssistantText` / `extractSessionTokenUsage` from the TS reference.
public enum PiPlanParsing {
    /// Decode the plan JSON object embedded in the agent's final assistant text. Tolerant of
    /// surrounding prose / code fences: slices from the first `{` to the last `}`.
    public static func parsePlan(fromAssistantText text: String) throws -> ProposedPlan {
        let json = extractJSONObject(from: text)
        guard let data = json.data(using: .utf8) else {
            throw DetDocError("PI_PLAN_PARSE_FAILED", "pi plan output was not valid UTF-8")
        }
        do {
            return try JSONDecoder().decode(ProposedPlan.self, from: data)
        } catch {
            throw DetDocError("PI_PLAN_PARSE_FAILED", "pi did not return a valid plan JSON object: \(error)")
        }
    }

    /// The concatenated text of the most recent assistant message (empty if none).
    public static func lastAssistantText(_ messages: [PiRpcMessage]) -> String {
        for message in messages.reversed() where message.role == "assistant" {
            return message.text
        }
        return ""
    }

    /// Sum token usage across assistant messages; `total` is computed (the wire has no total).
    public static func tokenUsage(_ messages: [PiRpcMessage]) -> TokenUsage {
        var input = 0, output = 0, cacheRead = 0, cacheWrite = 0
        for message in messages where message.role == "assistant" {
            guard let usage = message.usage else { continue }
            input += usage.input
            output += usage.output
            cacheRead += usage.cacheRead
            cacheWrite += usage.cacheWrite
        }
        return TokenUsage(input: input, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite,
                          total: input + output + cacheRead + cacheWrite)
    }

    /// Return the substring from the first `{` to the last `}`, trimming surrounding text.
    static func extractJSONObject(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let open = trimmed.firstIndex(of: "{"),
              let close = trimmed.lastIndex(of: "}"),
              open <= close else {
            return trimmed
        }
        return String(trimmed[open...close])
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd swift/DetDocCore && swift test --filter PiPlanParsingTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiPlanParsing.swift swift/DetDocCore/Tests/DetDocCoreTests/PiPlanParsingTests.swift
git commit -m "feat(core): pi plan + token-usage extraction"
```

---

## Task 5: PiRpcTransport protocol + FakePiTransport + PiAgentRunner.plan

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiRpcTransport.swift`
- Create: `swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiProcessTransport.swift`
- Create: `swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiAgentRunner.swift`
- Create: `swift/DetDocCore/Tests/DetDocCoreTests/Support/FakePiTransport.swift`
- Create: `swift/DetDocCore/Tests/DetDocCoreTests/Support/PiTestBoxes.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/PiAgentRunnerTests.swift`

**Interfaces:**
- Consumes: `AgentRunner`, `PlanRequest`, `AgentPlanResult` (Plan 2); `PiRpcCodec`, `PiRpcEvent`, `PiAgentPrompts`, `PiPlanParsing` (Tasks 1-4); `DetDocConfig.agent.model`, `DetDocConfig.agent.thinking` (Plan 1).
- Produces:
  - `protocol PiRpcTransport: Sendable { func send(_ line: String) async throws; func events() -> AsyncThrowingStream<String, Error>; func finish() async }`.
  - `final class PiProcessTransport: PiRpcTransport, @unchecked Sendable` with `init(executable:arguments:cwd:) throws` — the live `pi --mode rpc` subprocess (default for the runner's factory).
  - `struct PiAgentRunner: AgentRunner` with `typealias TransportFactory = @Sendable (_ executable: String, _ args: [String], _ cwd: URL) throws -> any PiRpcTransport`; `init(executable: String = "pi", makeTransport: @escaping TransportFactory = …)`; `var supportsRepair: Bool { true }`; `func plan(_:)`. (`implement`/`repairValidation` added in Task 6.)
  - Internal: `static func spawnArgs(model: String?, tools: [String]) -> [String]`; `static let planningTools`; `static let implementationTools`.

- [ ] **Step 1: Write the failing test + test support**

```swift
// swift/DetDocCore/Tests/DetDocCoreTests/Support/FakePiTransport.swift
import Foundation
@testable import DetDocCore

/// An in-memory `PiRpcTransport` for tests: records sent command lines and replays a fixed
/// script of stdout JSONL records.
final class FakePiTransport: PiRpcTransport, @unchecked Sendable {
    private let scriptLines: [String]
    private let lock = NSLock()
    private var sent: [String] = []

    init(scriptLines: [String]) { self.scriptLines = scriptLines }

    var sentLines: [String] { lock.lock(); defer { lock.unlock() }; return sent }

    func send(_ line: String) async throws {
        lock.lock(); sent.append(line); lock.unlock()
    }

    func events() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for line in scriptLines { continuation.yield(line) }
            continuation.finish()
        }
    }

    func finish() async {}
}
```

```swift
// swift/DetDocCore/Tests/DetDocCoreTests/Support/PiTestBoxes.swift
import Foundation
@testable import DetDocCore

/// Sendable box for capturing the spawn args passed to a transport factory.
final class ArgsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [String] = []
    func set(_ args: [String]) { lock.lock(); value = args; lock.unlock() }
    var args: [String] { lock.lock(); defer { lock.unlock() }; return value }
}

/// Sendable box for collecting implementation progress callbacks.
final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [AgentImplementationProgress] = []
    func append(_ event: AgentImplementationProgress) { lock.lock(); collected.append(event); lock.unlock() }
    var events: [AgentImplementationProgress] { lock.lock(); defer { lock.unlock() }; return collected }
}

/// Build an `agent_end` JSONL line whose single assistant message carries `planJSON` as text.
func agentEndLine(planJSON: String, input: Int = 0, output: Int = 0) throws -> String {
    let content = try PiRpcCodec.encode([["type": "text", "text": planJSON]])
    return "{\"type\":\"agent_end\",\"messages\":[{\"role\":\"assistant\",\"content\":\(content),\"usage\":{\"input\":\(input),\"output\":\(output),\"cacheRead\":0,\"cacheWrite\":0}}]}"
}
```

```swift
// swift/DetDocCore/Tests/DetDocCoreTests/PiAgentRunnerTests.swift
import Foundation
import Testing
@testable import DetDocCore

private let planJSON = "{\"summary\":\"S\",\"changes\":[{\"reason\":\"doc-diff:docs/a.md:L1\",\"targetFiles\":[\"src/app.swift\"],\"kind\":\"modify\",\"rationale\":\"r\"}],\"questions\":[],\"risk\":\"low\"}"

@Test func planSendsThinkingThenPromptAndReturnsParsedPlan() async throws {
    let script = [
        "{\"type\":\"response\",\"command\":\"set_thinking_level\",\"success\":true}",
        "{\"type\":\"response\",\"command\":\"prompt\",\"success\":true}",
        "{\"type\":\"agent_start\"}",
        try agentEndLine(planJSON: planJSON, input: 10, output: 5),
    ]
    let transport = FakePiTransport(scriptLines: script)
    let argsBox = ArgsBox()
    let runner = PiAgentRunner(executable: "pi") { _, args, _ in argsBox.set(args); return transport }

    let result = try await runner.plan(PlanRequest(mode: .run, input: "DIFF", config: .default, cwd: URL(fileURLWithPath: "/tmp")))

    #expect(result.plan.summary == "S")
    #expect(result.plan.changes.first?.targetFiles == ["src/app.swift"])
    #expect(result.usage.input == 10)
    #expect(result.usage.total == 15)
    #expect(transport.sentLines.contains { $0.contains("\"type\":\"set_thinking_level\"") })
    #expect(transport.sentLines.contains { $0.contains("\"type\":\"prompt\"") })
    #expect(argsBox.args.contains("--mode"))
    #expect(argsBox.args.contains("rpc"))
    #expect(argsBox.args.contains("--no-session"))
    #expect(argsBox.args.contains("read,grep,find,ls"))  // planning tool set
}

@Test func planThrowsWhenPromptRejected() async {
    let script = ["{\"type\":\"response\",\"command\":\"prompt\",\"success\":false,\"error\":\"bad\"}"]
    let transport = FakePiTransport(scriptLines: script)
    let runner = PiAgentRunner(executable: "pi") { _, _, _ in transport }
    await #expect {
        _ = try await runner.plan(PlanRequest(mode: .run, input: "x", config: .default, cwd: URL(fileURLWithPath: "/tmp")))
    } throws: { ($0 as? DetDocError)?.code == "PI_RPC_COMMAND_FAILED" }
}

@Test func planThrowsWhenNoAgentEnd() async {
    let script = ["{\"type\":\"response\",\"command\":\"prompt\",\"success\":true}", "{\"type\":\"agent_start\"}"]
    let transport = FakePiTransport(scriptLines: script)
    let runner = PiAgentRunner(executable: "pi") { _, _, _ in transport }
    await #expect {
        _ = try await runner.plan(PlanRequest(mode: .run, input: "x", config: .default, cwd: URL(fileURLWithPath: "/tmp")))
    } throws: { ($0 as? DetDocError)?.code == "PI_RPC_NO_RESULT" }
}

@Test func passesModelArgWhenConfigured() async throws {
    var config = DetDocConfig.default
    config.agent.model = "anthropic/claude-opus"
    let transport = FakePiTransport(scriptLines: [
        "{\"type\":\"response\",\"command\":\"prompt\",\"success\":true}",
        try agentEndLine(planJSON: planJSON),
    ])
    let argsBox = ArgsBox()
    let runner = PiAgentRunner(executable: "pi") { _, args, _ in argsBox.set(args); return transport }
    _ = try await runner.plan(PlanRequest(mode: .run, input: "x", config: config, cwd: URL(fileURLWithPath: "/tmp")))
    #expect(argsBox.args.contains("--model"))
    #expect(argsBox.args.contains("anthropic/claude-opus"))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd swift/DetDocCore && swift test --filter PiAgentRunnerTests`
Expected: FAIL — `cannot find 'PiRpcTransport' / 'PiAgentRunner' in scope`.

- [ ] **Step 3: Write the transport protocol**

```swift
// swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiRpcTransport.swift
import Foundation

/// A bidirectional JSONL channel to a `pi --mode rpc` process. Abstracted so `PiAgentRunner`
/// is testable with an in-memory fake and runs live via `PiProcessTransport`.
public protocol PiRpcTransport: Sendable {
    /// Write one command as a single JSONL record (the transport appends the LF delimiter).
    func send(_ line: String) async throws
    /// Decoded JSONL records streamed from pi stdout, in order, until the process ends.
    func events() -> AsyncThrowingStream<String, Error>
    /// Close stdin and let pi exit; idempotent.
    func finish() async
}
```

- [ ] **Step 4: Write `PiProcessTransport` (the live subprocess transport)**

```swift
// swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiProcessTransport.swift
import Foundation

/// Live `pi --mode rpc` subprocess transport: spawns pi via `/usr/bin/env`, writes commands
/// to stdin, and streams LF-delimited JSONL records from stdout. Models the concurrency
/// approach of `ProcessRunner` (NSLock-guarded boxes, @unchecked Sendable).
public final class PiProcessTransport: PiRpcTransport, @unchecked Sendable {
    private let process: Process
    private let stdinHandle: FileHandle
    private let stdoutHandle: FileHandle
    private let stderrHandle: FileHandle
    private let lock = NSLock()
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var didFinish = false

    public init(executable: String, arguments: [String], cwd: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.currentDirectoryURL = cwd
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe
        self.process = process
        self.stdinHandle = inPipe.fileHandleForWriting
        self.stdoutHandle = outPipe.fileHandleForReading
        self.stderrHandle = errPipe.fileHandleForReading

        // Drain stderr continuously so a chatty pi can't deadlock by filling the pipe buffer.
        stderrHandle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self, !chunk.isEmpty else { return }
            self.lock.lock(); self.stderrBuffer.append(chunk); self.lock.unlock()
        }

        do {
            try process.run()
        } catch {
            throw DetDocError("PI_RPC_SPAWN_FAILED", "\(executable): \(error)")
        }
    }

    public func send(_ line: String) async throws {
        let data = Data((line + "\n").utf8)
        lock.lock(); defer { lock.unlock() }
        guard !didFinish else { return }
        do {
            try stdinHandle.write(contentsOf: data)
        } catch {
            throw DetDocError("PI_RPC_WRITE_FAILED", "Failed to write to pi stdin: \(error)")
        }
    }

    public func events() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            stdoutHandle.readabilityHandler = { [weak self] handle in
                guard let self else { return }
                let chunk = handle.availableData
                if chunk.isEmpty {  // EOF
                    handle.readabilityHandler = nil
                    continuation.finish()
                    return
                }
                self.lock.lock()
                self.stdoutBuffer.append(chunk)
                let records = PiRpcCodec.drainCompleteRecords(&self.stdoutBuffer)
                self.lock.unlock()
                for record in records { continuation.yield(record) }
            }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.finish() }
            }
        }
    }

    public func finish() async {
        lock.lock()
        let already = didFinish
        didFinish = true
        lock.unlock()
        guard !already else { return }
        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil
        try? stdinHandle.close()
        if process.isRunning { process.terminate() }
    }
}
```

- [ ] **Step 5: Write the runner (plan only; `implement`/`repairValidation` added in Task 6)**

```swift
// swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiAgentRunner.swift
import Foundation

/// `AgentRunner` that drives the installed `pi` binary as a subprocess over JSONL.
/// Pure logic is in PiRpcCodec/PiRpcEvent/PiAgentPrompts/PiPlanParsing; I/O is in the
/// injected `PiRpcTransport` (default: a live `pi --mode rpc` process).
public struct PiAgentRunner: AgentRunner {
    public typealias TransportFactory =
        @Sendable (_ executable: String, _ args: [String], _ cwd: URL) throws -> any PiRpcTransport

    let executable: String
    let makeTransport: TransportFactory

    public init(executable: String = "pi",
                makeTransport: @escaping TransportFactory = { executable, args, cwd in
                    try PiProcessTransport(executable: executable, arguments: args, cwd: cwd)
                }) {
        self.executable = executable
        self.makeTransport = makeTransport
    }

    public var supportsRepair: Bool { true }

    static let planningTools = ["read", "grep", "find", "ls"]
    static let implementationTools = ["read", "grep", "find", "ls", "bash", "edit", "write"]

    public func plan(_ request: PlanRequest) async throws -> AgentPlanResult {
        let args = Self.spawnArgs(model: request.config.agent.model, tools: Self.planningTools)
        let transport = try makeTransport(executable, args, request.cwd)
        let messages = try await drive(transport,
                                       thinking: request.config.agent.thinking,
                                       prompt: PiAgentPrompts.planningPrompt(request),
                                       progress: nil)
        let plan = try PiPlanParsing.parsePlan(fromAssistantText: PiPlanParsing.lastAssistantText(messages))
        return AgentPlanResult(plan: plan, usage: PiPlanParsing.tokenUsage(messages))
    }

    static func spawnArgs(model: String?, tools: [String]) -> [String] {
        var args = ["--mode", "rpc", "--no-session", "--tools", tools.joined(separator: ",")]
        if let model, !model.isEmpty { args += ["--model", model] }
        return args
    }

    /// Send the thinking level + prompt, then consume events until `agent_end`, returning that
    /// event's messages. Maps `tool_execution_start` → `progress` when a callback is supplied.
    func drive(_ transport: any PiRpcTransport,
               thinking: String,
               prompt: String,
               progress: (@Sendable (AgentImplementationProgress) -> Void)?) async throws -> [PiRpcMessage] {
        let stream = transport.events()
        try await transport.send(PiRpcCodec.encode(SetThinkingLevelCommand(level: thinking)))
        try await transport.send(PiRpcCodec.encode(PromptCommand(message: prompt)))

        var messages: [PiRpcMessage]?
        do {
            for try await line in stream {
                switch try PiRpcEvent.decode(line) {
                case .response(let command, let success, let error):
                    if command == "prompt" && !success {
                        throw DetDocError("PI_RPC_COMMAND_FAILED", "pi rejected the prompt: \(error ?? "unknown error")")
                    }
                case .toolExecutionStart(let toolName, let path, let command):
                    if let progress {
                        Self.emitProgress(toolName: toolName, path: path, command: command, progress: progress)
                    }
                case .agentEnd(let endMessages):
                    messages = endMessages
                case .other:
                    break
                }
                if messages != nil { break }
            }
        } catch {
            await transport.finish()
            throw error
        }
        await transport.finish()
        guard let messages else {
            throw DetDocError("PI_RPC_NO_RESULT", "pi ended without an agent_end event")
        }
        return messages
    }

    static func emitProgress(toolName: String, path: String?, command: String?,
                             progress: @Sendable (AgentImplementationProgress) -> Void) {
        switch toolName {
        case "edit": if let path { progress(.edit(path: path)) }
        case "write": if let path { progress(.write(path: path)) }
        case "bash": if let command { progress(.bash(command: command)) }
        default: break
        }
    }
}

struct SetThinkingLevelCommand: Encodable {
    let type = "set_thinking_level"
    let level: String
}

struct PromptCommand: Encodable {
    let type = "prompt"
    let message: String
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd swift/DetDocCore && swift test --filter PiAgentRunnerTests`
Expected: PASS (4 tests). The injected `FakePiTransport` means `PiProcessTransport` is not exercised here — Task 7 covers it.

- [ ] **Step 7: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiRpcTransport.swift swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiProcessTransport.swift swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiAgentRunner.swift swift/DetDocCore/Tests/DetDocCoreTests/PiAgentRunnerTests.swift swift/DetDocCore/Tests/DetDocCoreTests/Support/FakePiTransport.swift swift/DetDocCore/Tests/DetDocCoreTests/Support/PiTestBoxes.swift
git commit -m "feat(core): PiRpcTransport + PiProcessTransport + PiAgentRunner.plan"
```

---

## Task 6: PiAgentRunner.implement + repairValidation

**Files:**
- Modify: `swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiAgentRunner.swift` (add `implement`/`repairValidation`)
- Test: append to `swift/DetDocCore/Tests/DetDocCoreTests/PiAgentRunnerTests.swift`

**Interfaces:**
- Consumes: `ImplementRequest`, `RepairRequest`, `AgentRunResult`, `AgentImplementationProgress` (Plan 2); `PiAgentRunner.drive`/`spawnArgs`/`implementationTools` (Task 5).
- Produces:
  - `PiAgentRunner.implement(_:) async throws -> AgentRunResult`, `PiAgentRunner.repairValidation(_:) async throws -> AgentRunResult`.

- [ ] **Step 1: Write the failing tests (append)**

```swift
// append to swift/DetDocCore/Tests/DetDocCoreTests/PiAgentRunnerTests.swift

private func approvedPlan() -> ProposedPlan {
    ProposedPlan(summary: "S", changes: [PlanChange(reason: "doc-diff:docs/a.md:L1", targetFiles: ["src/app.swift"], kind: "modify", rationale: "r")], risk: "low")
}

@Test func implementSendsImplementationPromptAndReportsProgress() async throws {
    let script = [
        "{\"type\":\"response\",\"command\":\"prompt\",\"success\":true}",
        "{\"type\":\"tool_execution_start\",\"toolName\":\"write\",\"args\":{\"path\":\"src/app.swift\"}}",
        "{\"type\":\"tool_execution_start\",\"toolName\":\"bash\",\"args\":{\"command\":\"swift build\"}}",
        try agentEndLine(planJSON: "{}", input: 1, output: 1),
    ]
    let transport = FakePiTransport(scriptLines: script)
    let progress = ProgressBox()
    let runner = PiAgentRunner(executable: "pi") { _, args, _ in
        #expect(args.contains("read,grep,find,ls,bash,edit,write"))  // implementation tool set
        return transport
    }
    let request = ImplementRequest(mode: .run, input: "IN", config: .default, cwd: URL(fileURLWithPath: "/tmp"),
                                   approvedPlan: approvedPlan(), approvedTargets: ["src/app.swift"],
                                   progress: { progress.append($0) })
    let result = try await runner.implement(request)

    #expect(result.usage.input == 1)
    #expect(transport.sentLines.contains { $0.contains("DetDoc implementation phase") })
    #expect(progress.events.contains { if case .write(let p) = $0 { return p == "src/app.swift" } else { return false } })
    #expect(progress.events.contains { if case .bash(let c) = $0 { return c == "swift build" } else { return false } })
}

@Test func repairValidationSendsRepairPrompt() async throws {
    let transport = FakePiTransport(scriptLines: [
        "{\"type\":\"response\",\"command\":\"prompt\",\"success\":true}",
        "{\"type\":\"agent_end\",\"messages\":[]}",
    ])
    let runner = PiAgentRunner(executable: "pi") { _, _, _ in transport }
    let base = ImplementRequest(mode: .run, input: "IN", config: .default, cwd: URL(fileURLWithPath: "/tmp"),
                                approvedPlan: approvedPlan(), approvedTargets: ["src/app.swift"], progress: nil)
    _ = try await runner.repairValidation(RepairRequest(base: base, validationLog: "FAILED: grep", attempt: 1))
    #expect(transport.sentLines.contains { $0.contains("DetDoc validation repair phase") })
    #expect(transport.sentLines.contains { $0.contains("FAILED: grep") })
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd swift/DetDocCore && swift test --filter PiAgentRunnerTests`
Expected: FAIL — `value of type 'PiAgentRunner' has no member 'implement'`.

- [ ] **Step 3: Add `implement` / `repairValidation`**

In `PiAgentRunner.swift`, add these methods inside `struct PiAgentRunner` (after `plan`):

```swift
    public func implement(_ request: ImplementRequest) async throws -> AgentRunResult {
        try await runImplementation(request,
                                    prompt: PiAgentPrompts.implementationPrompt(request),
                                    progress: request.progress)
    }

    public func repairValidation(_ request: RepairRequest) async throws -> AgentRunResult {
        try await runImplementation(request.base,
                                    prompt: PiAgentPrompts.validationRepairPrompt(request),
                                    progress: request.base.progress)
    }

    private func runImplementation(_ request: ImplementRequest,
                                   prompt: String,
                                   progress: (@Sendable (AgentImplementationProgress) -> Void)?) async throws -> AgentRunResult {
        let args = Self.spawnArgs(model: request.config.agent.model, tools: Self.implementationTools)
        let transport = try makeTransport(executable, args, request.cwd)
        let messages = try await drive(transport, thinking: request.config.agent.thinking, prompt: prompt, progress: progress)
        return AgentRunResult(usage: PiPlanParsing.tokenUsage(messages))
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd swift/DetDocCore && swift test --filter PiAgentRunnerTests`
Expected: PASS (6 tests total).

- [ ] **Step 5: Build the whole package to confirm warning-clean (warnings = errors)**

Run: `cd swift/DetDocCore && swift build`
Expected: `Build complete!` with no warnings.

- [ ] **Step 6: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiAgentRunner.swift swift/DetDocCore/Tests/DetDocCoreTests/PiAgentRunnerTests.swift
git commit -m "feat(core): PiAgentRunner implement/repair methods"
```

---

## Task 7: PiProcessTransport integration test (fake-pi over a real pipe)

**Files:**
- Modify: `swift/DetDocCore/Package.swift` (add resources to `DetDocCoreTests`)
- Create: `swift/DetDocCore/Tests/DetDocCoreTests/Support/fake-pi.sh`
- Create: `swift/DetDocCore/Tests/DetDocCoreTests/Support/fake-pi-plan.jsonl`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/PiProcessTransportTests.swift`

**Interfaces:**
- Consumes: `PiAgentRunner`, `PiProcessTransport` (Task 5); `Bundle.module` (SwiftPM resource accessor).
- Produces: an end-to-end test driving `plan()` through a real `PiProcessTransport` against a deterministic fake-`pi` script (no network/LLM), proving spawn + stdin/stdout framing + codec + runner compose correctly.

- [ ] **Step 1: Create the fake-pi fixtures**

```bash
# swift/DetDocCore/Tests/DetDocCoreTests/Support/fake-pi.sh
#!/usr/bin/env bash
# Minimal fake `pi --mode rpc` for PiProcessTransport tests.
# Ignores command contents; on the first `prompt` command, emits a canned plan and exits.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while IFS= read -r line; do
  case "$line" in
    *'"type":"prompt"'*)
      cat "$here/fake-pi-plan.jsonl"
      exit 0
      ;;
  esac
done
```

```text
# swift/DetDocCore/Tests/DetDocCoreTests/Support/fake-pi-plan.jsonl
{"type":"response","command":"set_thinking_level","success":true}
{"type":"response","command":"prompt","success":true}
{"type":"agent_start"}
{"type":"agent_end","messages":[{"role":"assistant","content":[{"type":"text","text":"{\"summary\":\"Fake plan\",\"changes\":[{\"reason\":\"doc-diff:docs/spec.md:L1-L2\",\"targetFiles\":[\"src/app.swift\"],\"kind\":\"modify\",\"rationale\":\"r\"}],\"questions\":[],\"risk\":\"low\"}"}],"usage":{"input":10,"output":5,"cacheRead":0,"cacheWrite":0}}]}
```

(The `.jsonl` carries the plan JSON as a once-escaped string inside the assistant text — one escaping level, since it lives in a file rather than a Swift literal. Each record is exactly one physical line.)

- [ ] **Step 2: Add the resources to the test target**

In `swift/DetDocCore/Package.swift`, change the `DetDocCoreTests` test target to:

```swift
        .testTarget(
            name: "DetDocCoreTests",
            dependencies: ["DetDocCore"],
            resources: [
                .copy("Support/fake-pi.sh"),
                .copy("Support/fake-pi-plan.jsonl"),
            ]
        ),
```

- [ ] **Step 3: Write the failing test**

```swift
// swift/DetDocCore/Tests/DetDocCoreTests/PiProcessTransportTests.swift
import Foundation
import Testing
@testable import DetDocCore

@Test func processTransportDrivesPlanThroughFakePi() async throws {
    let script = try #require(Bundle.module.url(forResource: "fake-pi", withExtension: "sh"))
    // Spawn the fake via bash so the resource's executable bit doesn't matter.
    let runner = PiAgentRunner(executable: "bash") { _, _, cwd in
        try PiProcessTransport(executable: "bash", arguments: [script.path], cwd: cwd)
    }
    let result = try await runner.plan(PlanRequest(mode: .run, input: "DIFF", config: .default,
                                                   cwd: FileManager.default.temporaryDirectory))
    #expect(result.plan.summary == "Fake plan")
    #expect(result.plan.changes.first?.targetFiles == ["src/app.swift"])
    #expect(result.usage.input == 10)
    #expect(result.usage.total == 15)
}
```

- [ ] **Step 4: Run the test to verify it fails, then passes**

Run: `cd swift/DetDocCore && swift test --filter PiProcessTransportTests`
Expected first run (before Step 1-2 are in place): FAIL — resource not found / `Bundle.module` unavailable.
After Steps 1-2: PASS (1 test).

- [ ] **Step 5: Full test sweep**

Run: `cd swift/DetDocCore && swift test`
Expected: PASS — all existing DetDocCore tests plus the 7 new Pi* files green.

- [ ] **Step 6: Commit**

```bash
git add swift/DetDocCore/Package.swift swift/DetDocCore/Tests/DetDocCoreTests/Support/fake-pi.sh swift/DetDocCore/Tests/DetDocCoreTests/Support/fake-pi-plan.jsonl swift/DetDocCore/Tests/DetDocCoreTests/PiProcessTransportTests.swift
git commit -m "test(core): PiProcessTransport integration via fake-pi script"
```

- [ ] **Step 7: Manual real-`pi` verification (record outcome; not automated)**

This is a manual smoke check — do it once, note the result in the PR description. It needs a real, authenticated `pi` on PATH and makes a live LLM call (costs tokens, non-deterministic), so it is intentionally not a CI test.

1. Confirm pi: `pi --version` (exit 0). DetDoc surfaces this via `PiHealth.isAvailable()`.
2. In a scratch git repo with `.detdoc/config.yml` (provider `pi-rpc`, the default) and a dirty Markdown doc, launch the app (Task 8) and start a **run**.
3. Confirm the plan gate shows a parsed plan (summary/changes), approval proceeds to implementation, the patch gate shows a diff touching only approved targets, and apply commits. If the model wraps the plan in prose/fences, `PiPlanParsing` still extracts it; if parsing fails, the run surfaces `PI_PLAN_PARSE_FAILED` — tighten the planning prompt wording if so.

---

## Task 8: Wire PiAgentRunner into the app via AgentRunnerFactory

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Agent/AgentRunnerFactory.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/AgentRunnerFactoryTests.swift`
- Modify: `swift/DetDocApp/Sources/WorkspaceView.swift:20-29`

**Interfaces:**
- Consumes: `AgentRunner`, `FakeAgentRunner` (Plan 2), `PiAgentRunner` (Tasks 5-6); `DetDocConfig.agent.provider` (Plan 1).
- Produces: `enum AgentRunnerFactory { static func make(config: DetDocConfig) -> any AgentRunner }`.

- [ ] **Step 1: Write the failing test**

```swift
// swift/DetDocCore/Tests/DetDocCoreTests/AgentRunnerFactoryTests.swift
import Foundation
import Testing
@testable import DetDocCore

@Test func factoryReturnsPiRunnerForDefaultProvider() {
    // Default config provider is "pi-rpc".
    #expect(AgentRunnerFactory.make(config: .default) is PiAgentRunner)
}

@Test func factoryReturnsFakeRunnerForFakeProvider() {
    var config = DetDocConfig.default
    config.agent.provider = "fake"
    #expect(AgentRunnerFactory.make(config: config) is FakeAgentRunner)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd swift/DetDocCore && swift test --filter AgentRunnerFactoryTests`
Expected: FAIL — `cannot find 'AgentRunnerFactory' in scope`.

- [ ] **Step 3: Write the factory**

```swift
// swift/DetDocCore/Sources/DetDocCore/Agent/AgentRunnerFactory.swift
import Foundation

/// Selects the `AgentRunner` implementation from config. Default (`pi-rpc`) drives the real
/// `pi` binary; `fake` keeps the deterministic offline runner for development without pi.
public enum AgentRunnerFactory {
    public static func make(config: DetDocConfig) -> any AgentRunner {
        switch config.agent.provider {
        case "fake":
            return FakeAgentRunner(target: "src/app.swift", content: "// generated by DetDoc\n")
        default:
            return PiAgentRunner()
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd swift/DetDocCore && swift test --filter AgentRunnerFactoryTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Wire the app to the factory**

In `swift/DetDocApp/Sources/WorkspaceView.swift`, replace the hardcoded fake in `init(root:)`:

```swift
        let config = (try? ConfigStore().load(root: root)) ?? .default
        let agent = AgentRunnerFactory.make(config: config)
        _workspace = State(initialValue: WorkspaceViewModel(root: root))
```

(Remove the previous `let agent = FakeAgentRunner(target: "src/app.swift", content: "// generated by DetDoc\n")` line; the rest of `init` is unchanged.)

- [ ] **Step 6: Build the app**

Run:
```bash
cd swift/DetDocApp && xcodegen generate && xcodebuild -project DetDocApp.xcodeproj -scheme DetDocApp -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Full test sweep**

Run: `cd swift/DetDocCore && swift test`
Expected: PASS — all DetDocCore tests green.

- [ ] **Step 8: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Agent/AgentRunnerFactory.swift swift/DetDocCore/Tests/DetDocCoreTests/AgentRunnerFactoryTests.swift swift/DetDocApp/Sources/WorkspaceView.swift
git commit -m "feat(app): select PiAgentRunner via AgentRunnerFactory (config provider)"
```

---

## Self-Review

**1. Spec coverage (design spec §"Agent Layer and pi Integration", §"Safety Model", §Migration step 7):**
- `PiAgentRunner` driving `pi` over LF-delimited JSONL `pi --mode rpc` → Tasks 1-6. ✓
- Two-phase protocol (read-only planning → scoped implementation) → planning tool set `read,grep,find,ls` vs implementation `…,bash,edit,write` (Task 5/6 `spawnArgs`), prompts (Task 3). ✓
- Validation-repair support (`supportsRepair == true`, `repairValidation`) → Task 6. ✓
- Tool narrowing via `--tools` as defense-in-depth → Task 5/6. ✓ Safety still rests on worktree isolation + `PatchValidator` (engine, existing) — the runner does not re-implement guards. ✓
- pi health probe (`pi --version`) → already exists (`PiHealth`, Plan 2); unchanged. ✓ (noted, no task needed)
- `FakeAgentRunner` retained for offline/tests → `AgentRunnerFactory` `fake` branch (Task 8). ✓
- "Single uncertain module isolated behind the protocol" → all pi specifics live under `Agent/PiRpc/`; selection via factory. ✓
- Open decision "Exact pi RPC wire schema" → pinned in "Pinned pi RPC Wire Schema" + Key Decision (text-JSON plan extraction). ✓

**2. Placeholder scan:** No TBD/“handle errors”/“similar to Task N”. Every code step shows complete code; no temporary scaffolding (`PiProcessTransport` is written in full in Task 5, so the runner's default factory compiles without a stub). ✓

**3. Type consistency:**
- `AgentRunner` protocol unchanged; `plan/implement/repairValidation/supportsRepair` signatures match Plan 2 exactly (`PlanRequest`→`AgentPlanResult`, `ImplementRequest`/`RepairRequest`→`AgentRunResult`). ✓
- `AgentPlanResult(plan:usage:)`, `AgentRunResult(usage:)`, `TokenUsage(input:output:cacheRead:cacheWrite:total:)`, `ProposedPlan`/`PlanChange`, `AgentImplementationProgress.{edit,write,bash}` all used per Plan 1/2 definitions. ✓
- `PiRpcTransport` method names (`send`/`events`/`finish`) identical across protocol, `FakePiTransport`, `PiProcessTransport`, and runner call sites. ✓
- `PiRpcCodec.{splitRecords,encode,drainCompleteRecords}`, `PiRpcEvent.decode`, `PiPlanParsing.{parsePlan,lastAssistantText,tokenUsage}`, `PiAgentPrompts.{planningPrompt,implementationPrompt,validationRepairPrompt}`, `PiAgentRunner.spawnArgs` referenced consistently between definition and tests. ✓
- New `DetDocError` codes used exactly where declared in Global Constraints. ✓

**Assumptions to confirm during execution (fix inline if reality differs, do not expand scope):**
- `DetDocConfig` exposes mutable `agent.provider`/`agent.model` and `paths.deny: [String]` (consistent with `SettingsViewModel` editing config and Plan 1 parity facts). If a field is immutable, construct the config via its initializer in the test instead of mutating.
- `swift test`/`swift build` are the core verification commands and `Bundle.module` is generated once the test target declares `resources`.
