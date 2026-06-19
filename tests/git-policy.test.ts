import { writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { defaultConfig } from "../src/core/config.js";
import { DetDocError } from "../src/core/errors.js";
import { GitRepository } from "../src/core/git.js";
import { assertFixDirtyPolicy, assertRunDirtyPolicy, isDeniedPath, isDocPath } from "../src/core/paths.js";
import { cleanupFixtures, createGitFixture } from "./helpers/git-fixture.js";

afterEach(cleanupFixtures);

describe("path matching", () => {
  it("classifies docs and denied paths", () => {
    const config = defaultConfig();
    expect(isDocPath("docs/spec.md", config)).toBe(true);
    expect(isDocPath("README.md", config)).toBe(true);
    expect(isDocPath("src/index.ts", config)).toBe(false);
    expect(isDocPath(".detdoc/runs/x.md", config)).toBe(false);

    expect(isDeniedPath(".env", config)).toBe(true);
    expect(isDeniedPath(".env.local", config)).toBe(true);
    expect(isDeniedPath("node_modules/pkg/index.js", config)).toBe(true);
    expect(isDeniedPath("src/index.ts", config)).toBe(false);
  });
});

describe("dirty-state policy", () => {
  it("allows run when only docs are dirty", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const x = 1;\n" });
    await writeFile(join(fixture.cwd, "docs/spec.md"), "new\n", "utf8");

    await expect(assertRunDirtyPolicy(new GitRepository(fixture.cwd), defaultConfig())).resolves.toEqual([
      { path: "docs/spec.md", status: " M" },
    ]);
  });

  it("rejects run when code is dirty", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const x = 1;\n" });
    await writeFile(join(fixture.cwd, "src/app.ts"), "export const x = 2;\n", "utf8");

    await expect(assertRunDirtyPolicy(new GitRepository(fixture.cwd), defaultConfig())).rejects.toThrow(DetDocError);
  });

  it("allows fix with dirty docs but rejects dirty code", async () => {
    const fixture = await createGitFixture({ "docs/spec.md": "old\n", "src/app.ts": "export const x = 1;\n" });
    await writeFile(join(fixture.cwd, "docs/spec.md"), "new\n", "utf8");
    await expect(assertFixDirtyPolicy(new GitRepository(fixture.cwd), defaultConfig())).resolves.toEqual([
      { path: "docs/spec.md", status: " M" },
    ]);

    await writeFile(join(fixture.cwd, "src/app.ts"), "export const x = 2;\n", "utf8");
    await expect(assertFixDirtyPolicy(new GitRepository(fixture.cwd), defaultConfig())).rejects.toThrow("dirty non-documentation changes");
  });
});
