// @archlint.module core
// @archlint.domain demo.local-relative-expansion

import { effectfulHelper } from "../support/effects.js";

export function decideViaExternalHelper(value: number): boolean {
  effectfulHelper();
  return value >= 0;
}
