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
assert "Bun" in handler["effectfulIdentifiers"], handler
assert "dnsLookup" in handler["effectfulIdentifiers"], handler
assert "fetch" in handler["effectfulIdentifiers"], handler
assert "setTimeout" in handler["effectfulIdentifiers"], handler
assert "createCommand" in handler["effectfulIdentifiers"], handler
assert "usePlatformEffects" in handler["effectfulIdentifiers"], handler
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

copy_fixture "$ROOT/typescript/fixtures/sentry-dependency" "$TMPDIR"

npm --prefix "$ROOT/typescript" run --silent archlint -- --repo-root "$TMPDIR" --typescript-root . > "$TMPDIR/sentry-facts.json"
assert_facts "$TMPDIR/sentry-facts.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
core = [item for item in document["files"] if item["path"].endswith("sentry-core.ts")][0]
effects = core["effectfulReferences"]
sentry_effects = [
    effect for effect in effects
    if effect["origin"] == "dependency-summary"
    and effect["packageName"] == "@sentry/node"
]
by_reference = {effect["reference"]: effect for effect in sentry_effects}
assert sorted(by_reference) == ["captureException", "flush", "init"], effects
assert by_reference["init"]["category"] == "network", by_reference["init"]
assert by_reference["init"]["summaryId"] == "sentry-node-init-setup-effect", by_reference["init"]
assert by_reference["captureException"]["category"] == "network", by_reference["captureException"]
assert by_reference["captureException"]["summaryId"] == "sentry-node-capture-exception-network", by_reference["captureException"]
assert by_reference["flush"]["category"] == "network", by_reference["flush"]
assert by_reference["flush"]["summaryId"] == "sentry-node-flush-network", by_reference["flush"]
assert "getClient" not in by_reference, effects
assert "reportFailure" in core["effectfulIdentifiers"], core
local_shape_effects = [
    effect for effect in effects
    if effect["enclosingIdentifier"] == "localShape"
    and effect["origin"] == "dependency-summary"
]
assert local_shape_effects == [], effects
PY

expect_violation "effectful identifiers may only appear in shell, state, interface, test, stateTest, or exempt modules" \
  uv run --project "$ROOT" python "$ROOT/evaluate.py" \
  --repo-root "$TMPDIR" --adapter typescript --typescript-root .

copy_fixture "$ROOT/typescript/fixtures/openai-dependency" "$TMPDIR"

npm --prefix "$ROOT/typescript" run --silent archlint -- --repo-root "$TMPDIR" --typescript-root . > "$TMPDIR/openai-facts.json"
assert_facts "$TMPDIR/openai-facts.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
core = [item for item in document["files"] if item["path"].endswith("openai-core.ts")][0]
effects = core["effectfulReferences"]
openai_effects = [
    effect for effect in effects
    if effect["origin"] == "dependency-summary"
    and effect["packageName"] == "openai"
]
by_identifier = {
    effect["enclosingIdentifier"]: effect
    for effect in openai_effects
}
assert by_identifier["runInference"]["reference"] == "chat.completions.create", effects
assert by_identifier["runInference"]["category"] == "network", effects
assert by_identifier["runInference"]["summaryId"] == "openai-chat-completions-create-network", effects
assert by_identifier["runInference"]["receiverType"] == "OpenAI", effects
assert by_identifier["embedText"]["reference"] == "embeddings.create", effects
assert by_identifier["embedText"]["category"] == "network", effects
assert by_identifier["embedText"]["summaryId"] == "openai-embeddings-create-network", effects
assert "runInference" in core["effectfulIdentifiers"], core
assert "embedText" in core["effectfulIdentifiers"], core
assert "configureClient" not in core["effectfulIdentifiers"], core
local_shape_effects = [
    effect for effect in effects
    if effect["enclosingIdentifier"] == "localShape"
    and effect["origin"] == "dependency-summary"
]
assert local_shape_effects == [], effects
PY

expect_violation "effectful identifiers may only appear in shell, state, interface, test, stateTest, or exempt modules" \
  uv run --project "$ROOT" python "$ROOT/evaluate.py" \
  --repo-root "$TMPDIR" --adapter typescript --typescript-root .

copy_fixture "$ROOT/typescript/fixtures/local-relative-expansion" "$TMPDIR"

