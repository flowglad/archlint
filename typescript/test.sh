#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMPDIR="${TMPDIR:-/tmp}/archlint-typescript-fixture-$$"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/src" "$TMPDIR/tests"

cat > "$TMPDIR/src/decision.ts" <<'TS'
// @archlint.module core
// @archlint.domain demo.decision

export function decide(x: number): string {
  return x >= 0 ? "positive" : "negative";
}

export const decisionNode = (value: number): { kind: "node"; value: number } => ({
  kind: "node",
  value,
});

export function wrappedDecide(x: number): string {
  return decide(x);
}
TS

cat > "$TMPDIR/src/handler.ts" <<'TS'
// @archlint.module shell
// @archlint.domain demo.decision

import { Command } from "commander";
import { decide } from "./decision.js";

export function run(): string {
  new Command();
  return decide(1);
}
TS

cat > "$TMPDIR/tests/decision.test.mts" <<'TS'
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
TS

npm --prefix "$ROOT/typescript" install >/dev/null
npm --prefix "$ROOT/typescript" run --silent typecheck
uv run --project "$ROOT" python "$ROOT/evaluate.py" \
  --repo-root "$TMPDIR" \
  --adapter typescript \
  --typescript-root .

npm --prefix "$ROOT/typescript" run --silent archlint -- --repo-root "$TMPDIR" --typescript-root . > "$TMPDIR/facts.json"
uv run --project "$ROOT" python - "$TMPDIR/facts.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
test_file = [item for item in document["files"] if item["path"].endswith("decision.test.mts")][0]
assert test_file["testScope"] == "decision.test", test_file
assert test_file["propertyChecks"], test_file
check = test_file["propertyChecks"][0]
assert "decide" in check["references"], check
assert "wrappedDecide" in check["references"], check
assert check["generatedInputs"] == [{"name": "value", "uses": ["assert", "checkDecision", "decide", "equal", "wrappedDecide"]}], check
handler = [item for item in document["files"] if item["path"].endswith("handler.ts")][0]
assert "commander" in handler["effectfulImports"], handler
assert "Command" in handler["effectfulIdentifiers"], handler
core = [item for item in document["files"] if item["path"].endswith("decision.ts")][0]
assert "decisionNode" in core["decisionSurface"], core
assert "decisionNode" not in core["propertyTestSurface"], core
assert "decide" in core["propertyTestSurface"], core
PY

cat > "$TMPDIR/src/constant-only.ts" <<'TS'
// @archlint.module core
// @archlint.domain demo.constant

export function decideConstant(x: number): string {
  return x >= 0 ? "positive" : "negative";
}
TS

cat > "$TMPDIR/tests/constant-only.test.mts" <<'TS'
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
TS

if uv run --project "$ROOT" python "$ROOT/evaluate.py" \
  --repo-root "$TMPDIR" \
  --adapter typescript \
  --typescript-root . > "$TMPDIR/constant.out"
then
  echo "constant generated-input property unexpectedly passed" >&2
  exit 1
fi
grep -q "core module property tests must reference every decision API: decideConstant" "$TMPDIR/constant.out" \
  || cat "$TMPDIR/constant.out" >&2
