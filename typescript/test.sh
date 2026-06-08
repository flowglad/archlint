#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ARCHLINT_ROOT="$ROOT"
. "$ROOT/test/lib.sh"
TMPDIR="${TMPDIR:-/tmp}/archlint-typescript-fixture-$$"
trap 'rm -rf "$TMPDIR"' EXIT
export UV_CACHE_DIR="${UV_CACHE_DIR:-$TMPDIR/uv-cache}"

copy_fixture "$ROOT/typescript/fixtures/base" "$TMPDIR"

npm --prefix "$ROOT/typescript" install >/dev/null
npm --prefix "$ROOT/typescript" run --silent typecheck
uv run --project "$ROOT" python "$ROOT/evaluate.py" \
  --repo-root "$TMPDIR" \
  --adapter typescript \
  --typescript-root .

npm --prefix "$ROOT/typescript" run --silent archlint -- --repo-root "$TMPDIR" --typescript-root . > "$TMPDIR/facts.json"
assert_facts "$TMPDIR/facts.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
test_file = [item for item in document["files"] if item["path"].endswith("decision.test.mts")][0]
assert test_file["testScope"] == "decision.test", test_file
assert test_file["propertyChecks"], test_file
check = test_file["propertyChecks"][0]
assert "decide" in check["references"], check
assert "wrappedDecide" in check["references"], check
assert check["generatedInputs"] == [{"name": "value", "uses": ["value"]}], check
handler = [item for item in document["files"] if item["path"].endswith("handler.ts")][0]
assert "commander" in handler["effectfulImports"], handler
assert "Command" in handler["effectfulIdentifiers"], handler
assert "createCommand" in handler["effectfulIdentifiers"], handler
assert "run" in handler["effectfulIdentifiers"], handler
# moduleName is the capitalized file basename and qualifiedReferences use the
# same prefix for semantic cross-file references.
assert handler["moduleName"] == "Handler", handler
assert "Decision.decide" in handler["qualifiedReferences"], handler
consumer = [item for item in document["files"] if item["path"].endswith("consumer.ts")][0]
assert "Handler.run" in consumer["qualifiedReferences"], consumer
assert "Consumer.localRun" not in consumer["qualifiedReferences"], consumer
core = [item for item in document["files"] if item["path"].endswith("decision.ts")][0]
assert core["moduleName"] == "Decision", core
assert "decisionNode" in core["decisionSurface"], core
assert "decisionNode" not in core["propertyTestSurface"], core
assert "decide" in core["propertyTestSurface"], core
PY

copy_fixture "$ROOT/typescript/fixtures/constant-only" "$TMPDIR"

expect_violation "core module property tests must reference every decision API: decideConstant" \
  uv run --project "$ROOT" python "$ROOT/evaluate.py" \
  --repo-root "$TMPDIR" --adapter typescript --typescript-root .

copy_fixture "$ROOT/typescript/fixtures/effectful-expansion" "$TMPDIR"

expect_violation "effectful identifiers may only appear in shell, state, interface, test, stateTest, or exempt modules" \
  uv run --project "$ROOT" python "$ROOT/evaluate.py" \
  --repo-root "$TMPDIR" --adapter typescript --typescript-root .
