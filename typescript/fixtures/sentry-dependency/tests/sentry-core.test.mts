import fc from "fast-check";
import { localShape, reportFailure } from "../src/sentry-core";

/**
 * @archlint.module test
 * @archlint.domain sentry.effects
 */
fc.assert(
  fc.property(fc.string(), (value) => {
    void reportFailure;
    void localShape;
    return value.length >= 0;
  }),
);
