# Hidden doc↔code links — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a run implements code, DetDoc writes hidden `<!-- detdoc:link -->` comments into the run's input docs mapping each doc section to the `File.swift#symbol`s that implement it, hidden by default in the live preview with a toolbar toggle.

**Architecture:** The agent emits a `detdoc-links` fenced block at the end of its implement/repair turn (parsed like the existing plan output). The engine, after applying the patch to main and before committing, rewrites the input docs to carry a block of single-line HTML comments at EOF — so the links ride in the same `DetDoc apply` commit and don't trigger a phantom run. The live-preview delegate hides those comment lines unless a global toggle is on.

**Tech Stack:** Swift 6, SwiftPM (`DetDocCore`), SwiftUI + AppKit/TextKit 2 (`DetDocApp`), Swift Testing (`@Test`/`#expect`), pi over `--mode rpc`.

## Global Constraints

- Swift 6 toolchain; modules are `DetDocCore` (pure) and `DetDocApp` (SwiftUI).
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`) — not XCTest.
- Core tests run headless: `swift test --package-path swift/DetDocCore`.
- App build/test/preview go through the Xcode MCP workflow (module `DetDoc`); live GUI automation is unreliable — verify via tests + `RenderPreview`.
- Link granularity is **file + symbol** (`Path.ext#symbol`), never line numbers.
- Annotations are always written on apply (no config flag).
- Annotations are single-line HTML comments grouped at end-of-doc.
- Per `CLAUDE.md`: every new/changed SwiftUI view gets a Preview with multiple states and accessibility IDs.
- Docs are read-only to the agent's *patch* (`PatchValidator` rejects doc paths); only DetDoc writes links.

---

### Task 1: `CodeLink` model, in-file block, and viewer scanner (Core)

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Services/CodeLink.swift`
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/CodeLinkTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct CodeLink: Sendable, Equatable { public let docPath: String; public let heading: String; public let refs: [String] }`
  - `enum CodeLinkBlock` with:
    - `static func isLinkLine(_ line: String) -> Bool`
    - `static func serializeLine(_ link: CodeLink) -> String`
    - `static func apply(to markdown: String, links: [CodeLink]) -> String`
  - `enum CodeLinkScanner` with `static func scan(_ text: String) -> [NSRange]`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func serializeLineFormatsHeadingAndRefs() {
    let link = CodeLink(docPath: "docs/spec.md", heading: "## Plan approval",
                        refs: ["AppCoordinator.swift#approvePlan", "PlanGateView.swift#PlanGateView"])
    #expect(CodeLinkBlock.serializeLine(link)
        == #"<!-- detdoc:link "## Plan approval" AppCoordinator.swift#approvePlan PlanGateView.swift#PlanGateView -->"#)
}

@Test func isLinkLineDetectsOurComments() {
    #expect(CodeLinkBlock.isLinkLine(#"  <!-- detdoc:link "## H" a.swift#x -->  "#))
    #expect(!CodeLinkBlock.isLinkLine("## H"))
    #expect(!CodeLinkBlock.isLinkLine("<!-- a normal comment -->"))
}

@Test func applyAppendsBlockAtEndAndLeavesProseUntouched() {
    let md = "# Title\n\nSome prose.\n"
    let out = CodeLinkBlock.apply(to: md, links: [
        CodeLink(docPath: "d.md", heading: "## A", refs: ["a.swift#x"]),
    ])
    #expect(out == "# Title\n\nSome prose.\n\n<!-- detdoc:link \"## A\" a.swift#x -->\n")
}

@Test func applyIsIdempotent() {
    let md = "# Title\n\nSome prose.\n"
    let links = [CodeLink(docPath: "d.md", heading: "## A", refs: ["a.swift#x"])]
    let once = CodeLinkBlock.apply(to: md, links: links)
    let twice = CodeLinkBlock.apply(to: once, links: links)
    #expect(once == twice)
}

