// @archlint.module shell
// @archlint.domain demo.decision

import { Command } from "commander";
import { decide } from "./decision.js";

function createCommand(): Command {
  return new Command();
}

export function run(): string {
  createCommand();
  return decide(1);
}
