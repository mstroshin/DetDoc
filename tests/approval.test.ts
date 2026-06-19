import { Readable } from "node:stream";
import { describe, expect, it } from "vitest";
import { TerminalApprovalUI } from "../src/core/approval.js";
import { createTestIO } from "./helpers/test-io.js";

describe("TerminalApprovalUI", () => {
  it("renders plans in a boxed readable format instead of raw JSON", async () => {
    const io = createTestIO();
    const approval = new TerminalApprovalUI({
      ...io,
      stdin: Readable.from(["no\n"]),
      isInteractive: true,
    });

    await approval.approvePlan({
      summary: "Bootstrap MusicPlayer",
      risk: "medium",
      questions: [],
      changes: [
        {
          reason: "doc-diff:docs/technical-spec.md:L13-L24",
          targetFiles: ["project.yml"],
          kind: "create",
          rationale: "XcodeGen project definition is required.",
        },
        {
          reason: "doc-diff:docs/features/main_screen.md:L1-L1",
          targetFiles: ["Sources/MusicPlayerShared/MainScreenView.swift", "Sources/MusicPlayerShared/MainScreenViewModel.swift"],
          kind: "create",
          rationale: "The main screen needs a centered title.",
        },
      ],
    });

    const output = io.stdoutText();
    expect(output).toContain("╭");
    expect(output).toContain("╰");
    expect(output).toContain("│");
    expect(output).toContain("DetDoc proposed plan");
    expect(output).toContain("Summary: Bootstrap MusicPlayer");
    expect(output).toContain("Risk: medium");
    expect(output).toContain("1. create");
    expect(output).toContain("Reason: doc-diff:docs/technical-spec.md:L13-L24");
    expect(output).toContain("- project.yml");
    expect(output).toContain("Rationale: XcodeGen project definition is required.");
    expect(output).not.toContain('"changes"');
    expect(output).not.toContain('"targetFiles"');
  });
});
