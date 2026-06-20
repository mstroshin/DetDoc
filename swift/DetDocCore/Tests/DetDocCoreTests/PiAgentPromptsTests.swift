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