npm --prefix "$ROOT/typescript" run --silent archlint -- --repo-root "$TMPDIR" --typescript-root src > "$TMPDIR/local-relative-facts.json"
assert_facts "$TMPDIR/local-relative-facts.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
core = [
    item for item in document["files"]
    if item["metadata"]["domain"] == "demo.local-relative-expansion"
][0]
assert "decideViaExternalHelper" in core["effectfulIdentifiers"], core
effects = [
    effect for effect in core["effectfulReferences"]
    if effect["origin"] == "local-call-expansion"
]
assert len(effects) == 1, effects
effect = effects[0]
assert effect["reference"] == "Effects.effectfulHelper", effect
assert effect["category"] == "network", effect
assert effect["enclosingIdentifier"] == "decideViaExternalHelper", effect
assert any("local call expansion reached Effects.effectfulHelper" in item for item in effect["evidence"]), effect
PY

expect_violation "effectful identifiers may only appear in shell, state, interface, test, stateTest, or exempt modules" \
  uv run --project "$ROOT" python "$ROOT/evaluate.py" \
  --repo-root "$TMPDIR" --adapter typescript --typescript-root src

copy_fixture "$ROOT/typescript/fixtures/workspace-package-expansion" "$TMPDIR"

npm --prefix "$ROOT/typescript" run --silent archlint -- --repo-root "$TMPDIR" --typescript-root packages/consumer > "$TMPDIR/workspace-package-facts.json"
assert_facts "$TMPDIR/workspace-package-facts.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
core = [
    item for item in document["files"]
    if item["metadata"]["domain"] == "demo.workspace-package-expansion"
][0]
assert "decideViaWorkspacePackage" in core["effectfulIdentifiers"], core
effects = [
    effect for effect in core["effectfulReferences"]
    if effect["origin"] == "local-call-expansion"
]
assert len(effects) == 1, effects
effect = effects[0]
assert effect["reference"] == "Index.effectfulHelper", effect
assert effect["category"] == "network", effect
assert effect["enclosingIdentifier"] == "decideViaWorkspacePackage", effect
assert any("local call expansion reached Index.effectfulHelper" in item for item in effect["evidence"]), effect
PY

expect_violation "effectful identifiers may only appear in shell, state, interface, test, stateTest, or exempt modules" \
  uv run --project "$ROOT" python "$ROOT/evaluate.py" \
  --repo-root "$TMPDIR" --adapter typescript --typescript-root packages/consumer

copy_fixture "$ROOT/typescript/fixtures/trigger-dependency" "$TMPDIR"

npm --prefix "$ROOT/typescript" run --silent archlint -- --repo-root "$TMPDIR" --typescript-root . > "$TMPDIR/trigger-facts.json"
assert_facts "$TMPDIR/trigger-facts.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
core = [item for item in document["files"] if item["path"].endswith("trigger-core.ts")][0]
effects = core["effectfulReferences"]
metadata_effects = [
    effect for effect in effects
    if effect["origin"] == "dependency-summary"
    and effect["packageName"] == "@trigger.dev/sdk"
    and effect["reference"] == "append"
]
assert len(metadata_effects) == 1, effects
assert metadata_effects[0]["category"] == "storage", metadata_effects[0]
assert metadata_effects[0]["summaryId"] == "trigger-sdk-metadata-append-runtime-metadata", metadata_effects[0]
logger_effects = [
    effect for effect in effects
    if effect["origin"] == "dependency-summary"
    and effect["packageName"] == "@trigger.dev/core"
    and effect["reference"] == "warn"
]
assert len(logger_effects) == 1, effects
assert logger_effects[0]["category"] == "console", logger_effects[0]
assert logger_effects[0]["summaryId"] == "trigger-core-logger-runtime-log", logger_effects[0]
local_shape_effects = [
    effect for effect in effects
    if effect["enclosingIdentifier"] == "localShape"
    and effect["origin"] == "dependency-summary"
]
assert local_shape_effects == [], effects
assert "emitTriggerEvent" in core["effectfulIdentifiers"], core
assert "localShape" not in core["effectfulIdentifiers"], core
PY

expect_violation "effectful identifiers may only appear in shell, state, interface, test, stateTest, or exempt modules" \
  uv run --project "$ROOT" python "$ROOT/evaluate.py" \
  --repo-root "$TMPDIR" --adapter typescript --typescript-root .

