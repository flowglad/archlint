# Archlint

Archlint is a standalone architecture conformance suite. Consumer repositories invoke it from a sibling checkout or another configured path and pass repository-specific roots and manifests through CLI arguments.

The implementation is split into one shared evaluator and language-specific fact adapters:

- `evaluate.py` owns orchestration and policy. It calls requested adapters, validates each emitted JSON fact document with `jsonschema`, and evaluates rules for each adapter document independently.
- `go/` parses Go source and emits architecture facts as JSON.
- `ocaml/` parses OCaml source with compiler-libs and emits architecture facts as JSON.
- `swift/` parses Swift source with SwiftSyntax and emits architecture facts as JSON.

Adapters should not own policy or call the evaluator. Do not add new policy to `go/`, `ocaml/`, or `swift/` when the rule can be expressed over the shared fact schema.

When multiple adapters are requested, their facts are not merged before policy evaluation. The Go, OCaml, and Swift adapters describe different language universes, so shell-to-core, core-to-test, and state-to-stateTest relationships are evaluated inside each adapter result. Cross-language architecture relationships should be represented through explicit interface modules or backend API contracts, not by sharing an `@archlint.domain` string.

## Running

Run evaluator tests from this repository:

```sh
uv run --project . python evaluate_test.py
```

Run Go adapter tests:

```sh
cd go && go test .
```

Run Swift adapter fixture tests:

```sh
sh swift/test.sh
```

Run OCaml adapter fixture tests:

```sh
sh ocaml/test.sh
```

Consumer repositories can call the evaluator directly:

```sh
uv run --project /path/to/archlint python /path/to/archlint/evaluate.py \
  --repo-root /path/to/consumer-repo \
  --adapter go \
  --go-module path/to/go-module \
  --go-packages './...' \
  --adapter ocaml \
  --ocaml-root . \
  --adapter swift \
  --swift-xcodegen path/to/project.yml
```

Adapter-specific inputs:

- `--repo-root`: consumer repository root.
- `--adapter`: `go`, `ocaml`, or `swift`; may be repeated.
- `--go-module`: Go module path relative to `--repo-root`.
- `--go-packages`: Go package pattern relative to `--go-module`.
- `--ocaml-root`: OCaml source root relative to `--repo-root`. Defaults to `.`.
- `--swift-xcodegen`: XcodeGen project manifest path relative to `--repo-root`.

The evaluator also accepts a fact JSON document on stdin or as a positional file path. This is mainly for tests and diagnostics.

The Python evaluator is managed with `uv`. Dependencies are declared in `pyproject.toml` and locked in `uv.lock`:

```sh
uv sync --project .
```

## Module Metadata

Every Go, OCaml, and Swift source module in application code must declare architecture metadata:

```text
// @archlint.module core|interface|value|shell|state|test|stateTest|exempt
// @archlint.domain <domain>
// @archlint.exempt-reason <reason>
```

OCaml files use the same tags inside a leading block comment:

```ocaml
(* @archlint.module core
   @archlint.domain mail.sync *)
```

These tags must appear in the leading file comment block before the package, imports, type declarations, or any other source body. Tags buried later in a file are ignored and should be treated as missing metadata.

Each metadata tag may appear at most once. Duplicating `@archlint.module`, `@archlint.domain`, or `@archlint.exempt-reason` invalidates that field rather than letting the last tag win.

`@archlint.domain` is required for every non-exempt module and invalid on exempt modules.

`@archlint.exempt-reason` is required for every exempt module and invalid on non-exempt modules.

`test` and `stateTest` modules must live in test targets. Production module types (`core`, `interface`, `value`, `shell`, and `state`) must not be declared in test targets. Use test modules for test helpers rather than moving production architecture surfaces into test files.

Domains must be specific enough to make shell-to-core linkage meaningful. Archlint enforces this structurally by limiting how many non-value production modules can participate in one domain within an adapter document; if a domain grows past that bound, split it by responsibility.

