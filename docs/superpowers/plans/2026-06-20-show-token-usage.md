# Run Token Usage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `detdoc run --show-token-usage` to print a final token usage summary for pi-backed run phases.

**Architecture:** Add small token-usage value types to the agent layer, return usage alongside agent plan/implementation calls, aggregate usage in `runFlow`, and let the run CLI format the summary only when the flag is present. Keep `apply` unchanged.

**Tech Stack:** TypeScript, Commander, Vitest, embedded `@earendil-works/pi-coding-agent` SDK.

## Global Constraints

- `--show-token-usage` applies only to `detdoc run`.
- `detdoc apply` must remain unchanged because saved-run apply does not call pi.
- Without `--show-token-usage`, run output must remain unchanged.
- Missing agent usage fields must be treated as zero and must not fail the command.
- Fake agent usage can be zero/empty for stable tests.

---

## File Structure

- Modify `src/core/agent/agent-runner.ts`: define `TokenUsage`, `AgentPlanResult`, `AgentRunResult`, and helper functions; update `AgentRunner` method signatures.
- Modify `src/core/agent/fake-agent-runner.ts`: return zero usage with fake plan/implementation/repair calls.
- Modify `src/core/agent/pi-sdk-runner.ts`: extract usage from `session.messages` after each `session.prompt(...)` and return it from agent methods.
- Modify `src/core/flow.ts`: aggregate phase usage and expose it in `FlowResult`.
- Modify `src/cli/commands/run.ts`: add `--show-token-usage`, format summary after normal result line when requested.
- Modify `tests/run-command-options.test.ts`: assert help includes the flag, assert summary appears only with the flag.

---

### Task 1: Agent usage result types and fake-agent behavior

**Files:**
- Modify: `src/core/agent/agent-runner.ts`
- Modify: `src/core/agent/fake-agent-runner.ts`
- Test: `tests/run-command-options.test.ts`

**Interfaces:**
- Produces: `TokenUsage`, `zeroTokenUsage()`, `addTokenUsage(a, b)`, `AgentPlanResult`, `AgentRunResult`.
- Produces: `AgentRunner.plan(request): Promise<AgentPlanResult>`.
- Produces: `AgentRunner.implement(request): Promise<AgentRunResult>`.
- Produces: `AgentRunner.repairValidation?(request): Promise<AgentRunResult>`.

- [ ] **Step 1: Write failing tests for CLI visibility and opt-in summary**

Add this test to `tests/run-command-options.test.ts` inside the existing `describe("run command options", ...)` block:

```ts
  it("documents token usage flag", async () => {
    const io = createTestIO();
    const code = await runCli(["node", "detdoc", "run", "--help"], io);

    expect(code).toBe(0);
    expect(io.stdoutText()).toContain("--show-token-usage");
  });
```

Add this helper near the existing tests to avoid repeating cwd/env setup:

```ts
async function runWithFakeAgentInFixture(args: string[]) {
  const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const value = 1;\n" });
  await initConfig(fixture.cwd);
  await writeFile(join(fixture.cwd, "docs/spec.md"), "new behavior\n", "utf8");

  const previousCwd = process.cwd();
  const previousFakeAgent = process.env.DETDOC_FAKE_AGENT;
  process.chdir(fixture.cwd);
  process.env.DETDOC_FAKE_AGENT = "1";
  try {
    const io = createTestIO();
    const code = await runCli(["node", "detdoc", ...args], io);
    return { code, io, fixture };
  } finally {
    process.chdir(previousCwd);
    if (previousFakeAgent === undefined) delete process.env.DETDOC_FAKE_AGENT;
    else process.env.DETDOC_FAKE_AGENT = previousFakeAgent;
  }
}
```

Add these tests:

```ts
  it("does not print token usage without the flag", async () => {
    const { code, io } = await runWithFakeAgentInFixture(["run", "--auto-approve"]);

    expect(code).toBe(0);
    expect(io.stdoutText()).toMatch(/Run .* saved/);
    expect(io.stdoutText()).not.toContain("Token usage:");
  });

  it("prints token usage with the flag", async () => {
    const { code, io } = await runWithFakeAgentInFixture(["run", "--auto-approve", "--show-token-usage"]);

    expect(code).toBe(0);
    expect(io.stdoutText()).toMatch(/Run .* saved/);
    expect(io.stdoutText()).toContain("Token usage:");
    expect(io.stdoutText()).toContain("plan: input 0, output 0, cache read 0, cache write 0, total 0");
    expect(io.stdoutText()).toContain("implement: input 0, output 0, cache read 0, cache write 0, total 0");
    expect(io.stdoutText()).toContain("total: input 0, output 0, cache read 0, cache write 0, total 0");
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test -- tests/run-command-options.test.ts`