@Test func applyWithEmptyLinksStripsExistingBlock() {
    let md = "# Title\n\nSome prose.\n\n<!-- detdoc:link \"## A\" a.swift#x -->\n"
    #expect(CodeLinkBlock.apply(to: md, links: []) == "# Title\n\nSome prose.\n")
}

@Test func scanFindsCommentRange() {
    let para = #"<!-- detdoc:link "## A" a.swift#x -->"#
    let ranges = CodeLinkScanner.scan(para)
    #expect(ranges == [NSRange(location: 0, length: (para as NSString).length)])
}

@Test func scanIgnoresPlainText() {
    #expect(CodeLinkScanner.scan("just prose").isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path swift/DetDocCore --filter CodeLinkTests`
Expected: FAIL — `cannot find 'CodeLink' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

public struct CodeLink: Sendable, Equatable {
    public let docPath: String   // repo-relative .md the link belongs to ("" when parsed in-file)
    public let heading: String   // exact heading text incl. leading '#'s, e.g. "## Plan approval"
    public let refs: [String]    // "Path.ext#symbol" entries
    public init(docPath: String, heading: String, refs: [String]) {
        self.docPath = docPath; self.heading = heading; self.refs = refs
    }
}

/// Reads/writes the trailing block of `<!-- detdoc:link "<heading>" <refs…> -->`
/// comments inside a single Markdown document.
public enum CodeLinkBlock {
    public static func isLinkLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("<!--") && t.hasSuffix("-->") && t.contains("detdoc:link")
    }

    public static func serializeLine(_ link: CodeLink) -> String {
        "<!-- detdoc:link \"\(link.heading)\" \(link.refs.joined(separator: " ")) -->"
    }

    /// Idempotent: strips every existing link line + trailing blanks, then appends a
    /// fresh block (blank line + one comment per link + trailing newline). Empty
    /// `links` just strips. Prose above the block is preserved verbatim.
    public static func apply(to markdown: String, links: [CodeLink]) -> String {
        var lines = markdown.components(separatedBy: "\n").filter { !isLinkLine($0) }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        let body = lines.joined(separator: "\n")
        if links.isEmpty { return body.isEmpty ? "" : body + "\n" }
        let block = links.map(serializeLine).joined(separator: "\n")
        return body + "\n\n" + block + "\n"
    }
}

/// Finds full `<!-- detdoc:link … -->` spans inside one paragraph (for the viewer).
public enum CodeLinkScanner {
    public static func scan(_ text: String) -> [NSRange] {
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map(\.range)
    }
    // Pattern is static and known-valid; force-try is acceptable here (mirrors MarkdownStyleScanner).
    private static let regex = try! NSRegularExpression(pattern: #"<!--\s*detdoc:link\s+"[^"]*"[^>]*-->"#)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path swift/DetDocCore --filter CodeLinkTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Services/CodeLink.swift \
        swift/DetDocCore/Tests/DetDocCoreTests/CodeLinkTests.swift
git commit -m "feat(core): CodeLink model, in-file block writer, viewer scanner"
```

---

### Task 2: Parse the agent's `detdoc-links` fenced block + carry it on `AgentRunResult` (Core)

**Files:**
- Create: `swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiCodeLinkParsing.swift`
- Modify: `swift/DetDocCore/Sources/DetDocCore/Agent/AgentRunner.swift:50-53` (add `codeLinks` to `AgentRunResult`)
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/PiCodeLinkParsingTests.swift`

**Interfaces:**
- Consumes: `CodeLink` (Task 1).
- Produces:
  - `enum PiCodeLinkParsing { static func parseCodeLinks(fromAssistantText text: String) -> [CodeLink] }`
  - `AgentRunResult` gains `public let codeLinks: [CodeLink]` (default `[]`), keeping the existing `usage` init working.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func parsesFencedBlockWithDocHeadingAndRefs() {
    let text = """
    Done implementing.

    ```detdoc-links
    docs/spec.md ## Plan approval -> AppCoordinator.swift#approvePlan, PlanGateView.swift#PlanGateView
    docs/spec.md ## Patch gate -> AppCoordinator.swift#approveApply
    ```
    """
    let links = PiCodeLinkParsing.parseCodeLinks(fromAssistantText: text)
    #expect(links == [
        CodeLink(docPath: "docs/spec.md", heading: "## Plan approval",
                 refs: ["AppCoordinator.swift#approvePlan", "PlanGateView.swift#PlanGateView"]),
        CodeLink(docPath: "docs/spec.md", heading: "## Patch gate",
                 refs: ["AppCoordinator.swift#approveApply"]),
    ])
}

@Test func returnsEmptyWhenNoBlock() {
    #expect(PiCodeLinkParsing.parseCodeLinks(fromAssistantText: "no links here").isEmpty)
}

@Test func skipsMalformedLines() {
    let text = """
    ```detdoc-links
    garbage with no arrow
    docs/a.md ## H -> a.swift#x
    docs/b.md ## H ->
    ```
    """
    #expect(PiCodeLinkParsing.parseCodeLinks(fromAssistantText: text)
        == [CodeLink(docPath: "docs/a.md", heading: "## H", refs: ["a.swift#x"])])
}

@Test func agentRunResultDefaultsToNoCodeLinks() {
    #expect(AgentRunResult().codeLinks.isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path swift/DetDocCore --filter PiCodeLinkParsingTests`
Expected: FAIL — `cannot find 'PiCodeLinkParsing'` / no member `codeLinks`.

- [ ] **Step 3a: Add `codeLinks` to `AgentRunResult`**

In `Agent/AgentRunner.swift`, replace the `AgentRunResult` struct (lines 50-53):

```swift
public struct AgentRunResult: Sendable {
    public let usage: TokenUsage
    public let codeLinks: [CodeLink]
    public init(usage: TokenUsage = TokenUsage(), codeLinks: [CodeLink] = []) {
        self.usage = usage
        self.codeLinks = codeLinks
    }
}
```

- [ ] **Step 3b: Write the parser**

```swift
import Foundation

/// Extracts the optional `detdoc-links` fenced block pi emits at the end of an
/// implement/repair turn. Each line: `<docPath> <heading…> -> <ref>[, <ref>…]`.
public enum PiCodeLinkParsing {
    public static func parseCodeLinks(fromAssistantText text: String) -> [CodeLink] {
        guard let block = fencedBlock(text, lang: "detdoc-links") else { return [] }
        return block.split(separator: "\n").compactMap { raw -> CodeLink? in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let halves = line.components(separatedBy: " -> ")
            guard halves.count == 2 else { return nil }
            let left = halves[0].split(separator: " ", maxSplits: 1).map(String.init)
            guard left.count == 2 else { return nil }
            let docPath = left[0]
            let heading = left[1].trimmingCharacters(in: .whitespaces)
            let refs = halves[1].split(whereSeparator: { $0 == "," || $0 == " " })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !heading.isEmpty, !refs.isEmpty else { return nil }
            return CodeLink(docPath: docPath, heading: heading, refs: refs)
        }
    }

    /// Returns the contents between ```<lang> and the next ``` fence, or nil.
    static func fencedBlock(_ text: String, lang: String) -> String? {
        let ns = text as NSString
        let pattern = "```\(lang)\\n([\\s\\S]*?)```"
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path swift/DetDocCore --filter PiCodeLinkParsingTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiCodeLinkParsing.swift \
        swift/DetDocCore/Sources/DetDocCore/Agent/AgentRunner.swift \
        swift/DetDocCore/Tests/DetDocCoreTests/PiCodeLinkParsingTests.swift
git commit -m "feat(core): parse detdoc-links block; carry codeLinks on AgentRunResult"
```

---

### Task 3: Wire pi to request + return links; let `FakeAgentRunner` return links (Core)

**Files:**
- Modify: `swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiAgentPrompts.swift:48-80` (append link instruction to implement + repair prompts)
- Modify: `swift/DetDocCore/Sources/DetDocCore/Agent/PiRpc/PiAgentRunner.swift:50-58` (`runImplementation` parses + returns `codeLinks`)
- Modify: `swift/DetDocCore/Sources/DetDocCore/Agent/FakeAgentRunner.swift` (optional `codeLinks` to return)
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/FakeAgentRunnerCodeLinksTests.swift`

**Interfaces:**
- Consumes: `PiCodeLinkParsing` + `AgentRunResult.codeLinks` (Task 2).
- Produces:
  - `FakeAgentRunner.init(target:content:codeLinks:)` with `codeLinks: [CodeLink] = []`; `implement`/`repairValidation` return `AgentRunResult(codeLinks: codeLinks)`.
  - `PiAgentPrompts.linkInstruction` shared snippet appended to both prompts.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func fakeAgentReturnsConfiguredCodeLinks() async throws {
    let links = [CodeLink(docPath: "docs/idea.md", heading: "## A", refs: ["src/app.swift#run"])]
    let fake = FakeAgentRunner(target: "src/app.swift", content: "x\n", codeLinks: links)
    let req = ImplementRequest(mode: .run, input: "i", config: .default,
                               cwd: FileManager.default.temporaryDirectory,
                               approvedPlan: ProposedPlan(summary: "s",
                                   changes: [PlanChange(reason: "doc-diff:docs/idea.md:L1", targetFiles: ["src/app.swift"], kind: "modify", rationale: "r")],
                                   risk: "low"),
                               approvedTargets: ["src/app.swift"], progress: nil)
    let result = try await fake.implement(req)
    #expect(result.codeLinks == links)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path swift/DetDocCore --filter fakeAgentReturnsConfiguredCodeLinks`
Expected: FAIL — extra argument `codeLinks` in call.

- [ ] **Step 3a: Update `FakeAgentRunner`**

Replace the stored props + init and the two return sites:

```swift
public struct FakeAgentRunner: AgentRunner {
    private let target: String
    private let content: String
    private let codeLinks: [CodeLink]

    public init(target: String, content: String, codeLinks: [CodeLink] = []) {
        self.target = target
        self.content = content
        self.codeLinks = codeLinks
    }
    // ...
    public func implement(_ request: ImplementRequest) async throws -> AgentRunResult {
        guard request.approvedTargets.contains(target) else {
            throw DetDocError("FAKE_UNAPPROVED_WRITE", "FakeAgentRunner attempted unapproved write: \(target)")
        }
        try writeTarget(into: request.cwd)
        request.progress?(.write(path: target))
        return AgentRunResult(codeLinks: codeLinks)
    }

    public func repairValidation(_ request: RepairRequest) async throws -> AgentRunResult {
        try writeTarget(into: request.base.cwd)
        return AgentRunResult(codeLinks: codeLinks)
    }
```

- [ ] **Step 3b: Append the link instruction to the pi prompts**

In `PiAgentPrompts.swift`, add a shared snippet and append it to both `implementationPrompt` and `validationRepairPrompt` (as the final array element before `joined`):

```swift
static let linkInstruction = [
    "After finishing, output a fenced code block tagged `detdoc-links` mapping each",
    "documentation section you implemented to the code that implements it.",
    "One line per section: `<doc-path> <heading> -> <File.ext#symbol>[, <File.ext#symbol>…]`.",
    "Use the exact heading text from the docs (including leading #), repo-relative code",
    "paths, and symbol names (function/type/method) — never line numbers.",
    "Only include documentation sections actually realized by this change. If none, omit the block.",
    "Example:",
    "```detdoc-links",
    "docs/spec.md ## Plan approval -> AppCoordinator.swift#approvePlan, PlanGateView.swift#PlanGateView",
    "```",
].joined(separator: "\n")
```

Then in each prompt builder, add `linkInstruction` as the last element of the array passed to `.joined(separator: "\n\n")`.

- [ ] **Step 3c: Parse links in `PiAgentRunner.runImplementation`**

Replace the return (line 57):

```swift
let messages = try await drive(transport, thinking: request.config.agent.thinking, prompt: prompt, progress: progress)
let links = PiCodeLinkParsing.parseCodeLinks(fromAssistantText: PiPlanParsing.lastAssistantText(messages))
return AgentRunResult(usage: PiPlanParsing.tokenUsage(messages), codeLinks: links)
```

- [ ] **Step 4: Run the full core suite**

Run: `swift test --package-path swift/DetDocCore`
Expected: PASS (new test + no regressions; `PiAgentPromptsTests` may assert prompt contents — if it pins an exact prompt string, update it to include the new instruction).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Agent
git add swift/DetDocCore/Tests/DetDocCoreTests/FakeAgentRunnerCodeLinksTests.swift
git commit -m "feat(core): pi requests+returns detdoc-links; FakeAgentRunner can emit them"
```