Domain names must use lowercase alphanumeric segments separated by `.` or `-`, such as `mail.sync`, `backend.http`, or `http-api`. Uppercase letters, underscores, empty segments, and other punctuation are invalid.

## Module Types

`core` modules contain pure decision logic. They must declare a non-empty callable decision surface and must not import effectful packages.

`shell` modules contain effectful handlers. They execute decisions from same-domain `core` modules and should not contain business branching that could have been decided by the pure layer.

`state` modules own shared mutable state. They create an obligation to prove interleaving invariants with generated operation sequences.

`test` modules contain ordinary tests and property tests for same-domain `core` modules.

`stateTest` modules contain property interleavings tests for same-domain `state` modules. A `stateTest` domain must have at least one corresponding `state` module.

`interface` modules define vocabulary and contracts only. They must not contain concrete business logic or computed values.

`value` modules define inert value types and simple derived properties. They may contain computed properties, but must not contain function or initializer bodies, control flow, import effectful frameworks, own shared mutable state, declare classes, or contain imperative top-level declarations. Branching decisions belong in `core`, where property-test obligations apply.

`exempt` modules are narrow escape hatches. Every exemption must declare an allowed reason.

Exemption reasons are not module types. They may have shallow admissibility checks that prove the escape hatch is plausible, but they must not create ordinary architecture obligations such as domain participation, shell-to-core linkage, property-test requirements, or state interleaving requirements. If a reason needs those obligations, promote it to a real `@archlint.module` value instead of expanding the exemption.

## Enforcement Model

The repository mechanically enforces the decision/handler split by induction:

1. Known effectful libraries and framework types identify effectful code.
2. Effectful code must live in `shell`, `state`, checked `interface`, `test`, `stateTest`, or justified `exempt` modules.
3. `shell` modules must reference at least one `core` decision API in the same domain.
4. `shell` modules must actually touch effectful APIs; a pure file cannot be labeled as a handler to avoid core obligations.
5. `core` modules must declare non-empty callable decision APIs. Adapters derive this from language structure, not name prefixes or suffixes.
6. Every `core` module must be backed by same-domain `test` or `stateTest` modules that include at least one property test.
7. Core module property tests must reference every API in the core module decision surface.
8. `state` modules must actually own stateful APIs: shared mutable state, persistent state APIs, database/keychain/filesystem APIs, or another effectful state boundary.
9. `state` modules must be backed by at least one same-domain `stateTest` with property interleavings.
10. A `state` module is not covered merely because an unrelated same-domain interleaving exists. The state module must structurally reference at least one same-domain `core` decision API reached by property interleavings.
11. `stateTest` modules must themselves contain property interleavings that reach same-domain `core` decision APIs; ordinary property tests must use `test`.
12. Property interleavings may only be emitted by `stateTest` modules. A generated array or slice inside an ordinary `test` module is still just a property input, not an operation-sequence invariant.
13. `interface` modules define vocabulary and contracts only; they must not contain concrete business logic or computed values.
14. `value` modules are non-effectful value vocabulary with optional simple derived properties; they must not become service, framework-boundary, state-owner, branching, or callable decision code.
15. `core` and `value` modules must not structurally reference same-package implementation surfaces declared by `shell`, `state`, or `exempt` modules.

Handlers should not satisfy conformance by importing or referencing an unrelated decision module. If a shell can pass by referencing a core that is not part of its real workflow, the domain is too broad and should be split. The evaluator treats domain breadth as a structural property instead of banning particular domain names.

Shell-to-core linkage is deliberately narrower than "mentions any exported type in a core file." Handlers may reference a callable decision API or a decision product structurally emitted by a callable API. Arbitrary exported vocabulary that happens to live in a core module does not satisfy the handler relationship.

Property tests are not optional decoration for core modules. A decider or Go decision module without a property-bearing, same-domain `test` or `stateTest` module should fail architecture conformance even when it has example tests. Adding a new public decision API to an already-tested core module creates new property-test coverage obligations for that specific API.

