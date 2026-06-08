# archlint task runner.
#
#   just            list recipes
#   just setup      install every adapter toolchain + dependency
#   just test       build nothing new; run all five suites in parallel
#   just test-go    run a single suite (go | ocaml | swift | ts | py)
#
# The five suites are independent, so `test` fans them out concurrently and
# aggregates pass/fail. There is deliberately no dependency-graph build layer:
# each native toolchain (dune, swift, npm, go) already does its own incremental
# rebuilds.

# The OCaml adapter builds in its own self-contained local opam switch
# (ocaml/_opam) so it never borrows a switch from a sibling repository.
# Override by exporting ARCHLINT_OPAM_SWITCH before invoking just.
export ARCHLINT_OPAM_SWITCH := env_var_or_default("ARCHLINT_OPAM_SWITCH", justfile_directory() / "ocaml")

# OCaml compiler used when provisioning the local switch.
ocaml_compiler := "ocaml-base-compiler.5.4.1"

# List available recipes.
default:
    @just --list

# Install/prepare all adapter toolchains and dependencies.
setup: setup-ocaml
    uv sync --project .
    npm --prefix typescript install
    swift build --package-path swift

# Provision the OCaml adapter's self-contained local opam switch if missing.
# Idempotent: skips when ocaml/_opam already exists.
setup-ocaml:
    #!/bin/sh
    set -eu
    if [ -d "{{justfile_directory()}}/ocaml/_opam" ]; then
      echo "ocaml/_opam already present; skipping switch creation"
    else
      echo "creating self-contained OCaml switch in ocaml/_opam"
      opam switch create "{{justfile_directory()}}/ocaml" "{{ocaml_compiler}}" --deps-only --yes
    fi

# Run every suite in parallel and print an aggregated PASS/FAIL summary.
# Exits non-zero (and dumps the output of failing suites) if any suite fails.
test:
    #!/bin/sh
    set -u
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    suites="py go ocaml swift ts"
    echo "running suites in parallel: $suites"
    for s in $suites; do
      ( just "test-$s" >"$tmp/$s.log" 2>&1; echo "$?" >"$tmp/$s.status" ) &
    done
    wait
    status=0
    echo
    echo "==== results ===="
    for s in $suites; do
      code="$(cat "$tmp/$s.status")"
      if [ "$code" -eq 0 ]; then
        printf 'PASS  test-%s\n' "$s"
      else
        printf 'FAIL  test-%s (exit %s)\n' "$s" "$code"
        status=1
      fi
    done
    if [ "$status" -ne 0 ]; then
      echo
      echo "==== output from failing suites ===="
      for s in $suites; do
        [ "$(cat "$tmp/$s.status")" -eq 0 ] && continue
        printf '\n----- test-%s -----\n' "$s"
        cat "$tmp/$s.log"
      done
    fi
    exit "$status"

# Shared evaluator (policy) unit tests.
test-py:
    uv run --project . python evaluate_test.py

# Go adapter tests (native; they invoke evaluate.py).
test-go:
    cd go && go test ./...

# OCaml adapter fixture tests (uses the self-contained local switch).
test-ocaml: setup-ocaml
    sh ocaml/test.sh

# Swift adapter fixture tests.
test-swift:
    sh swift/test.sh

# TypeScript adapter fixture tests.
test-ts:
    sh typescript/test.sh
