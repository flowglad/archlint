// @archlint.module test
// @archlint.domain demo.constant

import { test } from "node:test";
import assert from "node:assert/strict";
import * as fc from "fast-check";
import { decideConstant } from "../src/constant-only.js";

test("constant property", () => {
  fc.assert(
    fc.property(fc.constant(undefined), () => {
      assert.equal(decideConstant(1), "positive");
    }),
  );
});
