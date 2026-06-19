import { execFile } from "node:child_process";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const fixtureDirs: string[] = [];

export interface GitFixture {
  cwd: string;
  git(args: string[]): Promise<{ stdout: string; stderr: string }>;
}

export async function cleanupFixtures(): Promise<void> {
  await Promise.all(fixtureDirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })));
}

export async function createGitFixture(files: Record<string, string>): Promise<GitFixture> {
  const cwd = await mkdtemp(join(tmpdir(), "detdoc-git-"));
  fixtureDirs.push(cwd);

  const git = async (args: string[]) => {
    const { stdout, stderr } = await execFileAsync("git", args, {
      cwd,
      env: {
        ...process.env,
        GIT_AUTHOR_NAME: "DetDoc Test",
        GIT_AUTHOR_EMAIL: "detdoc@example.com",
        GIT_COMMITTER_NAME: "DetDoc Test",
        GIT_COMMITTER_EMAIL: "detdoc@example.com",
      },
    });
    return { stdout, stderr };
  };

  await git(["init", "-b", "main"]);
  await git(["config", "user.name", "DetDoc Test"]);
  await git(["config", "user.email", "detdoc@example.com"]);

  for (const [path, content] of Object.entries(files)) {
    const absolute = join(cwd, path);
    await mkdir(dirname(absolute), { recursive: true });
    await writeFile(absolute, content, "utf8");
  }

  await git(["add", "."]);
  await git(["commit", "-m", "initial"]);

  return { cwd, git };
}
