import { describe, expect, it } from "vitest";
import { createTestIO } from "./helpers/test-io.js";
import { runCli } from "../src/cli/main.js";

describe("CLI skeleton", () => {
  it("prints help with the MVP commands", async () => {
    const io = createTestIO();
    const code = await runCli(["node", "detdoc", "--help"], io);

    expect(code).toBe(0);
    expect(io.stdoutText()).toContain("Usage: detdoc");
    expect(io.stdoutText()).toContain("init");
    expect(io.stdoutText()).toContain("diff");
    expect(io.stdoutText()).toContain("plan");
    expect(io.stdoutText()).toContain("run");
    expect(io.stdoutText()).toContain("fix");
    expect(io.stdoutText()).toContain("apply");
    expect(io.stdoutText()).toContain("replay");
  });

  it("returns a non-zero code for unknown commands", async () => {
    const io = createTestIO();
    const code = await runCli(["node", "detdoc", "unknown"], io);

    expect(code).toBe(1);
    expect(io.stderrText()).toContain("unknown command");
  });
});
