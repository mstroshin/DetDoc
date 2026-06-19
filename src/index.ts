#!/usr/bin/env node
import { runCli } from "./cli/main.js";

const exitCode = await runCli(process.argv);
process.exitCode = exitCode;
