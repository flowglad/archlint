// @archlint.module test
// @archlint.domain demo.closure

import { test } from "node:test";
import assert from "node:assert/strict";
import * as fc from "fast-check";
import { decideA, decideB, decideC } from "../src/closure.js";

const genB = fc.integer().map((value) => {
  decideB(value);
  return value;
});

function makeProp(decide: (value: number) => boolean) {
  return (value: number) => {
    decide(value);
    return true;
  };
}

test("closure properties", () => {
  fc.assert(
    fc.property(fc.integer(), (value) => {
      assert.equal(typeof decideA(value), "boolean");
    }),
  );
  fc.assert(fc.property(genB, makeProp(decideC)));
});
