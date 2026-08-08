#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ARCHLINT_ROOT="$ROOT"
. "$ROOT/test/lib.sh"
TMPDIR="${TMPDIR:-/tmp}/archlint-ocaml-fixture-$$"
trap 'rm -rf "$TMPDIR"' EXIT
export UV_CACHE_DIR="${UV_CACHE_DIR:-$TMPDIR/uv-cache}"

copy_fixture "$ROOT/ocaml/fixtures/base" "$TMPDIR"

# Dune action preprocessing records the typedtree source as [*.pp.ml].
# The adapter must map that generated source path back to the real source file.

# Call-graph closure for property coverage: a core whose three decision APIs
# are each reached differently — directly in a callback (decide_a), only inside
# a generator (decide_b), and only through a higher-order test helper (decide_c).
# All must count, so coverage follows the call graph rather than the syntactic
# callback alone.

eval "$(opam env --switch "${ARCHLINT_OPAM_SWITCH:-$ROOT/ocaml}" --set-switch --shell=sh)"
dune build --root "$ROOT/ocaml" >/dev/null
dune runtest --root "$ROOT/ocaml" >/dev/null
dune exec --root "$ROOT/ocaml" ./main.exe -- --repo-root "$TMPDIR" --ocaml-root . > "$TMPDIR/facts.json"
uv run --project "$ROOT" python "$ROOT/evaluate.py" "$TMPDIR/facts.json"

copy_fixture "$ROOT/ocaml/fixtures/state-open-plain" "$TMPDIR"

# A hand-rolled harness in a dune (test ...) stanza: no Alcotest/QCheck/etc.,
# pass/fail signalled purely by the process exit code. The dune stanza is the
# authoritative test-scope signal, so this must still be detected as a test.
dune exec --root "$ROOT/ocaml" ./main.exe -- --repo-root "$TMPDIR" --ocaml-root . > "$TMPDIR/facts-state.json"
assert_facts "$TMPDIR/facts-state.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
checks_by_file = {item["path"]: item["propertyChecks"] for item in document["files"]}
ordinary = [checks for path, checks in checks_by_file.items() if path.endswith("test_decision.ml")][0]
state = [checks for path, checks in checks_by_file.items() if path.endswith("test_state.ml")][0]
assert ordinary and ordinary[0]["operationSequences"] == [], ordinary
assert ordinary[0]["generatedInputs"], ordinary
assert ordinary[0]["generatedInputs"][0]["name"] == "xs", ordinary
assert "xs" in ordinary[0]["generatedInputs"][0]["uses"], ordinary
assert state and state[0]["operationSequences"], state
assert "decide" in state[0]["references"], state
assert "xs" in state[0]["generatedInputs"][0]["uses"], state
assert state[0]["operationSequences"][0]["input"] == "xs", state
assert "decide" in state[0]["operationSequences"][0]["operations"], state
assert "decide" in state[0]["operationSequences"][0]["assertions"], state
handler = [item for item in document["files"] if item["path"].endswith("handler.ml")][0]
assert "Unix" in handler["effectfulIdentifiers"], handler
# moduleName is the OCaml module of the file; qualifiedReferences carry the full
# Module.value form for module-qualified uses (here Decision.decide), so the
# dependency-direction rule matches on qualified names rather than bare ones.
assert handler["moduleName"] == "Handler", handler
assert "Decision.decide" in handler["qualifiedReferences"], handler
decision = [item for item in document["files"] if item["path"].endswith("/lib/decision.ml")][0]
assert decision["moduleName"] == "Decision", decision
# decision.ml uses `decide` only as its own bare binding, never Module-qualified.
assert decision["qualifiedReferences"] == [], decision
fuzz = [item for item in document["files"] if item["path"].endswith("fuzz_decision.ml")][0]
assert fuzz["testScope"] == "fuzz_decision", fuzz
# Test scope inferred from the dune (test ...) stanza, not a test-library reference.
plain = [item for item in document["files"] if item["path"].endswith("plain_exit_test.ml")][0]
assert plain["testScope"] == "plain_exit_test", plain
assert not any(lib in plain["apiReferences"] for lib in ("Alcotest", "QCheck", "QCheck2", "Crowbar")), plain
export = [item for item in document["files"] if item["path"].endswith("export.ml")][0]
assert "Js_of_ocaml" in export["effectfulImports"], export
assert "Js" in export["effectfulIdentifiers"], export
counter = [item for item in document["files"] if item["path"].endswith("counter.ml")][0]
assert counter["sharedState"], counter
open_core = [item for item in document["files"] if item["path"].endswith("open_core.ml")][0]
assert "Open_shell.decide" in open_core["qualifiedReferences"], open_core
assert "Open_shell.incidental" not in open_core["qualifiedReferences"], open_core
PY

copy_fixture "$ROOT/ocaml/fixtures/constant-only" "$TMPDIR"

constant_lint() {
  dune exec --root "$ROOT/ocaml" ./main.exe -- --repo-root "$TMPDIR" --ocaml-root . \
    | uv run --project "$ROOT" python "$ROOT/evaluate.py"
}
expect_violation "core module property tests must reference every decision API: decide" constant_lint

# Regression: a linking-only property over [unit] that merely [ignore]s the API
# is NOT meaningful, so closure must not let it satisfy coverage.
copy_fixture "$ROOT/ocaml/fixtures/linkonly" "$TMPDIR"

expect_violation "core module property tests must reference every decision API: decide_link" constant_lint

WRAPPED_TMP="$TMPDIR/wrapped-references"
copy_fixture "$ROOT/ocaml/fixtures/wrapped-references" "$WRAPPED_TMP"
dune exec --root "$ROOT/ocaml" ./main.exe -- \
  --repo-root "$WRAPPED_TMP" --ocaml-root . > "$WRAPPED_TMP/facts.json"
assert_facts "$WRAPPED_TMP/facts.json" <<PY
import json
import sys

sys.path.insert(0, "$ROOT")
import evaluate

document = json.load(open(sys.argv[1], encoding="utf-8"))
by_suffix = {
    suffix: next(item for item in document["files"] if item["path"].endswith(suffix))
    for suffix in (
        "/caller/cross_shell.ml",
        "/caller/open_shell.ml",
        "/same/same_decision.ml",
        "/same/same_shell.ml",
        "/unwrapped/unwrapped_shell.ml",
    )
}

# Explicit cross-library wrapper qualification canonicalizes to the source
# module used by the evaluator.
assert "Decision.decide" in by_suffix["/caller/cross_shell.ml"]["qualifiedReferences"], by_suffix
assert not any(
    reference.startswith("Wrapper.") or reference.startswith("Wrapper__")
    for reference in by_suffix["/caller/cross_shell.ml"]["qualifiedReferences"]
), by_suffix

# The same owned unit is recovered when the wrapper was supplied by [-open].
assert "Decision.decide" in by_suffix["/caller/open_shell.ml"]["qualifiedReferences"], by_suffix

# Dune's implicit open for modules within a wrapped library resolves to the
# sibling source module, while the defining module does not emit itself.
assert "Same_decision.decide" in by_suffix["/same/same_shell.ml"]["qualifiedReferences"], by_suffix
assert by_suffix["/same/same_decision.ml"]["qualifiedReferences"] == [], by_suffix

# [(wrapped false)] retains its direct compilation-unit behavior.
assert "Unwrapped_decision.decide" in by_suffix["/unwrapped/unwrapped_shell.ml"]["qualifiedReferences"], by_suffix

files = evaluate.parse_fact_document(document)
assert evaluate.evaluate_shell_modules(files) == [], evaluate.evaluate_shell_modules(files)
PY
