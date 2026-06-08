// @archlint.module shell
// @archlint.domain demo.decision

import { Command } from "commander";
import { lookup as dnsLookup } from "node:dns/promises";
import { decide } from "./decision.js";

function createCommand(): Command {
  return new Command();
}

async function usePlatformEffects(): Promise<void> {
  await fetch("https://example.com");
  await dnsLookup("example.com");
  await Bun.file("fixture.txt").text();
  setTimeout(() => {}, 0);
}

export function run(): string {
  createCommand();
  void usePlatformEffects();
  return decide(1);
}