---

### Task 4: Engine writes the link block into input docs before commit (Core)

**Files:**
- Modify: `swift/DetDocCore/Sources/DetDocCore/Engine/DetDocEngine.swift:170-224` (capture implement/repair result; add `writeCodeLinks` before `commitOrStage`)
- Test: `swift/DetDocCore/Tests/DetDocCoreTests/FlowCodeLinksTests.swift`

**Interfaces:**
- Consumes: `AgentRunResult.codeLinks` (Task 2), `CodeLinkBlock.apply` (Task 1), `PathPolicy.isDoc`, `GitRepository.statusPorcelain`/`.cwd`.
- Produces: a private `writeCodeLinks(_:mainRepo:config:)` on `DetDocEngine`; no change to public API. After a run, the committed input doc contains the link block.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import DetDocCore

@Test func runFlowWritesCodeLinkBlockIntoInputDoc() async throws {
    let fx = try await GitFixture()
    try ConfigStore().initFiles(root: fx.root)
    try await fx.commitAll("detdoc init")
    try fx.write("docs/idea.md", "# Idea\n\nDo the thing.\n")   // dirty doc drives the run

    let links = [CodeLink(docPath: "docs/idea.md", heading: "# Idea", refs: ["src/app.swift#run"])]
    let engine = DetDocEngine(root: fx.root,
                              agent: FakeAgentRunner(target: "src/app.swift", content: "let v = 1\n", codeLinks: links))

    let stream = await engine.start(mode: .run, message: nil)
    var applied = false
    for try await event in stream {
        switch event {
        case .planReady: await engine.submitPlanDecision(.approve)
        case .patchReady: await engine.submitApplyDecision(.apply)
        case .complete(let r): applied = r.applied
        default: break
        }
    }
    #expect(applied)

    let doc = try String(contentsOf: fx.root.appendingPathComponent("docs/idea.md"), encoding: .utf8)
    #expect(doc.contains(#"<!-- detdoc:link "# Idea" src/app.swift#run -->"#))
    #expect(doc.hasPrefix("# Idea\n\nDo the thing.\n"))   // prose preserved

    let status = try await fx.repo.statusPorcelain()
    #expect(status.isEmpty)   // links committed; tree clean
}

