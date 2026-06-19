import { Command, CommanderError } from "commander";
import { registerApplyCommand } from "./commands/apply.js";
import { registerDiffCommand } from "./commands/diff.js";
import { registerFixCommand } from "./commands/fix.js";
import { registerInitCommand } from "./commands/init.js";
import { registerPlanCommand } from "./commands/plan.js";
import { registerReplayCommand } from "./commands/replay.js";
import { registerRunCommand } from "./commands/run.js";
import { defaultIO, type CliIO, writeLine } from "./output.js";
import { toErrorMessage } from "../core/errors.js";

function addCommand(program: Command, name: string, description: string): void {
  program
    .command(name)
    .description(description)
    .allowUnknownOption(false)
    .action(() => {
      throw new Error(`Command '${name}' is registered but not implemented in this build`);
    });
}

function isHelpDisplayed(error: unknown): boolean {
  return error instanceof CommanderError && error.code === "commander.helpDisplayed";
}

function isCommanderUsageError(error: unknown): error is CommanderError {
  return error instanceof CommanderError;
}

export async function runCli(argv: string[], io: CliIO = defaultIO()): Promise<number> {
  const program = new Command();
  program
    .name("detdoc")
    .description("Deterministic documentation-driven agent orchestration")
    .exitOverride()
    .configureOutput({
      writeOut: (text) => io.stdout.write(text),
      writeErr: (text) => io.stderr.write(text),
    });

  registerInitCommand(program, io);
  registerDiffCommand(program, io);
  registerPlanCommand(program, io);
  registerRunCommand(program, io);
  registerFixCommand(program, io);
  registerApplyCommand(program, io);
  registerReplayCommand(program, io);

  try {
    await program.parseAsync(argv);
    return 0;
  } catch (error) {
    if (isHelpDisplayed(error)) return 0;
    if (isCommanderUsageError(error)) return error.exitCode || 1;
    const message = toErrorMessage(error);
    writeLine(io.stderr, message);
    return 1;
  }
}
