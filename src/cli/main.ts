import { Command, CommanderError } from "commander";
import { registerInitCommand } from "./commands/init.js";
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
  addCommand(program, "diff", "Print normalized documentation diff");
  addCommand(program, "plan", "Create an approved implementation plan without applying code changes");
  addCommand(program, "run", "Run the documentation-diff workflow");
  addCommand(program, "fix", "Run the bugfix-intent workflow");
  addCommand(program, "apply", "Apply a saved DetDoc patch");
  addCommand(program, "replay", "Replay a saved DetDoc patch without calling an agent");

  try {
    await program.parseAsync(argv);
    return 0;
  } catch (error) {
    if (isHelpDisplayed(error)) return 0;
    const message = toErrorMessage(error);
    writeLine(io.stderr, message);
    return 1;
  }
}
