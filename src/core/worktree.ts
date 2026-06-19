import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { GitRepository } from "./git.js";

export interface TemporaryWorktree {
  path: string;
  repo: GitRepository;
  cleanup(): Promise<void>;
}

export class WorktreeManager {
  async createFromHead(baseRepo: GitRepository, options: { prefix?: string } = {}): Promise<TemporaryWorktree> {
    const prefix = options.prefix ?? "detdoc-worktree-";
    const container = await mkdtemp(join(tmpdir(), prefix));
    const path = join(container, "worktree");
    const head = await baseRepo.headCommit();
    await baseRepo.git(["worktree", "add", "--detach", path, head]);

    const repo = new GitRepository(path);
    return {
      path,
      repo,
      cleanup: async () => {
        await baseRepo.git(["worktree", "remove", "--force", path]).catch(async () => {
          await rm(path, { recursive: true, force: true });
        });
        await rm(container, { recursive: true, force: true });
      },
    };
  }
}