Expected: FAIL because `--show-token-usage` is not registered and no token usage output exists.

- [ ] **Step 3: Add usage types to agent-runner**

In `src/core/agent/agent-runner.ts`, add these exports after `AgentImplementationProgressReporter`:

```ts
export interface TokenUsage {
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
  total: number;
}

export interface AgentPlanResult {
  plan: ProposedPlan;
  usage: TokenUsage;
}

export interface AgentRunResult {
  usage: TokenUsage;
}

export function zeroTokenUsage(): TokenUsage {
  return { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 };
}

export function addTokenUsage(left: TokenUsage, right: TokenUsage): TokenUsage {
  return {
    input: left.input + right.input,
    output: left.output + right.output,
    cacheRead: left.cacheRead + right.cacheRead,
    cacheWrite: left.cacheWrite + right.cacheWrite,
    total: left.total + right.total,
  };
}
```

Update the `AgentRunner` interface to:

```ts
export interface AgentRunner {
  plan(request: PlanRequest): Promise<AgentPlanResult>;
  implement(request: ImplementRequest): Promise<AgentRunResult>;
  repairValidation?(request: RepairValidationRequest): Promise<AgentRunResult>;
}
```

- [ ] **Step 4: Update fake agent to return zero usage**

In `src/core/agent/fake-agent-runner.ts`, import `zeroTokenUsage` and return structured results:

```ts
import type { AgentPlanResult, AgentRunResult, AgentRunner, ImplementRequest, PlanRequest, RepairValidationRequest } from "./agent-runner.js";
import { zeroTokenUsage } from "./agent-runner.js";
```

Change `plan` to return:

```ts
return { plan: this.planResult, usage: zeroTokenUsage() };
```

Change `implement` and `repairValidation` to end with:

```ts
return { usage: zeroTokenUsage() };
```

- [ ] **Step 5: Run typecheck to expose downstream signature errors**

Run: `npm run typecheck`

Expected: FAIL in `flow.ts` and `pi-sdk-runner.ts` because they still use the old agent method return shapes.

---

### Task 2: Aggregate flow usage and CLI output

**Files:**
- Modify: `src/core/flow.ts`
- Modify: `src/cli/commands/run.ts`
- Test: `tests/run-command-options.test.ts`

**Interfaces:**
- Consumes: `TokenUsage`, `zeroTokenUsage()`, `addTokenUsage()` from Task 1.
- Produces: `FlowResult.tokenUsage` with `{ plan, implement, repairValidation, total }`.
- Produces: `formatTokenUsageSummary(usage)` in `src/cli/commands/run.ts`.

- [ ] **Step 1: Update flow imports and result type**

In `src/core/flow.ts`, change the agent import to:

```ts
import { addTokenUsage, zeroTokenUsage, type AgentImplementationProgressEvent, type AgentRunner, type TokenUsage } from "./agent/agent-runner.js";
```

Add this interface after `FlowResult`:

```ts
export interface FlowTokenUsage {
  plan: TokenUsage;
  implement: TokenUsage;
  repairValidation: TokenUsage;
  total: TokenUsage;
}
```

Update `FlowResult` to include:

```ts
  tokenUsage: FlowTokenUsage;
```

- [ ] **Step 2: Add aggregation inside runFlow**

Near the start of `runFlow`, after `const cwd = input.cwd;`, add:

```ts
  const tokenUsage: FlowTokenUsage = {
    plan: zeroTokenUsage(),
    implement: zeroTokenUsage(),
    repairValidation: zeroTokenUsage(),
    total: zeroTokenUsage(),
  };
  const recordUsage = (phase: keyof Omit<FlowTokenUsage, "total">, usage: TokenUsage): void => {
    tokenUsage[phase] = addTokenUsage(tokenUsage[phase], usage);
    tokenUsage.total = addTokenUsage(tokenUsage.total, usage);
  };
```

Change planning to:

```ts
    const planResult = await input.agent.plan({ mode: input.mode, input: taskInput, config, cwd: worktree.path });
    recordUsage("plan", planResult.usage);
    const proposedPlan = validateProposedPlan(planResult.plan, { config, mode: input.mode });
```

Change implementation to:

```ts
    const implementResult = await input.agent.implement({
      mode: input.mode,
      input: taskInput,
      config,
      cwd: worktree.path,
      approvedPlan: proposedPlan,
      approvedTargets,
      progress: (event) => progress(input, { phase: "implement", message: agentActionMessage(event), runId: manifest.runId }),
    });
    recordUsage("implement", implementResult.usage);
```

Change repair to:

