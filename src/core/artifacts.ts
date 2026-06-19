import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import type { RunManifest } from "./manifest.js";

export class ArtifactStore {
  constructor(readonly cwd: string) {}

  runDir(runId: string): string {
    return join(this.cwd, ".detdoc", "runs", runId);
  }

  async createRun(manifest: RunManifest): Promise<string> {
    const dir = this.runDir(manifest.runId);
    await mkdir(dir, { recursive: true });
    await this.writeJson(manifest.runId, "manifest.json", manifest);
    return dir;
  }

  async writeText(runId: string, name: string, content: string): Promise<void> {
    await writeFile(join(this.runDir(runId), name), content, "utf8");
  }

  async writeJson(runId: string, name: string, value: unknown): Promise<void> {
    await this.writeText(runId, name, `${JSON.stringify(value, null, 2)}\n`);
  }

  async readText(runId: string, name: string): Promise<string> {
    return readFile(join(this.runDir(runId), name), "utf8");
  }

  async readJson<T>(runId: string, name: string): Promise<T> {
    return JSON.parse(await this.readText(runId, name)) as T;
  }

  async deleteRun(runId: string): Promise<void> {
    await rm(this.runDir(runId), { recursive: true, force: true });
  }
}
