import { mkdir, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { GitRepository } from "./git.js";

export interface TemporaryWorktree {
  path: string;
  repo: GitRepository;
  branchName?: string;
  cleanup(): Promise<void>;
}

export interface CreateWorktreeOptions {
  prefix?: string;
  path?: string;
  branchName?: string;
}

export class WorktreeManager {
  async createFromHead(baseRepo: GitRepository, options: CreateWorktreeOptions = {}): Promise<TemporaryWorktree> {
    const prefix = options.prefix ?? "detdoc-worktree-";
    const container = options.path ? undefined : await mkdtemp(join(tmpdir(), prefix));
    const path = options.path ?? join(container!, "worktree");
    const head = await baseRepo.headCommit();

    if (options.path) await mkdir(dirname(path), { recursive: true });

    if (options.branchName) {
      await baseRepo.git(["worktree", "add", "-b", options.branchName, path, head]);
    } else {
      await baseRepo.git(["worktree", "add", "--detach", path, head]);
    }

    const repo = new GitRepository(path);
    return {
      path,
      repo,
      branchName: options.branchName,
      cleanup: async () => {
        await baseRepo.git(["worktree", "remove", "--force", path]).catch(async () => {
          await rm(path, { recursive: true, force: true });
        });
        if (options.branchName) {
          await baseRepo.git(["branch", "-D", options.branchName]).catch(() => undefined);
        }
        if (container) await rm(container, { recursive: true, force: true });
      },
    };
  }
}