```ts
        const repairResult = await repairValidation.call(input.agent, {
          mode: input.mode,
          input: taskInput,
          config: worktreeConfig,
          cwd: worktree.path,
          approvedPlan: proposedPlan,
          approvedTargets,
          validationLog: validationFailureLog,
          attempt,
          progress: (event) => progress(input, { phase: "repair_validation", message: agentActionMessage(event), runId: manifest.runId }),
        });
        recordUsage("repairValidation", repairResult.usage);
```

Update both run returns to include `tokenUsage`:

```ts
return { runId: manifest.runId, applied: false, patch, tokenUsage };
```

and:

```ts
return { runId: manifest.runId, applied: true, patch, tokenUsage };
```

- [ ] **Step 3: Update createPlanFlow and non-agent flows**

In `createPlanFlow`, change planning to:

```ts
  const planResult = await input.agent.plan({ mode, input: taskInput, config, cwd });
  const plan = validateProposedPlan(planResult.plan, { config, mode });
```

In `applyRun` and `replayRun`, add zero usage to returned results:

```ts
const tokenUsage: FlowTokenUsage = {
  plan: zeroTokenUsage(),
  implement: zeroTokenUsage(),
  repairValidation: zeroTokenUsage(),
  total: zeroTokenUsage(),
};
```

Return `{ runId: input.runId, applied: true, patch, tokenUsage }` from both functions.

- [ ] **Step 4: Add run flag and formatter**

In `src/cli/commands/run.ts`, import `type FlowTokenUsage`:

```ts
import { runDocFlow, type FlowProgressReporter, type FlowTokenUsage } from "../../core/flow.js";
```

Extend `RunOptions`:

```ts
  showTokenUsage?: boolean;
```

Add formatter functions before `registerRunCommand`:

```ts
function formatNumber(value: number): string {
  return new Intl.NumberFormat("en-US").format(value);
}

function formatTokenUsageLine(label: string, usage: FlowTokenUsage[keyof FlowTokenUsage]): string {
  return `  ${label}: input ${formatNumber(usage.input)}, output ${formatNumber(usage.output)}, cache read ${formatNumber(usage.cacheRead)}, cache write ${formatNumber(usage.cacheWrite)}, total ${formatNumber(usage.total)}`;
}

export function formatTokenUsageSummary(usage: FlowTokenUsage): string[] {
  const lines = ["Token usage:", formatTokenUsageLine("plan", usage.plan), formatTokenUsageLine("implement", usage.implement)];
  if (usage.repairValidation.total > 0) lines.push(formatTokenUsageLine("repair validation", usage.repairValidation));
  lines.push(formatTokenUsageLine("total", usage.total));
  return lines;
}
```

Register the option:

```ts
    .option("--show-token-usage", "print final token usage summary")
```

After the existing run result line, add:

```ts
        if (options.showTokenUsage) {
          for (const line of formatTokenUsageSummary(result.tokenUsage)) writeLine(io.stdout, line);
        }
```

- [ ] **Step 5: Run focused tests**

Run: `npm test -- tests/run-command-options.test.ts`

Expected: still FAIL until `pi-sdk-runner.ts` returns the new shapes, but tests should now show fewer compile/runtime errors.

---

### Task 3: Extract usage from Pi SDK sessions

**Files:**
- Modify: `src/core/agent/pi-sdk-runner.ts`
- Test: `tests/pi-runner-smoke.test.ts`
- Test: `tests/run-command-options.test.ts`

**Interfaces:**
- Consumes: `AgentPlanResult`, `AgentRunResult`, `TokenUsage`, `zeroTokenUsage()`, `addTokenUsage()` from Task 1.
- Produces: `extractSessionTokenUsage(messages): TokenUsage` exported for unit/smoke testing if useful.

- [ ] **Step 1: Update imports and method signatures**

In `src/core/agent/pi-sdk-runner.ts`, change the agent-runner import to:

```ts
import {
  addTokenUsage,
  zeroTokenUsage,
  type AgentPlanResult,
  type AgentRunner,
  type AgentRunResult,
  type ImplementRequest,
  type PlanRequest,
  type RepairValidationRequest,
  type TokenUsage,
} from "./agent-runner.js";
```

Change `plan(request: PlanRequest): Promise<ProposedPlan>` to `plan(request: PlanRequest): Promise<AgentPlanResult>`.

Change `private async runImplementationPrompt(...): Promise<void>` to `Promise<AgentRunResult>`.

Change `implement` and `repairValidation` to return `Promise<AgentRunResult>`.

- [ ] **Step 2: Add robust usage extraction helpers**

Add these helpers near `extractLastAssistantText`:

