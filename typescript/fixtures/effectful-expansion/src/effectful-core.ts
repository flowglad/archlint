// @archlint.module core
// @archlint.domain demo.effectful-expansion

import { Command } from "commander";

function createCommand(): Command {
  return new Command();
}

export function decideWithEffect(value: number): boolean {
  createCommand();
  return value >= 0;
}
