import fc from "fast-check";
import { decide } from "../src/effect-core";

/**
 * @archlint.module test
 * @archlint.domain effect.requirements
 */
fc.assert(
  fc.property(fc.string(), (value) => {
    return decide(value).length <= value.length;
  }),
);