@Test func runFlowDropsLinksForDocsNotInInput() async throws {
    let fx = try await GitFixture()
    try ConfigStore().initFiles(root: fx.root)
    try fx.write("docs/other.md", "# Other\n")
    try await fx.commitAll("detdoc init")            // other.md committed, NOT dirty
    try fx.write("docs/idea.md", "# Idea\n")          // only idea.md drives the run

    let links = [CodeLink(docPath: "docs/other.md", heading: "# Other", refs: ["src/app.swift#run"])]
    let engine = DetDocEngine(root: fx.root,
                              agent: FakeAgentRunner(target: "src/app.swift", content: "x\n", codeLinks: links))
    let stream = await engine.start(mode: .run, message: nil)
    for try await event in stream {
        switch event {
        case .planReady: await engine.submitPlanDecision(.approve)
        case .patchReady: await engine.submitApplyDecision(.apply)
        default: break
        }
    }
    let other = try String(contentsOf: fx.root.appendingPathComponent("docs/other.md"), encoding: .utf8)
    #expect(!other.contains("detdoc:link"))   // not in input diff → untouched
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path swift/DetDocCore --filter FlowCodeLinks`
Expected: FAIL — doc does not contain the link comment.

- [ ] **Step 3a: Capture the final agent result**

In `runInsideWorktree`, change the implement call (line ~170) and the repair call (line ~194) to keep the latest result:

```swift
emit(.progress(phase: .implement, message: "Agent is editing approved files"))
var agentResult = try await agent.implement(ImplementRequest(mode: mode, input: taskInput, config: config, cwd: worktree.path,
                                                             approvedPlan: proposed, approvedTargets: approvedTargets, progress: nil))
```

and in the repair branch:

```swift
agentResult = try await agent.repairValidation(RepairRequest(base: base, validationLog: error.message, attempt: attempt))
```

- [ ] **Step 3b: Write the links before commit**

Immediately after `runPostApplyValidation(...)` and before the `commit` progress emit / `commitOrStage(...)`:

```swift
try await writeCodeLinks(agentResult.codeLinks, mainRepo: mainRepo, config: config)
```

Add the helper to `DetDocEngine` (alongside the other private methods):

```swift
/// Write the agent's doc→code links as a trailing HTML-comment block into each input
/// doc, idempotently. Restricted to docs that are part of this run's input (currently
/// dirty docs in main), so the agent can't annotate unrelated files. Staged by the
/// subsequent `git add -A`, so links land in the same `DetDoc apply` commit.
private func writeCodeLinks(_ links: [CodeLink], mainRepo: GitRepository, config: DetDocConfig) async throws {
    guard !links.isEmpty else { return }
    let policy = PathPolicy(config: config)
    let inputDocs = Set(try await mainRepo.statusPorcelain().map(\.path).filter { policy.isDoc($0) })
    for (docPath, docLinks) in Dictionary(grouping: links.filter { inputDocs.contains($0.docPath) }, by: \.docPath) {
        let url = mainRepo.cwd.appendingPathComponent(docPath)
        guard let original = try? String(contentsOf: url, encoding: .utf8) else { continue }
        let updated = CodeLinkBlock.apply(to: original, links: docLinks)
        if updated != original { try updated.write(to: url, atomically: true, encoding: .utf8) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path swift/DetDocCore --filter FlowCodeLinks`
Then full suite: `swift test --package-path swift/DetDocCore`
Expected: PASS (2 new tests + no regressions).

- [ ] **Step 5: Commit**

```bash
git add swift/DetDocCore/Sources/DetDocCore/Engine/DetDocEngine.swift \
        swift/DetDocCore/Tests/DetDocCoreTests/FlowCodeLinksTests.swift
git commit -m "feat(core): write doc->code link block into input docs on apply"
```

---

### Task 5: Hide/show links in the live preview + toolbar toggle (App)

**Files:**
- Modify: `swift/DetDocApp/Sources/Workspace/Docs/LivePreviewTextView.swift` (add `showCodeLinks`; hide/dim `detdoc:link` paragraphs; refresh-all on toggle)
- Modify: `swift/DetDocApp/Sources/Workspace/Docs/DocEditorScreen.swift` (header toggle bound to `@AppStorage`; thread `showCodeLinks` into `LivePreviewTextView`; Preview states + a11y IDs)

**Interfaces:**
- Consumes: `CodeLinkScanner.scan` (Task 1, from `DetDocCore`).
- Produces: `LivePreviewTextView` gains `var showCodeLinks: Bool`; `DocEditorScreen` owns `@AppStorage("showCodeLinks") var showCodeLinks = false`.

- [ ] **Step 1: Add `showCodeLinks` to the representable + coordinator**

In `LivePreviewTextView` add the stored property and thread it to the coordinator:

```swift
struct LivePreviewTextView: NSViewRepresentable {
    @Bindable var editor: DocEditorViewModel
    var resolver: DocLinkResolver
    var imageImporter: DocImageImporter
    var candidatesProvider: () -> [DocCandidate]
    var onFollowLink: (String) -> Void
    var showCodeLinks: Bool = false
    // ...
}
```

Pass it into `makeCoordinator()` (add a `showCodeLinks` param + stored `var showCodeLinks` on `Coordinator`, defaulting in `init`), and in `updateNSView` refresh all paragraphs when it changes:

```swift
func updateNSView(_ nsView: NSScrollView, context: Context) {
    // ...existing assignments...
    let changed = context.coordinator.showCodeLinks != showCodeLinks
    context.coordinator.showCodeLinks = showCodeLinks
    guard let tv = nsView.documentView as? NSTextView else { return }
    if tv.string != editor.source { tv.string = editor.source }
    if changed { context.coordinator.refreshAllParagraphs() }
}
```

Add to `Coordinator`:

```swift
var showCodeLinks = false

func refreshAllParagraphs() {
    guard let storage = textView?.textStorage else { return }
    storage.beginEditing()
    storage.edited(.editedAttributes, range: NSRange(location: 0, length: storage.length), changeInLength: 0)
    storage.endEditing()
}
```

- [ ] **Step 2: Hide/dim link comments in the paragraph delegate**

In `textContentStorage(_:textParagraphWith:)`, after computing `spans/refs/imageRefs`, scan for link ranges and include them in the early-out and modifications:

```swift
let codeLinkRanges = CodeLinkScanner.scan(raw.string)
if spans.isEmpty && refs.isEmpty && imageRefs.isEmpty && codeLinkRanges.isEmpty { return nil }
```

Then, after the heading/bold/italic loop (and before applying `modifications`), handle the link ranges:

```swift
for r in codeLinkRanges {
    if showCodeLinks {
        display.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: r)
        display.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), range: r)
    } else {
        modifications.append((range: r, replacement: nil))   // delete from display
    }
}
```

(The existing highest-offset-first `modifications` loop deletes them when hidden.)

- [ ] **Step 3: Toggle in `DocEditorScreen` + thread the flag**

```swift
import SwiftUI
import DetDocCore

struct DocEditorScreen: View {
    @Bindable var editor: DocEditorViewModel
    var resolver: DocLinkResolver
    var imageImporter: DocImageImporter
    var candidatesProvider: () -> [DocCandidate]
    var onFollowLink: (String) -> Void
    @AppStorage("showCodeLinks") private var showCodeLinks = false

    var body: some View {
        Group {
            if editor.selectedPath == nil {
                ContentUnavailableView("Select a document", systemImage: "doc.text",
                                       description: Text("Pick a Markdown file from the sidebar."))
                    .accessibilityIdentifier("doc-editor-empty")
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Toggle("Show code links", isOn: $showCodeLinks)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .accessibilityIdentifier("toggle-show-code-links")
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    Divider()
                    LivePreviewTextView(editor: editor, resolver: resolver,
                                        imageImporter: imageImporter,
                                        candidatesProvider: candidatesProvider,
                                        onFollowLink: onFollowLink,
                                        showCodeLinks: showCodeLinks)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("doc-editor-live-preview")
                }
            }
        }
    }
}
```

- [ ] **Step 4: Add Preview states** (per `CLAUDE.md`)

Append two `#Preview`s to `DocEditorScreen.swift`. `DocEditorViewModel(root:config:)` reads `source` from disk on `open`, so the helper writes a seeded `.md` (with a `detdoc:link` line) into a temp dir, then opens it. The toggle reads `@AppStorage("showCodeLinks")`, so the "shown" preview seeds `UserDefaults` before building the view.