Shared mutable state must not be implicit. Mutex-protected stores, actor-owned mutable state, database queues, keychain/user-defaults backed stores, and observable app models should live in `state` modules. That label is intentionally loud: it creates an obligation to prove interleaving invariants with generated operation sequences.

`state` is also a positive structural claim. A file with no shared mutable state and no effectful state boundary cannot be labeled `state` merely to opt into or route around state-test obligations. Pure state transition logic belongs in `core`; inert data belongs in `value`; effectful non-state handlers belong in `shell`.

State coverage is deliberately structural. A `stateTest` produces interleaving `propertyChecks` from APIs reachable inside generated operation-sequence properties, including same-file helpers called by those properties. Ordinary `test` modules never emit interleaving property checks; generated arrays, slices, bytes, and strings are common property inputs and are not sufficient evidence of temporal interleavings without the `stateTest` module marker. Those interleavings must reach same-domain `core` decision surfaces, and the `stateTest` domain must contain a real `state` module. A `state` module only satisfies its interleaving obligation when its own `apiReferences` intersect same-domain interleaving references derived from `propertyChecks` and same-domain `core` decision surfaces. This lets handlers and stores satisfy the rule by calling the pure decider or model operation that the interleaving test exercises, while rejecting broad domains, unrelated state tests, orphan `stateTest` labels, and incidental shared value names such as `State`, `Date`, or `String`.

## Exemptions

Allowed exemption reasons are intentionally narrow:

- `app-entry`: app launch glue; must not contain service logic
- `effect-facade`: thin service facade over effect boundaries; must not touch effectful APIs directly
- `framework-boundary`: direct framework calls that cannot be represented as an inert interface; must actually touch effectful APIs
- `principal-context`: principal propagation glue; must not touch effectful APIs
- `prototype-data`: static demo data; must not touch effectful APIs or declare classes
- `test-fixture`: intentionally failing or fake support types; must not touch effectful APIs or declare classes
- `view-adapter`: view composition and UI state glue; must not declare classes

When a conformance test fails, prefer changing the application architecture over weakening the rule. Narrow exceptions are acceptable for view-adapter or framework boundary code that does not fit the current model, but they should be explicit in the checker and justified by file shape.

Do not grow exemption reasons into hidden module types. A reason-specific rule may reject an implausible exemption shape, such as class declarations inside `view-adapter` or `framework-boundary` without effectful APIs. It should not impose positive architectural relationships. That promotion threshold is exactly why inert behavioral values were moved from `exempt` into the `value` module type.

## Fact Schema

The canonical adapter fact contract is `fact.schema.json`. The evaluator loads that file directly and validates every adapter document against it before policy evaluation.

Adapters emit a JSON document with this top-level shape:

```json
{
  "files": []
}
```

Each file fact includes:

```json
{
  "path": "/absolute/path/to/source",
  "package": "package-or-target",
  "testTarget": "",
  "metadata": {
    "moduleType": "core",
    "domain": "mail.sync",
    "exemptReason": ""
  },
  "imports": [],
  "identifiers": [],
  "apiReferences": ["decideSync"],
  "decisionSurface": [],
  "propertyTestSurface": [],
  "decisionProducts": [],
  "decisionReferences": [],
  "effectfulImports": [],
  "effectfulIdentifiers": [],
  "sharedState": [],
  "propertyChecks": [
    {
      "references": ["decideSync"],
      "interleaving": false
    }
  ],
  "interfaceLogicEvidence": {
    "functionBodies": [],
    "initializerBodies": [],
    "computedProperties": [],
    "controlFlow": [],
    "classDeclarations": [],
    "imperativeDeclarations": []
  }
}
```