copy_fixture "$ROOT/typescript/fixtures/effect-requirements" "$TMPDIR"

npm --prefix "$ROOT/typescript" run --silent archlint -- --repo-root "$TMPDIR" --typescript-root . > "$TMPDIR/effect-facts.json"
assert_facts "$TMPDIR/effect-facts.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
core = [item for item in document["files"] if item["path"].endswith("effect-core.ts")][0]
effects = core["effectfulReferences"]
by_identifier = {
    effect["enclosingIdentifier"]: effect
    for effect in effects
    if effect["origin"] == "dependency-summary"
}
assert by_identifier["loadDirect"]["reference"] == "SqlClient.SqlClient", effects
assert by_identifier["loadDirect"]["category"] == "database", effects
assert by_identifier["loadDirect"]["summaryId"] == "effect-requirement-sqlclient", effects
assert by_identifier["loadViaBinding"]["reference"] == "SqlClient.SqlClient", effects
assert by_identifier["layerNeedsSql"]["reference"] == "SqlClient.SqlClient", effects
assert by_identifier["pgRequirement"]["reference"] == "PgClient.PgClient", effects
assert by_identifier["pgRequirement"]["packageName"] == "@effect/sql-pg", effects
assert by_identifier["runSqlRequirement"]["reference"] == "SqlClient.SqlClient", effects
assert by_identifier["runSqlRequirement"]["category"] == "database", effects
assert any("executed deferred computation type" in item for item in by_identifier["runSqlRequirement"]["evidence"]), effects
assert "loadDirect" in core["effectfulIdentifiers"], core
assert "loadViaBinding" in core["effectfulIdentifiers"], core
assert "layerNeedsSql" in core["effectfulIdentifiers"], core
assert "pgRequirement" in core["effectfulIdentifiers"], core
assert "runSqlRequirement" in core["effectfulIdentifiers"], core
assert "platformFetch" in core["effectfulIdentifiers"], core
assert "fetchProgram" in core["effectfulIdentifiers"], core
assert "tryPromiseProgram" in core["effectfulIdentifiers"], core
assert "runFetchProgram" in core["effectfulIdentifiers"], core
assert "localOnly" not in core["effectfulIdentifiers"], core
assert "localLayer" not in core["effectfulIdentifiers"], core
assert "runPureEffect" not in core["effectfulIdentifiers"], core
PY

expect_violation "effectful identifiers may only appear in shell, state, interface, test, stateTest, or exempt modules" \
  uv run --project "$ROOT" python "$ROOT/evaluate.py" \
  --repo-root "$TMPDIR" --adapter typescript --typescript-root .

copy_fixture "$ROOT/typescript/fixtures/anthropic-dependency" "$TMPDIR"

npm --prefix "$ROOT/typescript" run --silent archlint -- --repo-root "$TMPDIR" --typescript-root . > "$TMPDIR/anthropic-facts.json"
assert_facts "$TMPDIR/anthropic-facts.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
core = [item for item in document["files"] if item["path"].endswith("anthropic-core.ts")][0]
effects = core["effectfulReferences"]
anthropic_effects = [
    effect for effect in effects
    if effect["origin"] == "dependency-summary"
    and effect["packageName"] == "@anthropic-ai/sdk"
    and effect["reference"] == "messages.create"
]
assert len(anthropic_effects) == 1, effects
effect = anthropic_effects[0]
assert effect["kind"] == "call", effect
assert effect["category"] == "network", effect
assert effect["summaryId"] == "anthropic-sdk-messages-create-network", effect
assert effect["receiverType"] == "Anthropic", effect
assert effect["enclosingIdentifier"] == "createMessage", effect
assert "createMessage" in core["effectfulIdentifiers"], core
assert "runModelTurn" in core["effectfulIdentifiers"], core
local_shape_effects = [
    effect for effect in effects
    if effect["enclosingIdentifier"] == "localShape"
    and effect["origin"] == "dependency-summary"
]
assert local_shape_effects == [], effects
PY

expect_violation "effectful identifiers may only appear in shell, state, interface, test, stateTest, or exempt modules" \
  uv run --project "$ROOT" python "$ROOT/evaluate.py" \
  --repo-root "$TMPDIR" --adapter typescript --typescript-root .
