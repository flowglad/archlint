import fc from "fast-check";
import { configureClient, embedText, localShape, runInference } from "../src/openai-core";

/**
 * @archlint.module test
 * @archlint.domain openai.effects
 */
fc.assert(
  fc.property(fc.string(), (value) => {
    void runInference;
    void embedText;
    void configureClient;
    void localShape;
    return value.length >= 0;
  }),
);