Language adapters may compute these facts with language-specific AST tooling, but the meaning of each field belongs to the shared evaluator. `decisionSurface` is the set of core APIs that handlers may structurally reference. `propertyTestSurface` is the callable subset that must be covered by generated property tests; static constants may be handler surfaces without becoming property-test obligations. `propertyChecks` is the normal form for generated property-test evidence. Each item represents one property check, its reachable API `references`, and whether that property is an operation-sequence `interleaving`. References must come from the generated property expression or function body itself, including helpers structurally called by that property, not incidental examples elsewhere in the test file. The evaluator derives property-test coverage and interleaving coverage from `propertyChecks`, then compares interleaving references against same-domain `state` module `apiReferences` and same-domain `core` `decisionSurface`; adapters should therefore keep these fields structural and avoid broad identifier bags that would let unrelated modules appear linked.

Effect evidence is also normalized. Adapters own language-specific classification of effectful packages, frameworks, and framework types, but they emit the matched values as `effectfulImports` and `effectfulIdentifiers`. The evaluator derives booleans from those structured lists. Do not add adapter-emitted `hasEffectful...` booleans.

Shared mutable state evidence follows the same shape. Adapters own language-specific detection, but emit `sharedState` entries with a `kind` and structural `references`, such as `go-sync`, `swift-actor-var`, or `swift-database-queue`. The evaluator derives `has shared mutable state` from whether that list is non-empty. Do not add adapter-emitted `hasSharedMutableState` booleans.

Interface and value logic evidence is normalized too. Adapters emit `interfaceLogicEvidence` lists naming the declarations or syntax classes that caused the evidence, such as `functionBodies`, `computedProperties`, `classDeclarations`, or `controlFlow`; the evaluator derives the corresponding `has...` checks from whether those lists are empty. Do not add adapter-emitted `hasFunctionBodies`-style booleans.

Reference evidence must be internally consistent. Every `decisionSurface`, `propertyTestSurface`, `decisionProducts`, and `decisionReferences` entry must also appear in the file's structural `identifiers`, because those fields describe declarations or declaration-derived values. Every `functionBodies`, `initializerBodies`, `computedProperties`, and `classDeclarations` entry must also appear in the file's structural `identifiers`. Every `propertyChecks[].references` entry must also appear in the file's structural `apiReferences`, because property checks describe reachable call-site evidence. Every `effectfulImports` entry must appear in `imports`, and every `effectfulIdentifiers` entry must appear in `identifiers`. Interleaving references are not emitted as a separate list; they are derived from checks where `interleaving` is true, which makes interleavings imply ordinary property-test evidence by construction.

Fact emission should also avoid stringly typed shortcuts. Adapters should report structural evidence from language parsers or dependency APIs: declarations, imports, member accesses, property-wrapper attributes, call expressions, exported APIs, and generated-input shapes. They should not infer facts from filename prose, comments, test names, or suffixes when the language ecosystem exposes a stronger structural signal. Adapters also should not emit policy violation text; they emit facts, and the shared evaluator owns rule messages.

Property-test evidence is tied to known property-testing API calls, not to a test name containing `Property`. Property coverage is tied to API references reachable from generated property bodies, not to example tests or unrelated helper functions that merely live in the same source file. Property interleaving evidence is tied to generated operation-sequence inputs in `stateTest` modules, not to an `Interleavings` word in a declaration name or any generated collection inside an ordinary `test` module. These facts are emitted as `propertyChecks`, not as pre-unioned booleans and reference lists. Control-flow evidence is emitted from AST nodes such as Swift `if`/`switch`/loop statements, Go `if`/`switch`/loop/select statements, and OCaml `if`/`match`/loop expressions. Shared-state evidence is emitted from language AST nodes such as Swift actor stored `var` members, Go sync types, or OCaml top-level state allocations and mutable fields, not from source-text substring scans.

The fact schema is intentionally strict:

- `metadata.moduleType` and `metadata.exemptReason` must be known schema enum values, with `""` reserved for missing source tags
- `path` and `package` must be non-empty strings
- list fields must contain unique, non-empty strings
- unknown fields are rejected