```swift
@MainActor private func previewScreen(showLinks: Bool) -> some View {
    UserDefaults.standard.set(showLinks, forKey: "showCodeLinks")
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("detdoc-preview-\(showLinks)", isDirectory: true)
    let docs = dir.appendingPathComponent("docs", isDirectory: true)
    try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
    let md = "# Idea\n\nDo the thing.\n\n<!-- detdoc:link \"# Idea\" src/app.swift#run -->\n"
    try? md.write(to: docs.appendingPathComponent("idea.md"), atomically: true, encoding: .utf8)
    let editor = DocEditorViewModel(root: dir, config: .default)
    editor.open("docs/idea.md")
    return DocEditorScreen(editor: editor,
                           resolver: DocLinkResolver(candidates: []),
                           imageImporter: DocImageImporter(root: dir),
                           candidatesProvider: { [] },
                           onFollowLink: { _ in })
        .frame(width: 600, height: 400)
}

#Preview("Code links hidden") { previewScreen(showLinks: false) }
#Preview("Code links shown")  { previewScreen(showLinks: true) }
```

- [ ] **Step 5: Build + render previews via Xcode MCP**

- Build the `DetDoc` scheme (Xcode MCP `BuildProject`); fix any errors.
- `RenderPreview` both `DocEditorScreen` previews; confirm the link line is absent in "hidden" and present (dimmed, smaller) in "shown".
- Run the app view-model tests (`RunSomeTests` for `DocEditorViewModelTests`) to confirm no regressions.

