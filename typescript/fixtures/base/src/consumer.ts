// @archlint.module exempt
// @archlint.exempt-reason test-support

import { run } from "./handler.js";

function localRun(): string {
  return "local";
}

export function consume(): string {
  localRun();
  return run();
}
