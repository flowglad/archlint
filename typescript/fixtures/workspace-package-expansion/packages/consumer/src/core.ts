// @archlint.module core
// @archlint.domain demo.workspace-package-expansion

import { effectfulHelper } from "@demo/provider";

export function decideViaWorkspacePackage(value: number): boolean {
  effectfulHelper();
  return value >= 0;
}