- [ ] **Step 6: Commit**

```bash
git add swift/DetDocApp/Sources/Workspace/Docs/LivePreviewTextView.swift \
        swift/DetDocApp/Sources/Workspace/Docs/DocEditorScreen.swift
git commit -m "feat(app): hide/show doc->code links in live preview with toolbar toggle"
```

---

## Self-Review

**Spec coverage:**
- Annotation format (single-line HTML comment, EOF block) → Task 1 (`serializeLine`/`apply`).
- Map from the agent (folded into implement/repair, fenced block) → Tasks 2 + 3.
- `AgentRunResult.codeLinks` → Task 2.
- Engine write-step before commit, restricted to input docs, idempotent, same commit → Task 4.
- Preview hide (default) / show (dimmed text, no nav) + global `@AppStorage` toggle → Task 5.
- file#symbol granularity, always-on, only input docs → enforced in Tasks 1/3/4.
- Edge cases (no links strip; heading-not-found still serializes; repair uses final result; pre-existing block replaced) → covered by `apply` (Task 1) + capturing the latest `agentResult` (Task 4).
- Tests: round-trip/idempotency (T1), parsing (T2), fake returns links (T3), engine commit + non-input untouched (T4), previews (T5).

**Placeholder scan:** Two spots intentionally reference existing local patterns rather than hard-coding them (the config factory in T3 Step 1, and the `DocEditorViewModel`/`#Preview` construction in T5 Step 4) — both name the exact grep to find the established form. Everything else is concrete code.

**Type consistency:** `CodeLink(docPath:heading:refs:)`, `CodeLinkBlock.{isLinkLine,serializeLine,apply}`, `CodeLinkScanner.scan`, `PiCodeLinkParsing.parseCodeLinks`, `AgentRunResult(usage:codeLinks:)`, `FakeAgentRunner(target:content:codeLinks:)`, `LivePreviewTextView.showCodeLinks`, `Coordinator.refreshAllParagraphs()` — names are used identically across tasks.
