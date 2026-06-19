import type { Command } from "commander";
import type { CliIO } from "../output.js";
import { writeLine } from "../output.js";
import { initConfig } from "../../core/config.js";

export function registerInitCommand(program: Command, io: CliIO): void {
  program
    .command("init")
    .description("Create .detdoc/config.yml")
    .action(async () => {
      const result = await initConfig(process.cwd());
      if (result.gitInitialized) {
        writeLine(io.stdout, "Initialized git repository");
      }
      if (result.created) {
        writeLine(io.stdout, "Created .detdoc/config.yml");
      } else {
        writeLine(io.stdout, ".detdoc/config.yml already exists");
      }
      if (result.docsCreated.length > 0) {
        writeLine(io.stdout, `Created starter docs: ${result.docsCreated.join(", ")}`);
      }
      if (result.initialCommitCreated) {
        writeLine(io.stdout, "Created initial commit: Initial DetDoc setup");
      }
    });
}
