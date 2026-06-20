import { describe, expect, it } from "vitest";
import { defaultConfig } from "../src/core/config.js";
import { extractSessionTokenUsage, PiSdkRunner } from "../src/core/agent/pi-sdk-runner.js";

const runSmoke = process.env.DETDOC_PI_SMOKE === "1";

describe("PiSdkRunner usage helpers", () => {
  it("extracts token usage from assistant messages", () => {
    const usage = extractSessionTokenUsage([
      { role: "user", usage: { input: 100 } },
      { role: "assistant", usage: { input: 10, output: 2, cacheRead: 3, cacheWrite: 4, totalTokens: 19 } },
      { role: "assistant", usage: { input: 5, output: 6 } },
    ]);

    expect(usage).toEqual({ input: 15, output: 8, cacheRead: 3, cacheWrite: 4, total: 30 });
  });
});

describe.skipIf(!runSmoke)("PiSdkRunner smoke", () => {
  it("can be constructed and exposes AgentRunner methods", async () => {
    const runner = new PiSdkRunner();
    expect(typeof runner.plan).toBe("function");
    expect(typeof runner.implement).toBe("function");
    expect(defaultConfig().agent.provider).toBe("pi-sdk");
  });
});
