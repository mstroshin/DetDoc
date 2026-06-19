import { describe, expect, it } from "vitest";
import { defaultConfig } from "../src/core/config.js";
import { PiSdkRunner } from "../src/core/agent/pi-sdk-runner.js";

const runSmoke = process.env.DETDOC_PI_SMOKE === "1";

describe.skipIf(!runSmoke)("PiSdkRunner smoke", () => {
  it("can be constructed and exposes AgentRunner methods", async () => {
    const runner = new PiSdkRunner();
    expect(typeof runner.plan).toBe("function");
    expect(typeof runner.implement).toBe("function");
    expect(defaultConfig().agent.provider).toBe("pi-sdk");
  });
});
