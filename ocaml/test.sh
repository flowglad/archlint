#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ARCHLINT_ROOT="$ROOT"
. "$ROOT/test/lib.sh"
TMPDIR="${TMPDIR:-/tmp}/archlint-ocaml-fixture-$$"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/lib" "$TMPDIR/test" "$TMPDIR/harnesses" "$TMPDIR/wasm"

cat > "$TMPDIR/lib/decision.ml" <<'ML'
(* @archlint.module core
   @archlint.domain demo.decision *)

let decide x =
  if x > 0 then `Positive else `Non_positive
ML

cat > "$TMPDIR/lib/handler.ml" <<'ML'
(* @archlint.module shell
   @archlint.domain demo.decision *)

let run path =
  let _exists = Unix.access path [ Unix.F_OK ] in
  Decision.decide 1
ML

cat > "$TMPDIR/test/test_decision.ml" <<'ML'
(* @archlint.module test
   @archlint.domain demo.decision *)

let suite =
  [
    QCheck2.Test.make ~name:"decide total"
      QCheck2.Gen.(list small_int)
      (fun xs -> List.for_all (fun x -> match Decision.decide x with _ -> true) xs);
  ]
ML

cat > "$TMPDIR/harnesses/fuzz_decision.ml" <<'ML'
(* @archlint.module test
   @archlint.domain demo.decision *)

let register_fuzz_property () =
  Crowbar.add_test ~name:"dependency-defined test scope" [ Crowbar.int ] (fun x ->
      ignore (Decision.decide x))

let () = register_fuzz_property ()
ML

cat > "$TMPDIR/wasm/export.ml" <<'ML'
(* @archlint.module shell
   @archlint.domain demo.decision *)

open Js_of_ocaml

let () =
  Js.export "demo"
    (object%js
       method decide x = Decision.decide x
    end)
ML

eval "$(opam env --switch "${ARCHLINT_OPAM_SWITCH:-$ROOT/ocaml}" --set-switch --shell=sh)"
dune build --root "$ROOT/ocaml" >/dev/null
dune exec --root "$ROOT/ocaml" ./main.exe -- --repo-root "$TMPDIR" --ocaml-root . > "$TMPDIR/facts.json"
uv run --project "$ROOT" python "$ROOT/evaluate.py" "$TMPDIR/facts.json"

cat > "$TMPDIR/lib/counter.ml" <<'ML'
(* @archlint.module state
   @archlint.domain demo.decision *)

module Counter = struct
  let cell = Atomic.make 0
end

let read () =
  Decision.decide (Atomic.get Counter.cell)
ML

cat > "$TMPDIR/test/test_state.ml" <<'ML'
(* @archlint.module stateTest
   @archlint.domain demo.decision *)

let suite =
  [
    QCheck2.Test.make ~name:"operation sequence"
      QCheck2.Gen.(list small_int)
      (fun xs -> List.for_all (fun x -> match Decision.decide x with _ -> true) xs);
  ]
ML

# A hand-rolled harness in a dune (test ...) stanza: no Alcotest/QCheck/etc.,
# pass/fail signalled purely by the process exit code. The dune stanza is the
# authoritative test-scope signal, so this must still be detected as a test.
mkdir -p "$TMPDIR/plain"
cat > "$TMPDIR/plain/dune" <<'DUNE'
; covers the (test ...) stanza form
(test
 (name plain_exit_test)
 (modules plain_exit_test))
DUNE

cat > "$TMPDIR/plain/plain_exit_test.ml" <<'ML'
(* @archlint.module test
   @archlint.domain demo.decision *)

let failures = ref 0

let check name cond =
  if cond then Stdlib.Printf.printf "ok: %s\n" name
  else (
    Stdlib.incr failures;
    Stdlib.Printf.printf "FAIL: %s\n" name)

let () =
  check "decide is positive" (match Decision.decide 1 with `Positive -> true | _ -> false);
  if !failures > 0 then Stdlib.exit 1
ML

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
PY

cat > "$TMPDIR/lib/constant_only.ml" <<'ML'
(* @archlint.module core
   @archlint.domain demo.constant *)

let decide x =
  if x > 0 then `Positive else `Non_positive
ML

cat > "$TMPDIR/test/test_constant_only.ml" <<'ML'
(* @archlint.module test
   @archlint.domain demo.constant *)

let suite =
  [
    QCheck2.Test.make ~name:"constant assertion"
      QCheck2.Gen.unit
      (fun () -> match Constant_only.decide 1 with _ -> true);
  ]
ML

constant_lint() {
  dune exec --root "$ROOT/ocaml" ./main.exe -- --repo-root "$TMPDIR" --ocaml-root . \
    | uv run --project "$ROOT" python "$ROOT/evaluate.py"
}
expect_violation "core module property tests must reference every decision API: decide" constant_lint
