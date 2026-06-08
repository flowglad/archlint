# Shared shell test harness for archlint adapter fixture suites.
#
# Source this from an adapter test.sh after setting ARCHLINT_ROOT to the
# repository root (the directory containing evaluate.py):
#
#   ARCHLINT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
#   . "$ARCHLINT_ROOT/test/lib.sh"
#
# Two families of helpers are provided:
#
#   * run_lint / run_adapter based assertions (assert_passes, assert_fails_with,
#     assert_fact_refs_contain, assert_fact_refs_not_contain,
#     assert_shared_state_contains). These require the sourcing script to define
#     run_lint (invoke the evaluator on a fixture) and run_adapter (emit the
#     adapter fact document for a fixture).
#
#   * Command-oriented helpers (assert_facts, expect_violation) that any script
#     can use without run_lint/run_adapter.
#
# All Python is run through the repository's uv project so the evaluator and ad
# hoc assertion scripts share one interpreter and dependency set.

# assert_facts FACTS_JSON < PYTHON
#
# Runs the Python program supplied on stdin with FACTS_JSON as sys.argv[1].
# The program asserts against the emitted fact document; a non-zero exit (e.g. a
# failed `assert`) aborts the suite via `set -e`.
assert_facts() {
  uv run --project "$ARCHLINT_ROOT" python - "$1"
}

# expect_violation EXPECTED_SUBSTRING COMMAND [ARGS...]
#
# Runs COMMAND expecting it to FAIL (non-zero) and to print EXPECTED_SUBSTRING
# on stdout or stderr. Aborts the suite if the command unexpectedly succeeds or
# if the expected violation text is absent. COMMAND may be a shell function, so
# pipelines can be wrapped and passed by name.
expect_violation() {
  expected="$1"
  shift
  if output="$("$@" 2>&1)"; then
    printf '%s\n' "expected a violation but command succeeded: $*" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
  if ! printf '%s\n' "$output" | grep -Fq "$expected"; then
    printf '%s\n' "expected violation output to contain: $expected" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

# assert_passes FIXTURE
#
# Requires run_lint. Asserts the evaluator accepts the fixture.
assert_passes() {
  fixture="$1"
  if ! output="$(run_lint "$fixture" 2>&1)"; then
    printf '%s\n' "expected fixture to pass: $fixture" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

# assert_fails_with FIXTURE EXPECTED_SUBSTRING
#
# Requires run_lint. Asserts the evaluator rejects the fixture and prints the
# expected violation text.
assert_fails_with() {
  fixture="$1"
  expected="$2"
  if output="$(run_lint "$fixture" 2>&1)"; then
    printf '%s\n' "expected fixture to fail: $fixture" >&2
    exit 1
  fi
  if ! printf '%s\n' "$output" | grep -Fq "$expected"; then
    printf '%s\n' "expected fixture output to contain: $expected" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

# assert_fact_refs_contain FIXTURE PATH_SUFFIX FIELD EXPECTED
#
# Requires run_adapter. Asserts the fact for the file ending in PATH_SUFFIX has
# EXPECTED among FIELD. FIELD may be a plain list field, or the synthetic
# "propertyTestReferences" / "propertyOperationSequenceReferences" views over
# propertyChecks.
assert_fact_refs_contain() {
  fixture="$1"
  suffix="$2"
  field="$3"
  expected="$4"
  if ! output="$(run_adapter "$fixture")"; then
    printf '%s\n' "expected adapter facts for fixture: $fixture" >&2
    exit 1
  fi
  if ! printf '%s\n' "$output" | uv run --project "$ARCHLINT_ROOT" python -c '
import json
import sys

suffix = sys.argv[1]
field = sys.argv[2]
expected = sys.argv[3]
document = json.load(sys.stdin)
matches = [item for item in document["files"] if item["path"].endswith(suffix)]
if not matches:
    raise SystemExit(f"missing fact ending with {suffix}")
if field == "propertyTestReferences":
    references = {
        reference
        for check in matches[0]["propertyChecks"]
        for reference in check["references"]
    }
elif field == "propertyOperationSequenceReferences":
    references = {
        reference
        for check in matches[0]["propertyChecks"]
        for sequence in check["operationSequences"]
        for reference in sequence["operations"] + sequence["assertions"]
    }
else:
    references = set(matches[0][field])
if expected not in references:
    raise SystemExit(f"missing {expected} in {sorted(references)}")
' "$suffix" "$field" "$expected"; then
    exit 1
  fi
}

# assert_fact_refs_not_contain FIXTURE PATH_SUFFIX FIELD UNEXPECTED
#
# Requires run_adapter. Inverse of assert_fact_refs_contain.
assert_fact_refs_not_contain() {
  fixture="$1"
  suffix="$2"
  field="$3"
  unexpected="$4"
  if ! output="$(run_adapter "$fixture")"; then
    printf '%s\n' "expected adapter facts for fixture: $fixture" >&2
    exit 1
  fi
  if ! printf '%s\n' "$output" | uv run --project "$ARCHLINT_ROOT" python -c '
import json
import sys

suffix = sys.argv[1]
field = sys.argv[2]
unexpected = sys.argv[3]
document = json.load(sys.stdin)
matches = [item for item in document["files"] if item["path"].endswith(suffix)]
if not matches:
    raise SystemExit(f"missing fact ending with {suffix}")
if field == "propertyTestReferences":
    references = {
        reference
        for check in matches[0]["propertyChecks"]
        for reference in check["references"]
    }
elif field == "propertyOperationSequenceReferences":
    references = {
        reference
        for check in matches[0]["propertyChecks"]
        for sequence in check["operationSequences"]
        for reference in sequence["operations"] + sequence["assertions"]
    }
else:
    references = set(matches[0][field])
if unexpected in references:
    raise SystemExit(f"unexpected {unexpected} in {sorted(references)}")
' "$suffix" "$field" "$unexpected"; then
    exit 1
  fi
}

# assert_shared_state_contains FIXTURE PATH_SUFFIX KIND REFERENCE
#
# Requires run_adapter. Asserts the file ending in PATH_SUFFIX reports a
# sharedState entry of KIND containing REFERENCE.
assert_shared_state_contains() {
  fixture="$1"
  suffix="$2"
  expected_kind="$3"
  expected_reference="$4"
  if ! output="$(run_adapter "$fixture")"; then
    printf '%s\n' "expected adapter facts for fixture: $fixture" >&2
    exit 1
  fi
  if ! printf '%s\n' "$output" | uv run --project "$ARCHLINT_ROOT" python -c '
import json
import sys

suffix = sys.argv[1]
expected_kind = sys.argv[2]
expected_reference = sys.argv[3]
document = json.load(sys.stdin)
matches = [item for item in document["files"] if item["path"].endswith(suffix)]
if not matches:
    raise SystemExit(f"missing fact ending with {suffix}")
for evidence in matches[0]["sharedState"]:
    if evidence["kind"] == expected_kind and expected_reference in set(evidence["references"]):
        raise SystemExit(0)
raise SystemExit(f"missing shared state {expected_kind}:{expected_reference} in {matches[0]['sharedState']}")
' "$suffix" "$expected_kind" "$expected_reference"; then
    exit 1
  fi
}
