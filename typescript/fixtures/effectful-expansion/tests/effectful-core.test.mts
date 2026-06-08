// @archlint.module test
// @archlint.domain demo.effectful-expansion

import { test } from "node:test";
import assert from "node:assert/strict";
import * as fc from "fast-check";
import { decideWithEffect } from "../src/effectful-core.js";

test("decision property", () => {
  fc.assert(
    fc.property(fc.integer(), (value) => {
      assert.equal(typeof decideWithEffect(value), "boolean");
    }),
  );
});
