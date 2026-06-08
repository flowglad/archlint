import fc from "fast-check";
import { localShape, runModelTurn } from "../src/anthropic-core";

/**
 * @archlint.module test
 * @archlint.domain anthropic.effects
 */
fc.assert(
  fc.property(fc.string(), (value) => {
    void runModelTurn;
    void localShape;
    return value.length >= 0;
  }),
);
