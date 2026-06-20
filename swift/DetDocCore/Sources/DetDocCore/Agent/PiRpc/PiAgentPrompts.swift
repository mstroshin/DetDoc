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
