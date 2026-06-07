#!/usr/bin/env python3
"""Evaluate architecture conformance facts.

Language adapters are responsible for parsing source code and emitting facts.
This evaluator owns cross-language policy.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator
from jsonschema.exceptions import ValidationError


DOMAIN_PRODUCTION_MODULE_LIMIT = 16
DOMAIN_PATTERN = re.compile(r"^[a-z][a-z0-9]*(?:[.-][a-z][a-z0-9]*)*$")

SCHEMA_PATH = Path(__file__).with_name("fact.schema.json")


def load_fact_schema() -> dict[str, Any]:
    return json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))


FACT_SCHEMA = load_fact_schema()
Draft202012Validator.check_schema(FACT_SCHEMA)
FACT_VALIDATOR = Draft202012Validator(FACT_SCHEMA)
VALID_MODULE_TYPES = set(FACT_SCHEMA["$defs"]["metadata"]["properties"]["moduleType"]["enum"]) - {""}
VALID_EXEMPT_REASONS = set(FACT_SCHEMA["$defs"]["metadata"]["properties"]["exemptReason"]["enum"]) - {""}


@dataclass(frozen=True)
class Violation:
    path: str
    message: str


@dataclass(frozen=True)
class Metadata:
    module_type: str
    domain: str
    exempt_reason: str


@dataclass(frozen=True)
class InterfaceLogicEvidence:
    function_bodies: set[str]
    constructor_bodies: set[str]
    derived_value_bodies: set[str]
    control_flow: set[str]
    imperative_declarations: set[str]
    has_function_bodies: bool
    has_constructor_bodies: bool
    has_derived_value_bodies: bool
    has_control_flow: bool
    has_imperative_declarations: bool


@dataclass(frozen=True)
class PropertyCheck:
    references: set[str]
    interleaving: bool


@dataclass(frozen=True)
class SharedStateEvidence:
    kind: str
    references: set[str]


@dataclass(frozen=True)
class SourceFile:
    path: str
    test_scope: str
    metadata: Metadata
    imports: set[str]
    identifiers: set[str]
    api_references: set[str]
    decision_surface: set[str]
    property_test_surface: set[str]
    decision_products: set[str]
    decision_references: set[str]
    effectful_imports: set[str]
    effectful_identifiers: set[str]
    has_effectful_imports: bool
    has_effectful_identifiers: bool
    shared_state: tuple[SharedStateEvidence, ...]
    has_shared_mutable_state: bool
    property_checks: tuple[PropertyCheck, ...]
    has_property_test: bool
    property_test_references: set[str]
    has_property_interleavings: bool
    property_interleaving_references: set[str]
    interface_logic_evidence: InterfaceLogicEvidence


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--adapter", action="append", choices=["go", "swift", "ocaml"], default=[])
    parser.add_argument("--go-module")
    parser.add_argument("--go-packages")
    parser.add_argument("--swift-xcodegen")
    parser.add_argument("--ocaml-root")
    parser.add_argument("facts", nargs="?", default="-")
    args = parser.parse_args()

    try:
        if args.adapter:
            violations = evaluate_adapters(
                repo_root=Path(args.repo_root).resolve(),
                adapters=args.adapter,
                go_module=args.go_module,
                go_packages=args.go_packages,
                swift_xcodegen=args.swift_xcodegen,
                ocaml_root=args.ocaml_root,
            )
        else:
            source = sys.stdin.read() if args.facts == "-" else open(args.facts, encoding="utf-8").read()
            files = parse_fact_document(json.loads(source))
            violations = evaluate(files)
    except Exception as error:  # noqa: BLE001 - diagnostics should include malformed fact input.
        print(f"architecture fact parse failed: {error}", file=sys.stderr)
        return 1

    for violation in sorted(violations, key=lambda item: (item.path, item.message)):
        print(f"{violation.path}: {violation.message}")
    return 1 if violations else 0


def evaluate_adapters(
    repo_root: Path,
    adapters: list[str],
    go_module: str | None,
    go_packages: str | None,
    swift_xcodegen: str | None,
    ocaml_root: str | None,
) -> list[Violation]:
    violations: list[Violation] = []
    for adapter in adapters:
        violations.extend(
            evaluate(run_adapter(repo_root, adapter, go_module, go_packages, swift_xcodegen, ocaml_root))
        )
    return violations


def run_adapter(
    repo_root: Path,
    adapter: str,
    go_module: str | None,
    go_packages: str | None,
    swift_xcodegen: str | None,
    ocaml_root: str | None,
) -> list[SourceFile]:
    tool_root = Path(__file__).resolve().parent
    if adapter == "go":
        if go_module is None:
            raise ValueError("--go-module is required when --adapter go is used")
        if go_packages is None:
            raise ValueError("--go-packages is required when --adapter go is used")
        command = [
            "go",
            "run",
            ".",
            "--repo-root",
            str(repo_root),
            "--go-module",
            go_module,
            "--go-packages",
            go_packages,
        ]
        cwd = tool_root / "go"
    elif adapter == "swift":
        if swift_xcodegen is None:
            raise ValueError("--swift-xcodegen is required when --adapter swift is used")
        command = [
            "swift",
            "run",
            "--package-path",
            str(tool_root / "swift"),
            "SwiftArchLint",
            "--repo-root",
            str(repo_root),
            "--xcodegen",
            swift_xcodegen,
        ]
        cwd = tool_root
    elif adapter == "ocaml":
        command = [
            "dune",
            "exec",
            "--root",
            str(tool_root / "ocaml"),
            "./main.exe",
            "--",
            "--repo-root",
            str(repo_root),
        ]
        if ocaml_root is not None:
            command.extend(["--ocaml-root", ocaml_root])
        cwd = tool_root
    else:
        raise ValueError(f"unknown adapter {adapter}")

    result = subprocess.run(command, cwd=cwd, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        output = "\n".join(part for part in [result.stdout.strip(), result.stderr.strip()] if part)
        raise RuntimeError(f"{adapter} adapter failed: {output}")
    return parse_fact_document(json.loads(result.stdout))


def parse_fact_document(document: dict[str, Any]) -> list[SourceFile]:
    validate_fact_document(document)
    return [parse_source_file(item) for item in document["files"]]


def validate_fact_document(document: Any) -> None:
    errors = sorted(FACT_VALIDATOR.iter_errors(document), key=lambda error: error.path)
    if errors:
        raise ValueError(f"fact document schema violation: {render_validation_error(errors[0])}")


def render_validation_error(error: ValidationError) -> str:
    path = "$"
    for segment in error.absolute_path:
        if isinstance(segment, int):
            path += f"[{segment}]"
        else:
            path += f".{segment}"
    return f"{path}: {error.message}"


def parse_source_file(item: dict[str, Any]) -> SourceFile:
    metadata = item["metadata"]
    interface_logic_evidence = item["interfaceLogicEvidence"]
    imports = set(item["imports"])
    identifiers = set(item["identifiers"])
    property_checks = tuple(
        PropertyCheck(
            references=set(check["references"]),
            interleaving=check["interleaving"],
        )
        for check in item["propertyChecks"]
    )
    property_test_references = set().union(*(check.references for check in property_checks), set())
    property_interleaving_references = set().union(
        *(check.references for check in property_checks if check.interleaving),
        set(),
    )
    shared_state = tuple(
        SharedStateEvidence(
            kind=evidence["kind"],
            references=set(evidence["references"]),
        )
        for evidence in item["sharedState"]
    )
    return SourceFile(
        path=item["path"],
        test_scope=item["testScope"],
        metadata=Metadata(
            module_type=metadata["moduleType"],
            domain=metadata["domain"],
            exempt_reason=metadata["exemptReason"],
        ),
        imports=imports,
        identifiers=identifiers,
        api_references=set(item["apiReferences"]),
        decision_surface=set(item["decisionSurface"]),
        property_test_surface=set(item["propertyTestSurface"]),
        decision_products=set(item["decisionProducts"]),
        decision_references=set(item["decisionReferences"]),
        effectful_imports=set(item["effectfulImports"]),
        effectful_identifiers=set(item["effectfulIdentifiers"]),
        has_effectful_imports=bool(item["effectfulImports"]),
        has_effectful_identifiers=bool(item["effectfulIdentifiers"]),
        shared_state=shared_state,
        has_shared_mutable_state=bool(shared_state),
        property_checks=property_checks,
        has_property_test=bool(property_checks),
        property_test_references=property_test_references,
        has_property_interleavings=any(check.interleaving for check in property_checks),
        property_interleaving_references=property_interleaving_references,
        interface_logic_evidence=InterfaceLogicEvidence(
            function_bodies=set(interface_logic_evidence["functionBodies"]),
            constructor_bodies=set(interface_logic_evidence["constructorBodies"]),
            derived_value_bodies=set(interface_logic_evidence["derivedValueBodies"]),
            control_flow=set(interface_logic_evidence["controlFlow"]),
            imperative_declarations=set(interface_logic_evidence["imperativeDeclarations"]),
            has_function_bodies=bool(interface_logic_evidence["functionBodies"]),
            has_constructor_bodies=bool(interface_logic_evidence["constructorBodies"]),
            has_derived_value_bodies=bool(interface_logic_evidence["derivedValueBodies"]),
            has_control_flow=bool(interface_logic_evidence["controlFlow"]),
            has_imperative_declarations=bool(interface_logic_evidence["imperativeDeclarations"]),
        ),
    )


def evaluate(files: list[SourceFile]) -> list[Violation]:
    violations: list[Violation] = []
    violations.extend(evaluate_fact_consistency(files))
    violations.extend(evaluate_file_metadata(files))
    violations.extend(evaluate_exemption_admissibility(files))
    violations.extend(evaluate_domain_breadth(files))
    violations.extend(evaluate_effect_boundaries(files))
    violations.extend(evaluate_dependency_direction(files))
    violations.extend(evaluate_interface_modules(files))
    violations.extend(evaluate_value_modules(files))
    violations.extend(evaluate_shell_modules(files))
    violations.extend(evaluate_core_modules(files))
    violations.extend(evaluate_state_modules(files))
    return violations


def evaluate_fact_consistency(files: list[SourceFile]) -> list[Violation]:
    violations: list[Violation] = []
    for source_file in files:
        effectful_imports_outside_imports = sorted(source_file.effectful_imports - source_file.imports)
        if effectful_imports_outside_imports:
            violations.append(
                Violation(
                    source_file.path,
                    "effectful imports must be structural imports: "
                    + ", ".join(effectful_imports_outside_imports),
                )
            )
        effectful_identifiers_outside_identifiers = sorted(
            source_file.effectful_identifiers - source_file.identifiers
        )
        if effectful_identifiers_outside_identifiers:
            violations.append(
                Violation(
                    source_file.path,
                    "effectful identifiers must be structural identifiers: "
                    + ", ".join(effectful_identifiers_outside_identifiers),
                )
            )
        references_outside_property = sorted(
            source_file.property_test_references - source_file.api_references
        )
        if references_outside_property:
            violations.append(
                Violation(
                    source_file.path,
                    "property test references must be reachable API references: "
                    + ", ".join(references_outside_property),
                )
            )
        surface_outside_identifiers = sorted(source_file.decision_surface - source_file.identifiers)
        if surface_outside_identifiers:
            violations.append(
                Violation(
                    source_file.path,
                    "decision surface must be structural identifiers: "
                    + ", ".join(surface_outside_identifiers),
                )
            )
        property_surface_outside_identifiers = sorted(
            source_file.property_test_surface - source_file.identifiers
        )
        if property_surface_outside_identifiers:
            violations.append(
                Violation(
                    source_file.path,
                    "property test surface must be structural identifiers: "
                    + ", ".join(property_surface_outside_identifiers),
                )
            )
        products_outside_identifiers = sorted(source_file.decision_products - source_file.identifiers)
        if products_outside_identifiers:
            violations.append(
                Violation(
                    source_file.path,
                    "decision products must be structural identifiers: "
                    + ", ".join(products_outside_identifiers),
                )
            )
        decision_references_outside_identifiers = sorted(
            source_file.decision_references - source_file.identifiers
        )
        if decision_references_outside_identifiers:
            violations.append(
                Violation(
                    source_file.path,
                    "decision references must be structural identifiers: "
                    + ", ".join(decision_references_outside_identifiers),
                )
            )
        evidence = source_file.interface_logic_evidence
        for field_name, references in [
            ("function body evidence", evidence.function_bodies),
            ("constructor body evidence", evidence.constructor_bodies),
            ("derived value body evidence", evidence.derived_value_bodies),
        ]:
            references_outside_identifiers = sorted(references - source_file.identifiers)
            if references_outside_identifiers:
                violations.append(
                    Violation(
                        source_file.path,
                        f"{field_name} must be structural identifiers: "
                        + ", ".join(references_outside_identifiers),
                    )
                )
    return violations


def evaluate_file_metadata(files: list[SourceFile]) -> list[Violation]:
    violations: list[Violation] = []
    for source_file in files:
        metadata = source_file.metadata
        if not metadata.module_type:
            violations.append(Violation(source_file.path, "module must declare @archlint.module"))
            continue
        if metadata.module_type != "exempt" and not metadata.domain:
            violations.append(Violation(source_file.path, "module must declare @archlint.domain"))
        if metadata.module_type != "exempt" and metadata.domain and not DOMAIN_PATTERN.fullmatch(metadata.domain):
            violations.append(Violation(source_file.path, "module domain must be lowercase dot-or-kebab segments"))
        if metadata.module_type == "exempt" and metadata.domain:
            violations.append(Violation(source_file.path, "exempt module must not declare @archlint.domain"))
        if metadata.module_type == "exempt" and not metadata.exempt_reason:
            violations.append(Violation(source_file.path, "exempt module must declare @archlint.exempt-reason"))
        if metadata.module_type != "exempt" and metadata.exempt_reason:
            violations.append(Violation(source_file.path, "@archlint.exempt-reason is only valid on exempt modules"))
        if metadata.module_type in {"test", "stateTest"} and not source_file.test_scope:
            violations.append(Violation(source_file.path, "test module must be declared in a test scope"))
        if metadata.module_type in {"core", "interface", "value", "shell", "state"} and source_file.test_scope:
            violations.append(Violation(source_file.path, "production module must not be declared in a test scope"))
    return violations


def evaluate_domain_breadth(files: list[SourceFile]) -> list[Violation]:
    files_by_domain: dict[str, list[SourceFile]] = {}
    for source_file in files:
        if source_file.metadata.module_type in {"value", "test", "stateTest", "exempt"}:
            continue
        if not source_file.metadata.domain:
            continue
        files_by_domain.setdefault(source_file.metadata.domain, []).append(source_file)

    violations: list[Violation] = []
    for domain, domain_files in files_by_domain.items():
        if len(domain_files) <= DOMAIN_PRODUCTION_MODULE_LIMIT:
            continue
        violation_path = sorted(source_file.path for source_file in domain_files)[0]
        violations.append(
            Violation(
                violation_path,
                f"domain has {len(domain_files)} production modules; maximum is {DOMAIN_PRODUCTION_MODULE_LIMIT}",
            )
        )
    return violations


def evaluate_exemption_admissibility(files: list[SourceFile]) -> list[Violation]:
    violations: list[Violation] = []
    for source_file in files:
        if source_file.metadata.module_type != "exempt":
            continue
        reason = source_file.metadata.exempt_reason
        evidence = source_file.interface_logic_evidence
        has_effects = source_file.has_effectful_imports or source_file.has_effectful_identifiers

        if reason == "entrypoint":
            if evidence.has_function_bodies or evidence.has_constructor_bodies or evidence.has_control_flow:
                violations.append(Violation(source_file.path, "entrypoint exemption must not contain decision logic"))

        if reason == "effect-boundary" and not has_effects:
            violations.append(Violation(source_file.path, "effect-boundary exemption must touch effectful APIs"))

        if reason == "effect-facade":
            if has_effects:
                violations.append(Violation(source_file.path, "effect-facade exemption must not touch effectful APIs directly"))

        if reason == "pure-glue":
            if has_effects:
                violations.append(Violation(source_file.path, "pure-glue exemption must not touch effectful APIs"))
            if evidence.has_control_flow:
                violations.append(Violation(source_file.path, "pure-glue exemption must not contain decision control flow"))

        if reason == "static-data":
            if has_effects:
                violations.append(Violation(source_file.path, "static-data exemption must not touch effectful APIs"))
            if evidence.has_function_bodies or evidence.has_constructor_bodies or evidence.has_control_flow:
                violations.append(Violation(source_file.path, "static-data exemption must not contain behavior"))

        if reason == "test-support" and has_effects:
            violations.append(Violation(source_file.path, "test-support exemption must not touch effectful APIs"))

    return violations


def evaluate_effect_boundaries(files: list[SourceFile]) -> list[Violation]:
    violations: list[Violation] = []
    for source_file in files:
        module_type = source_file.metadata.module_type
        if module_type == "core" and source_file.has_effectful_imports:
            violations.append(Violation(source_file.path, "core module must not import effectful dependencies"))
        if module_type == "shell" and not (
            source_file.has_effectful_imports or source_file.has_effectful_identifiers
        ):
            violations.append(Violation(source_file.path, "shell module must touch effectful APIs"))
        if module_type == "state" and not (
            source_file.has_shared_mutable_state
            or source_file.has_effectful_imports
            or source_file.has_effectful_identifiers
        ):
            violations.append(Violation(source_file.path, "state module must own stateful APIs"))
        if (
            source_file.has_effectful_imports or source_file.has_effectful_identifiers
        ) and module_type not in {"shell", "state", "interface", "test", "stateTest", "exempt"}:
            violations.append(
                Violation(
                    source_file.path,
                    "effectful identifiers may only appear in shell, state, interface, test, stateTest, or exempt modules",
                )
            )
        if source_file.has_shared_mutable_state and module_type not in {"state", "test", "stateTest", "exempt"}:
            violations.append(
                Violation(source_file.path, "shared mutable state may only appear in state, test, or stateTest modules")
            )
        if source_file.has_property_interleavings and module_type != "stateTest":
            violations.append(Violation(source_file.path, "property interleavings may only appear in stateTest modules"))
    return violations


def evaluate_dependency_direction(files: list[SourceFile]) -> list[Violation]:
    implementation_references_by_domain: dict[str, set[str]] = {}
    for source_file in files:
        if source_file.metadata.module_type in {"shell", "state", "exempt"}:
            implementation_references_by_domain.setdefault(source_file.metadata.domain, set()).update(
                source_file.decision_references
            )

    violations: list[Violation] = []
    for source_file in files:
        if source_file.metadata.module_type not in {"core", "value"}:
            continue
        forbidden_references = implementation_references_by_domain.get(source_file.metadata.domain, set())
        referenced_implementation = sorted(source_file.api_references.intersection(forbidden_references))
        if referenced_implementation:
            violations.append(
                Violation(
                    source_file.path,
                    f"{source_file.metadata.module_type} module must not reference implementation APIs: {', '.join(referenced_implementation)}",
                )
            )
    return violations


def evaluate_value_modules(files: list[SourceFile]) -> list[Violation]:
    violations: list[Violation] = []
    for source_file in files:
        if source_file.metadata.module_type != "value":
            continue
        evidence = source_file.interface_logic_evidence
        if evidence.has_function_bodies:
            violations.append(Violation(source_file.path, "value module must not contain function bodies"))
        if evidence.has_constructor_bodies:
            violations.append(Violation(source_file.path, "value module must not contain constructor bodies"))
        if evidence.has_control_flow:
            violations.append(Violation(source_file.path, "value module must not contain control flow"))
        if evidence.has_imperative_declarations:
            violations.append(
                Violation(source_file.path, "value module may only declare imports, types, and constants")
            )
    return violations


def evaluate_interface_modules(files: list[SourceFile]) -> list[Violation]:
    violations: list[Violation] = []
    for source_file in files:
        if source_file.metadata.module_type != "interface":
            continue
        evidence = source_file.interface_logic_evidence
        if evidence.has_function_bodies:
            violations.append(Violation(source_file.path, "interface module must not contain function bodies"))
        if evidence.has_constructor_bodies:
            violations.append(Violation(source_file.path, "interface module must not contain constructor bodies"))
        if evidence.has_derived_value_bodies:
            violations.append(Violation(source_file.path, "interface module must not contain derived value bodies"))
        if evidence.has_control_flow:
            violations.append(Violation(source_file.path, "interface module must not contain control flow"))
        if evidence.has_imperative_declarations:
            violations.append(
                Violation(source_file.path, "interface module may only declare imports, types, and constants")
            )
    return violations


def evaluate_shell_modules(files: list[SourceFile]) -> list[Violation]:
    core_handler_references_by_domain: dict[str, set[str]] = {}
    for source_file in files:
        if source_file.metadata.module_type == "core":
            core_handler_references_by_domain.setdefault(source_file.metadata.domain, set()).update(
                source_file.decision_surface | source_file.decision_products
            )

    violations: list[Violation] = []
    for source_file in files:
        if source_file.metadata.module_type != "shell":
            continue
        core_references = core_handler_references_by_domain.get(source_file.metadata.domain, set())
        if not source_file.api_references.intersection(core_references):
            violations.append(Violation(source_file.path, "shell module must reference a core API in the same @archlint.domain"))
    return violations


def evaluate_core_modules(files: list[SourceFile]) -> list[Violation]:
    violations: list[Violation] = []
    for source_file in files:
        if source_file.metadata.module_type != "core":
            continue
        if not source_file.property_test_surface:
            violations.append(
                Violation(source_file.path, "core module must declare a callable decision API")
            )
        same_domain_tests = [
            test_file
            for test_file in files
            if test_file.metadata.module_type in {"test", "stateTest"}
            and test_file.metadata.domain == source_file.metadata.domain
        ]
        violation_path = source_file.path if not same_domain_tests else sorted(test.path for test in same_domain_tests)[0]
        if not same_domain_tests:
            violations.append(Violation(source_file.path, "core module must have a same-domain test or stateTest module"))
            continue
        if not any(test_file.has_property_test for test_file in same_domain_tests):
            violations.append(
                Violation(
                    violation_path,
                    "core module test must contain at least one property test",
                )
            )
            continue
        property_tests = [test_file for test_file in same_domain_tests if test_file.has_property_test]
        tested_surfaces = set().union(*(test_file.property_test_references for test_file in property_tests))
        missing_surfaces = sorted(source_file.property_test_surface - tested_surfaces)
        if missing_surfaces:
            violations.append(
                Violation(
                    violation_path,
                    "core module property tests must reference every decision API: "
                    + ", ".join(missing_surfaces),
                )
            )
    return violations


def evaluate_state_modules(files: list[SourceFile]) -> list[Violation]:
    state_modules_by_domain = {
        source_file.metadata.domain
        for source_file in files
        if source_file.metadata.module_type == "state"
    }
    state_tests_by_domain = {
        source_file.metadata.domain
        for source_file in files
        if source_file.metadata.module_type == "stateTest" and source_file.has_property_interleavings
    }
    core_decision_references_by_domain: dict[str, set[str]] = {}
    for source_file in files:
        if source_file.metadata.module_type != "core":
            continue
        core_decision_references_by_domain.setdefault(source_file.metadata.domain, set()).update(
            source_file.decision_surface
        )

    interleaving_references_by_domain: dict[str, set[str]] = {}
    for source_file in files:
        if source_file.metadata.module_type != "stateTest":
            continue
        if not source_file.has_property_interleavings:
            continue
        interleaving_references_by_domain.setdefault(source_file.metadata.domain, set()).update(
            source_file.property_interleaving_references
        )

    violations: list[Violation] = []
    for source_file in files:
        if source_file.metadata.module_type == "state":
            if source_file.metadata.domain not in state_tests_by_domain:
                violations.append(
                    Violation(
                        source_file.path,
                        "state module must have a same-domain stateTest with property interleavings",
                    )
                )
                continue
            tested_references = interleaving_references_by_domain.get(source_file.metadata.domain, set())
            core_decision_references = core_decision_references_by_domain.get(source_file.metadata.domain, set())
            covered_decision_references = source_file.api_references.intersection(
                tested_references,
                core_decision_references,
            )
            if not covered_decision_references:
                violations.append(
                    Violation(
                        source_file.path,
                        "state module must reference a core decision API reached by same-domain property interleavings",
                    )
                )
        if source_file.metadata.module_type == "stateTest":
            if not source_file.has_property_interleavings:
                violations.append(Violation(source_file.path, "stateTest module must contain property interleavings"))
            elif not source_file.property_interleaving_references:
                violations.append(
                    Violation(source_file.path, "stateTest module interleavings must reference reachable APIs")
                )
            else:
                if source_file.metadata.domain not in state_modules_by_domain:
                    violations.append(
                        Violation(source_file.path, "stateTest module must have a same-domain state module")
                    )
                core_decision_references = core_decision_references_by_domain.get(source_file.metadata.domain, set())
                if not source_file.property_interleaving_references.intersection(core_decision_references):
                    violations.append(
                        Violation(
                            source_file.path,
                            "stateTest module interleavings must reference same-domain core decision APIs",
                        )
                    )
    return violations


if __name__ == "__main__":
    raise SystemExit(main())
