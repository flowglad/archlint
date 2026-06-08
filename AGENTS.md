# AGENTS.md

Guidance for AI coding agents working in this repository.

## Architecture

Archlint has one shared evaluator and language-specific fact adapters:

- `evaluate.py` owns shared policy over the fact schema.
- `go/`, `ocaml/`, and `swift/` parse source code and emit facts.

Do not put cross-language policy in an adapter when it can be expressed over the shared fact schema. Adapters should emit structural facts; the evaluator should decide whether those facts satisfy architecture policy.

## Adapter Evidence

Facts must come from language structure or recognized standard/dependency APIs, not application-level naming conventions. Avoid relying on project directory names, local symbol names, prefixes, suffixes, or broad identifier bags when a standard library or third-party dependency symbol can provide stronger evidence.

Whenever an adapter uses known-good identifier detection, it must also implement call-graph expansion for that detection. If a file calls an application-level helper, and that helper calls the known-good standard or dependency API, the resulting fact should be the same as if the known-good API appeared directly at the call site.

This applies broadly, including:

- property-test detection and property `references`
- property generated-input `uses`
- property operation sequence detection
- test-scope inference from test-library APIs
- effect or state boundary evidence derived from known dependency APIs

The intent is to reject forgery by incidental names while accepting normal local factoring. A test file should not fail just because it wraps `QCheck`, `Crowbar`, `testing/quick`, or a Swift property-check helper in a local helper. Conversely, a file should not pass merely because it contains a local variable or unrelated declaration with a trusted-looking name.

For generated property tests, adapters should emit structurally rich generated-input evidence rather than policy booleans. Report the generated inputs and the reachable API uses where each generated value flows; the evaluator decides whether those uses satisfy property coverage or operation sequence obligations. Constant properties such as unit generators with `fun ()` or ignored closure arguments may be useful regression assertions, but they should not be emitted as generated-input-backed coverage.

## Validation

Run the focused adapter suite after adapter changes:

```sh
uv run --project . python evaluate_test.py
sh ocaml/test.sh
cd go && go test .
sh swift/test.sh
```

If a full adapter suite fails because of an existing unrelated policy drift, report that explicitly and still run the focused tests that cover the changed adapter behavior.
