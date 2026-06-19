import type { Command } from "commander";
import type { CliIO } from "../output.js";
import { loadConfig } from "../../core/config.js";
import { getNormalizedDocDiff } from "../../core/diff.js";
import { GitRepository } from "../../core/git.js";

export function registerDiffCommand(program: Command, io: CliIO): void {
  program
    .command("diff")
    .description("Print normalized documentation diff")
    .action(async () => {
      const cwd = process.cwd();
      const config = await loadConfig(cwd);
      const diff = await getNormalizedDocDiff(new GitRepository(cwd), config);
      io.stdout.write(diff);
    });
}
