// @archlint.module test
// @archlint.domain demo.decision

import { test } from "node:test";
import assert from "node:assert/strict";
import * as fc from "fast-check";
import { wrappedDecide } from "../src/decision.js";

function checkDecision(value: number): string {
  return wrappedDecide(value);
}

test("decision property", () => {
  fc.assert(
    fc.property(fc.integer(), (value) => {
      assert.equal(typeof checkDecision(value), "string");
    }),
  );
});
