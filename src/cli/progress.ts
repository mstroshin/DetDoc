import ora, { type Ora } from "ora";
import type { FlowProgressEvent, FlowProgressReporter } from "../core/flow.js";
import type { CliIO } from "./output.js";
import { writeLine } from "./output.js";

function isFinalEvent(event: FlowProgressEvent): boolean {
  return event.phase === "done";
}

function isApprovalEvent(event: FlowProgressEvent): boolean {
  return event.phase === "approve_plan" || event.phase === "approve_patch";
}

function createFallbackProgressReporter(io: CliIO): FlowProgressReporter {
  return (event) => {
    const prefix = isFinalEvent(event) ? "✓" : "◇";
    writeLine(io.stderr, `${prefix} ${event.message}`);
  };
}

export interface RunProgressController {
  report: FlowProgressReporter;
  fail(message?: string): void;
}

export function createRunProgressController(io: CliIO): RunProgressController {
  if (!io.isInteractive) {
    return {
      report: createFallbackProgressReporter(io),
      fail(message = "Run failed") {
        writeLine(io.stderr, `✖ ${message}`);
      },
    };
  }

  let spinner: Ora | undefined;

  return {
    report(event) {
      if (isFinalEvent(event)) {
        if (spinner?.isSpinning) spinner.succeed(event.message);
        else ora({ text: event.message, stream: io.stderr }).succeed();
        spinner = undefined;
        return;
      }

      if (isApprovalEvent(event)) {
        if (spinner?.isSpinning) spinner.succeed();
        spinner = undefined;
        writeLine(io.stderr, `◇ ${event.message}`);
        return;
      }

      if (!spinner) {
        spinner = ora({ text: event.message, stream: io.stderr }).start();
        return;
      }

      spinner.text = event.message;
    },
    fail(message = "Run failed") {
      if (spinner?.isSpinning) spinner.fail(message);
      spinner = undefined;
    },
  };
}

export function createRunProgressReporter(io: CliIO): FlowProgressReporter {
  return createRunProgressController(io).report;
}
