import { Readable } from "node:stream";
import { describe, expect, it } from "vitest";
import { TerminalApprovalUI } from "../src/core/approval.js";
import { createTestIO } from "./helpers/test-io.js";

function stripAnsi(text: string): string {
  return text.replace(/\u001B\[[0-?]*[ -/]*[@-~]/g, "");
}

describe("TerminalApprovalUI", () => {
  it("renders plans in a boxed readable format instead of raw JSON", async () => {
    const io = createTestIO();
    const approval = new TerminalApprovalUI({
      ...io,
      stdin: Readable.from(["n\n"]),
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
    const plain = stripAnsi(output);
    expect(output).toContain("╭");
    expect(output).toContain("╰");
    expect(output).toContain("│");
    expect(output).toContain("\u001b[");
    expect(plain).toContain("DetDoc proposed plan");
    expect(plain).toContain("Summary: Bootstrap MusicPlayer");
    expect(plain).toContain("Risk: medium");
    expect(plain).toContain("1. create");
    expect(plain).toContain("Reason: doc-diff:docs/technical-spec.md:L13-L24");
    expect(plain).toContain("- project.yml");
    expect(plain).toContain("Rationale: XcodeGen project definition is required.");
    expect(output).not.toContain('"changes"');
    expect(output).not.toContain('"targetFiles"');
  });

  it("accepts y for plan approval", async () => {
    const io = createTestIO();
    const approval = new TerminalApprovalUI({
      ...io,
      stdin: Readable.from(["y\n"]),
      isInteractive: true,
    });

    await expect(
      approval.approvePlan({
        summary: "Approve with y",
        risk: "low",
        questions: [],
        changes: [
          {
            reason: "doc-diff:docs/spec.md:L1-L1",
            targetFiles: ["src/app.ts"],
            kind: "modify",
            rationale: "Test y approval.",
          },
        ],
      }),
    ).resolves.toBe(true);

    expect(io.stdoutText()).toContain("Approve this plan? [y/N]:");
  });
});