```ts
function numberField(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function usageFromMessage(message: { role?: string; usage?: unknown }): TokenUsage {
  if (message.role !== "assistant" || !message.usage || typeof message.usage !== "object") return zeroTokenUsage();
  const usage = message.usage as { input?: unknown; output?: unknown; cacheRead?: unknown; cacheWrite?: unknown; totalTokens?: unknown; total?: unknown };
  const input = numberField(usage.input);
  const output = numberField(usage.output);
  const cacheRead = numberField(usage.cacheRead);
  const cacheWrite = numberField(usage.cacheWrite);
  const explicitTotal = numberField(usage.totalTokens) || numberField(usage.total);
  return {
    input,
    output,
    cacheRead,
    cacheWrite,
    total: explicitTotal || input + output + cacheRead + cacheWrite,
  };
}

export function extractSessionTokenUsage(messages: Array<{ role?: string; usage?: unknown }>): TokenUsage {
  return messages.reduce((total, message) => addTokenUsage(total, usageFromMessage(message)), zeroTokenUsage());
}
```

- [ ] **Step 3: Return usage from planning**

In `plan`, after `await session.prompt(buildPlanningPrompt(request));`, add:

```ts
      const usage = extractSessionTokenUsage(session.messages as Array<{ role?: string; usage?: unknown }>);
```

Return captured and parsed plans as:

```ts
      if (capturedPlan) return { plan: validateProposedPlan(capturedPlan, { config: request.config, mode: request.mode }), usage };

      const text = extractLastAssistantText(session.messages as Array<{ role?: string; content?: unknown }>);
      return { plan: validateProposedPlan(JSON.parse(text), { config: request.config, mode: request.mode }), usage };
```

- [ ] **Step 4: Return usage from implementation and repair**

In `runImplementationPrompt`, after `await session.prompt(prompt);`, add:

```ts
      return { usage: extractSessionTokenUsage(session.messages as Array<{ role?: string; usage?: unknown }>) };
```

Update callers:

```ts
  async implement(request: ImplementRequest): Promise<AgentRunResult> {
    return this.runImplementationPrompt(request, buildImplementationPrompt(request));
  }

  async repairValidation(request: RepairValidationRequest): Promise<AgentRunResult> {
    return this.runImplementationPrompt(request, buildValidationRepairPrompt(request));
  }
```

- [ ] **Step 5: Add helper unit coverage if compile allows direct import**

Add to `tests/pi-runner-smoke.test.ts`:

```ts
import { extractSessionTokenUsage } from "../src/core/agent/pi-sdk-runner.js";

it("extracts token usage from assistant messages", () => {
  const usage = extractSessionTokenUsage([
    { role: "user", usage: { input: 100 } },
    { role: "assistant", usage: { input: 10, output: 2, cacheRead: 3, cacheWrite: 4, totalTokens: 19 } },
    { role: "assistant", usage: { input: 5, output: 6 } },
  ]);

  expect(usage).toEqual({ input: 15, output: 8, cacheRead: 3, cacheWrite: 4, total: 30 });
});
```

- [ ] **Step 6: Run focused tests and typecheck**

Run: `npm test -- tests/pi-runner-smoke.test.ts tests/run-command-options.test.ts`

Expected: PASS.

Run: `npm run typecheck`

Expected: PASS.

---

### Task 4: Final verification and docs update

**Files:**
- Modify: `README.md`
- Test: all tests

**Interfaces:**
- Consumes: completed CLI flag and formatter from Tasks 1-3.
- Produces: user-facing documentation for `detdoc run --show-token-usage`.

- [ ] **Step 1: Document the flag**

In `README.md`, add `detdoc run [--auto-approve] [--auto-apply] [--show-token-usage]` in the command list.

Under the non-interactive shortcuts section, add:

```md
To inspect pi token usage for a run, add:

```bash
detdoc run --show-token-usage
```

The token usage summary is printed after the run result. `detdoc apply` does not expose this flag because applying a saved patch does not call pi.
```

- [ ] **Step 2: Run full verification**

Run: `npm test`

Expected: PASS.

Run: `npm run typecheck`

Expected: PASS.

Run: `npm run build`

Expected: PASS.

- [ ] **Step 3: Commit implementation**

```bash
git add src tests README.md docs/superpowers/plans/2026-06-20-show-token-usage.md
git commit -m "feat: show run token usage"
```

---

## Self-Review

- Spec coverage: Task 2 implements the run-only flag and final output; Task 3 implements Pi SDK usage extraction; Task 1 keeps fake-agent usage stable; Task 4 documents `apply` being unchanged.
- Placeholder scan: no TBD/TODO/fill-in placeholders remain.
- Type consistency: `TokenUsage`, `FlowTokenUsage`, `AgentPlanResult`, and `AgentRunResult` names are introduced before use and used consistently.
