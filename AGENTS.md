# AGENTS.md

Guidance for AI coding agents working in this repository.

## Architecture

Archlint has one shared evaluator and language-specific fact adapters:

- `evaluate.py` owns shared policy over the fact schema.
- `go/`, `ocaml/`, `swift/`, and `typescript/` parse source code and emit facts.

Do not put cross-language policy in an adapter when it can be expressed over the shared fact schema. Adapters should emit structural facts; the evaluator should decide whether those facts satisfy architecture policy.

## Adapter Evidence

Facts must come from language structure or recognized standard/dependency APIs, not application-level naming conventions. Avoid relying on project directory names, local symbol names, prefixes, suffixes, or broad identifier bags when a standard library or third-party dependency symbol can provide stronger evidence.

Whenever an adapter uses known-good identifier detection, it must also implement call-graph expansion for that detection. If a file calls an application-level helper, and that helper calls the known-good standard or dependency API, the resulting fact should be the same as if the known-good API appeared directly at the call site.

This applies broadly, including:

- property-test detection and property `references`
- property generated-input `uses` when the use is derived from trusted helper APIs rather than direct syntax
- property operation sequence detection
- test-scope inference from test-library APIs
- effect or state boundary evidence derived from known dependency APIs

Call-graph expansion is an adapter contract, not a per-rule convenience. Apply it uniformly at the fact site so every consumer of that fact sees the expanded evidence. For property-test facts, the expansion root is the whole property construction that reaches the test runner, not only the final assertion callback. That includes:

- generator expressions and helper bindings used to build generated inputs
- named helper functions and local function literals
- non-function top-level bindings such as generator values
- higher-order property builders when the language structure can trace a callback or returned property function
- operation-sequence operations and assertions derived through helpers

Do not add a narrow expansion path only for the newest failing fixture. Prefer a single closure helper that all fact emitters for that evidence category call through. If full expansion is not possible in a language adapter without semantic analysis, implement the strongest structural expansion available, document the remaining gap in the adapter test or issue, and avoid pretending a bare identifier match proves reachability.

The intent is to reject forgery by incidental names while accepting normal local factoring. A test file should not fail just because it wraps `QCheck`, `Crowbar`, `testing/quick`, or a Swift property-check helper in a local helper. Conversely, a file should not pass merely because it contains a local variable or unrelated declaration with a trusted-looking name.

For generated property tests, adapters should emit structurally rich generated-input evidence rather than policy booleans. Report the generated inputs and syntactic uses where each generated value participates in the property body. These uses are anti-vacuity evidence only; they do not need to prove value flow to an assertion or decision API. Constant properties such as unit generators with `fun ()` or ignored closure arguments may be useful regression assertions, but they should not be emitted as generated-input-backed coverage.

## Validation

Run the focused adapter suite after adapter changes:

```sh
uv run --project . python evaluate_test.py
sh ocaml/test.sh
cd go && go test .
sh swift/test.sh
sh typescript/test.sh
```

If a full adapter suite fails because of an existing unrelated policy drift, report that explicitly and still run the focused tests that cover the changed adapter behavior.
