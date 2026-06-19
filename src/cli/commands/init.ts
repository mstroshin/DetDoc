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
      if (result.created) {
        writeLine(io.stdout, "Created .detdoc/config.yml");
      } else {
        writeLine(io.stdout, ".detdoc/config.yml already exists");
      }
    });
}
