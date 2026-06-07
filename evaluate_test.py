#!/usr/bin/env python3

from pathlib import Path
import sys
import unittest
from unittest import mock

from jsonschema import Draft202012Validator

sys.path.insert(0, str(Path(__file__).parent))
import evaluate


def source_file(**overrides):
    overridden_keys = set(overrides)
    data = {
        "path": "/repo/Core.swift",
        "testScope": "",
        "metadata": {
            "moduleType": "core",
            "domain": "mail.sync",
            "exemptReason": "",
        },
        "imports": [],
        "identifiers": ["decideSync"],
        "apiReferences": ["decideSync"],
        "decisionSurface": ["decideSync"],
        "propertyTestSurface": ["decideSync"],
        "decisionProducts": [],
        "decisionReferences": ["decideSync"],
        "effectfulImports": [],
        "effectfulIdentifiers": [],
        "sharedState": [],
        "propertyChecks": [],
        "interfaceLogicEvidence": empty_interface_logic_evidence(),
    }
    data.update(overrides)
    if data["metadata"]["moduleType"] != "core":
        for decision_field in [
            "decisionSurface",
            "propertyTestSurface",
            "decisionProducts",
            "decisionReferences",
        ]:
            if decision_field not in overridden_keys:
                data[decision_field] = []
    return evaluate.parse_source_file(data)


def generated_input(name="input", uses=None):
    return {"name": name, "uses": [] if uses is None else uses}


def property_check(references=None, interleaving=False, generated_inputs=None):
    if generated_inputs is None:
        generated_inputs = [generated_input(uses=[] if references is None else references)]
    return {
        "references": [] if references is None else references,
        "interleaving": interleaving,
        "generatedInputs": generated_inputs,
    }


class EvaluateTests(unittest.TestCase):
    def test_effectful_imports_must_be_structural_imports(self):
        source = source_file(
            path="/repo/Core.swift",
            imports=[],
            effectfulImports=["EffectFramework"],
        )

        violations = evaluate.evaluate([source])

        self.assertIn(
            "effectful imports must be structural imports: EffectFramework",
            [violation.message for violation in violations],
        )

    def test_effectful_identifiers_must_be_structural_identifiers(self):
        source = source_file(
            path="/repo/Core.swift",
            identifiers=[],
            effectfulIdentifiers=["EffectType"],
        )

        violations = evaluate.evaluate([source])

        self.assertIn(
            "effectful identifiers must be structural identifiers: EffectType",
            [violation.message for violation in violations],
        )

    def test_property_test_references_must_be_api_references(self):
        source = source_file(
            path="/repo/CoreTests.swift",
            testScope="CoreTests",
            metadata={"moduleType": "test", "domain": "mail.sync", "exemptReason": ""},
            apiReferences=[],
            propertyChecks=[property_check(["decideSync"])],
        )

        violations = evaluate.evaluate([source])

        self.assertIn(
            "property test references must be reachable API references: decideSync",
            [violation.message for violation in violations],
        )

    def test_decision_surface_must_be_identifiers(self):
        source = source_file(
            path="/repo/Core.swift",
            identifiers=[],
            decisionSurface=["decideSync"],
            propertyTestSurface=[],
            decisionReferences=[],
        )

        violations = evaluate.evaluate([source])

        self.assertIn(
            "decision surface must be structural identifiers: decideSync",
            [violation.message for violation in violations],
        )

    def test_property_test_surface_must_be_identifiers(self):
        source = source_file(
            path="/repo/Core.swift",
            identifiers=[],
            decisionSurface=[],
            propertyTestSurface=["decideSync"],
            decisionReferences=[],
        )

        violations = evaluate.evaluate([source])

        self.assertIn(
            "property test surface must be structural identifiers: decideSync",
            [violation.message for violation in violations],
        )

    def test_decision_products_must_be_identifiers(self):
        source = source_file(
            path="/repo/Core.swift",
            identifiers=["decideSync"],
            decisionProducts=["SyncPlan"],
            decisionReferences=["decideSync"],
        )

        violations = evaluate.evaluate([source])

        self.assertIn(
            "decision products must be structural identifiers: SyncPlan",
            [violation.message for violation in violations],
        )

    def test_decision_references_must_be_identifiers(self):
        source = source_file(
            path="/repo/Core.swift",
            identifiers=["decideSync"],
            decisionProducts=[],
            decisionReferences=["decideSync", "SyncPlan"],
        )

        violations = evaluate.evaluate([source])

        self.assertIn(
            "decision references must be structural identifiers: SyncPlan",
            [violation.message for violation in violations],
        )

    def test_core_module_requires_matching_same_domain_property_test_that_references_surface(self):
        core = source_file(path="/repo/Core.swift")
        unrelated_test = source_file(
            path="/repo/CoreTests.swift",
            testScope="CoreTests",
            metadata={"moduleType": "test", "domain": "mail.sync", "exemptReason": ""},
            identifiers=["somethingElse"],
            apiReferences=["somethingElse"],
            propertyChecks=[property_check()],
        )

        violations = evaluate.evaluate([core, unrelated_test])

        self.assertIn(
            "core module property tests must reference every decision API: decideSync",
            [violation.message for violation in violations],
        )

    def test_core_module_accepts_property_test_that_references_surface(self):
        core = source_file(path="/repo/Core.swift")
        linked_test = source_file(
            path="/repo/CoreTests.swift",
            testScope="CoreTests",
            metadata={"moduleType": "test", "domain": "mail.sync", "exemptReason": ""},
            identifiers=["decideSync"],
            apiReferences=["decideSync"],
            propertyChecks=[property_check(["decideSync"])],
        )

        violations = evaluate.evaluate([core, linked_test])

        self.assertEqual([], violations)

    def test_core_module_rejects_property_reference_without_generated_input_use(self):
        core = source_file(path="/repo/Core.ml")
        constant_property = source_file(
            path="/repo/Core_test.ml",
            testScope="CoreTest",
            metadata={"moduleType": "test", "domain": "mail.sync", "exemptReason": ""},
            identifiers=["decideSync"],
            apiReferences=["decideSync"],
            propertyChecks=[
                property_check(["decideSync"], generated_inputs=[])
            ],
        )

        violations = evaluate.evaluate([core, constant_property])

        self.assertIn(
            "core module property tests must reference every decision API: decideSync",
            [violation.message for violation in violations],
        )

    def test_core_module_rejects_property_reference_with_unused_generated_input(self):
        core = source_file(path="/repo/Core.ml")
        ignored_input_property = source_file(
            path="/repo/Core_test.ml",
            testScope="CoreTest",
            metadata={"moduleType": "test", "domain": "mail.sync", "exemptReason": ""},
            identifiers=["decideSync"],
            apiReferences=["decideSync"],
            propertyChecks=[
                property_check(
                    ["decideSync"],
                    generated_inputs=[generated_input("input", uses=[])],
                )
            ],
        )

        violations = evaluate.evaluate([core, ignored_input_property])

        self.assertIn(
            "core module property tests must reference every decision API: decideSync",
            [violation.message for violation in violations],
        )

    def test_generated_input_uses_must_be_reachable_api_references(self):
        source = source_file(
            path="/repo/CoreTests.swift",
            testScope="CoreTests",
            metadata={"moduleType": "test", "domain": "mail.sync", "exemptReason": ""},
            apiReferences=["decideSync"],
            propertyChecks=[
                property_check(
                    ["decideSync"],
                    generated_inputs=[generated_input("input", uses=["hiddenUse"])],
                )
            ],
        )

        violations = evaluate.evaluate([source])

        self.assertIn(
            "property generated input uses must be reachable API references: hiddenUse",
            [violation.message for violation in violations],
        )

    def test_core_module_exhaustive_property_surface_is_structural(self):
        core = source_file(
            path="/repo/Core.ml",
            identifiers=["decideSync", "helper"],
            apiReferences=["decideSync", "helper"],
            decisionSurface=["decideSync", "helper"],
            propertyTestSurface=["decideSync", "helper"],
            decisionReferences=["decideSync", "helper"],
        )
        linked_test = source_file(
            path="/repo/Core_test.ml",
            testScope="CoreTest",
            metadata={"moduleType": "test", "domain": "mail.sync", "exemptReason": ""},
            identifiers=["decideSync"],
            apiReferences=["decideSync"],
            propertyChecks=[property_check(["decideSync"])],
        )

        violations = evaluate.evaluate([core, linked_test])

        self.assertIn(
            "core module property tests must reference every decision API: helper",
            [violation.message for violation in violations],
        )

    def test_shell_module_requires_same_domain_core_reference(self):
        core = source_file(path="/repo/Core.swift")
        shell = source_file(
            path="/repo/Handler.swift",
            metadata={"moduleType": "shell", "domain": "mail.sync", "exemptReason": ""},
            identifiers=["otherDecision"],
            apiReferences=["otherDecision"],
        )

        violations = evaluate.evaluate([core, shell])

        self.assertIn(
            "shell module must reference a core API in the same @archlint.domain",
            [violation.message for violation in violations],
        )

    def test_shell_module_does_not_accept_arbitrary_core_type_reference(self):
        core = source_file(
            path="/repo/Core.swift",
            apiReferences=["decideSync", "CoreVocabulary"],
            decisionSurface=["decideSync"],
            propertyTestSurface=["decideSync"],
            decisionProducts=[],
            decisionReferences=["decideSync", "CoreVocabulary"],
        )
        shell = source_file(
            path="/repo/Handler.swift",
            metadata={"moduleType": "shell", "domain": "mail.sync", "exemptReason": ""},
            apiReferences=["CoreVocabulary"],
        )

        violations = evaluate.evaluate([core, shell])

        self.assertIn(
            "shell module must reference a core API in the same @archlint.domain",
            [violation.message for violation in violations],
        )

    def test_shell_module_accepts_core_decision_product_reference(self):
        core = source_file(
            path="/repo/Core.swift",
            apiReferences=["decideSync", "SyncPlan"],
            identifiers=["decideSync", "SyncPlan"],
            decisionSurface=["decideSync"],
            propertyTestSurface=["decideSync"],
            decisionProducts=["SyncPlan"],
            decisionReferences=["decideSync", "SyncPlan"],
        )
        shell = source_file(
            path="/repo/Handler.swift",
            metadata={"moduleType": "shell", "domain": "mail.sync", "exemptReason": ""},
            apiReferences=["SyncPlan"],
            identifiers=["EffectType"],
            effectfulIdentifiers=["EffectType"],
            decisionSurface=[],
            propertyTestSurface=[],
            decisionProducts=[],
            decisionReferences=[],
        )
        test = source_file(
            path="/repo/CoreTests.swift",
            testScope="CoreTests",
            metadata={"moduleType": "test", "domain": "mail.sync", "exemptReason": ""},
            apiReferences=["decideSync"],
            propertyChecks=[property_check(["decideSync"])],
            decisionSurface=[],
            propertyTestSurface=[],
            decisionProducts=[],
            decisionReferences=[],
        )

        violations = evaluate.evaluate([core, shell, test])

        self.assertEqual([], violations)

    def test_shell_module_must_touch_effectful_api(self):
        core = source_file(
            path="/repo/Core.swift",
            apiReferences=["decideSync", "SyncPlan"],
            identifiers=["decideSync", "SyncPlan"],
            decisionSurface=["decideSync"],
            propertyTestSurface=["decideSync"],
            decisionProducts=["SyncPlan"],
            decisionReferences=["decideSync", "SyncPlan"],
        )
        shell = source_file(
            path="/repo/Handler.swift",
            metadata={"moduleType": "shell", "domain": "mail.sync", "exemptReason": ""},
            apiReferences=["SyncPlan"],
            decisionSurface=[],
            propertyTestSurface=[],
            decisionProducts=[],
            decisionReferences=[],
        )
        test = source_file(
            path="/repo/CoreTests.swift",
            testScope="CoreTests",
            metadata={"moduleType": "test", "domain": "mail.sync", "exemptReason": ""},
            apiReferences=["decideSync"],
            propertyChecks=[property_check(["decideSync"])],
            decisionSurface=[],
            propertyTestSurface=[],
            decisionProducts=[],
            decisionReferences=[],
        )

        violations = evaluate.evaluate([core, shell, test])

        self.assertIn("shell module must touch effectful APIs", [violation.message for violation in violations])

    def test_shell_module_does_not_accept_broad_identifier_spoof(self):
        core = source_file(path="/repo/Core.swift")
        shell = source_file(
            path="/repo/Handler.swift",
            metadata={"moduleType": "shell", "domain": "mail.sync", "exemptReason": ""},
            identifiers=["decideSync"],
            apiReferences=[],
        )

        violations = evaluate.evaluate([core, shell])

        self.assertIn(
            "shell module must reference a core API in the same @archlint.domain",
            [violation.message for violation in violations],
        )

    def test_core_test_does_not_accept_broad_identifier_spoof(self):
        core = source_file(path="/repo/Core.swift")
        test = source_file(
            path="/repo/CoreTests.swift",
            testScope="CoreTests",
            metadata={"moduleType": "test", "domain": "mail.sync", "exemptReason": ""},
            identifiers=["decideSync"],
            apiReferences=[],
            propertyChecks=[property_check()],
        )

        violations = evaluate.evaluate([core, test])

        self.assertIn(
            "core module property tests must reference every decision API: decideSync",
            [violation.message for violation in violations],
        )

    def test_core_test_does_not_accept_file_level_reference_outside_property_body(self):
        core = source_file(path="/repo/Core.swift")
        test = source_file(
            path="/repo/CoreTests.swift",
            testScope="CoreTests",
            metadata={"moduleType": "test", "domain": "mail.sync", "exemptReason": ""},
            apiReferences=["decideSync"],
            propertyChecks=[property_check()],
        )

        violations = evaluate.evaluate([core, test])

        self.assertIn(
            "core module property tests must reference every decision API: decideSync",
            [violation.message for violation in violations],
        )

    def test_core_module_must_not_reference_shell_api(self):
        core = source_file(
            path="/repo/Core.swift",
            metadata={"moduleType": "core", "domain": "mail.sync", "exemptReason": ""},
            apiReferences=["HTTPClient"],
        )
        shell = source_file(
            path="/repo/HTTPClient.swift",
            metadata={"moduleType": "shell", "domain": "mail.sync", "exemptReason": ""},
            decisionReferences=["HTTPClient"],
        )

        violations = evaluate.evaluate([core, shell])

        self.assertIn(
            "core module must not reference implementation APIs: HTTPClient",
            [violation.message for violation in violations],
        )

    def test_value_module_must_not_reference_state_api(self):
        value = source_file(
            path="/repo/Value.swift",
            metadata={"moduleType": "value", "domain": "mail.sync", "exemptReason": ""},
            apiReferences=["SQLiteStore"],
        )
        state = source_file(
            path="/repo/SQLiteStore.swift",
            metadata={"moduleType": "state", "domain": "mail.sync", "exemptReason": ""},
            decisionReferences=["SQLiteStore"],
        )

        violations = evaluate.evaluate([value, state])

        self.assertIn(
            "value module must not reference implementation APIs: SQLiteStore",
            [violation.message for violation in violations],
        )

    def test_dependency_direction_uses_api_references_not_broad_identifiers(self):
        core = source_file(
            path="/repo/Core.swift",
            metadata={"moduleType": "core", "domain": "mail.sync", "exemptReason": ""},
            identifiers=["HTTPClient"],
            apiReferences=[],
        )
        shell = source_file(
            path="/repo/HTTPClient.swift",
            metadata={"moduleType": "shell", "domain": "mail.sync", "exemptReason": ""},
            decisionReferences=["HTTPClient"],
        )

        violations = evaluate.evaluate([core, shell])

        self.assertNotIn(
            "core module must not reference implementation APIs: HTTPClient",
            [violation.message for violation in violations],
        )

    def test_dependency_direction_is_domain_scoped(self):
        core = source_file(
            path="/repo/auth/Core.go",
            metadata={"moduleType": "core", "domain": "auth.installation", "exemptReason": ""},
            apiReferences=["Principal"],
        )
        exempt = source_file(
            path="/repo/principal/Context.go",
            metadata={"moduleType": "exempt", "domain": "", "exemptReason": "pure-glue"},
            decisionReferences=["Principal"],
        )

        violations = evaluate.evaluate([core, exempt])

        self.assertNotIn(
            "core module must not reference implementation APIs: Principal",
            [violation.message for violation in violations],
        )

        same_domain_implementation = source_file(
            path="/repo/auth/Context.go",
            metadata={"moduleType": "shell", "domain": "auth.installation", "exemptReason": ""},
            decisionReferences=["Principal"],
            effectfulIdentifiers=["EffectType"],
            identifiers=["Principal", "EffectType"],
        )

        violations = evaluate.evaluate([core, same_domain_implementation])

        self.assertIn(
            "core module must not reference implementation APIs: Principal",
            [violation.message for violation in violations],
        )

    def test_state_module_requires_same_domain_interleaving_test(self):
        state = source_file(
            path="/repo/Store.swift",
            metadata={"moduleType": "state", "domain": "backend.sqlite", "exemptReason": ""},
        )
        wrong_domain_test = source_file(
            path="/repo/StoreTests.swift",
            metadata={"moduleType": "stateTest", "domain": "mail.sync", "exemptReason": ""},
            propertyChecks=[property_check(interleaving=True)],
        )

        violations = evaluate.evaluate([state, wrong_domain_test])

        self.assertIn(
            "state module must have a same-domain stateTest with property interleavings",
            [violation.message for violation in violations],
        )

    def test_state_module_requires_reachable_same_domain_interleaving_api_reference(self):
        core = source_file(
            path="/repo/SQLiteStateDecider.swift",
            metadata={"moduleType": "core", "domain": "backend.sqlite", "exemptReason": ""},
            apiReferences=["SQLiteStateDecider"],
            identifiers=["SQLiteStateDecider"],
            decisionSurface=["SQLiteStateDecider"],
            propertyTestSurface=["SQLiteStateDecider"],
            decisionReferences=["SQLiteStateDecider"],
        )
        state = source_file(
            path="/repo/Store.swift",
            metadata={"moduleType": "state", "domain": "backend.sqlite", "exemptReason": ""},
            apiReferences=["SQLiteStore", "SQLiteStateDecider"],
            imports=["PersistenceKit"],
            effectfulImports=["PersistenceKit"],
        )
        unrelated_interleaving_test = source_file(
            path="/repo/StoreTests.swift",
            testScope="StoreTests",
            metadata={"moduleType": "stateTest", "domain": "backend.sqlite", "exemptReason": ""},
            apiReferences=["UnrelatedDecider"],
            propertyChecks=[property_check(["UnrelatedDecider"], interleaving=True)],
        )

        violations = evaluate.evaluate([core, state, unrelated_interleaving_test])

        self.assertIn(
            "state module must reference a core decision API reached by same-domain property interleavings",
            [violation.message for violation in violations],
        )

    def test_state_module_rejects_incidental_non_core_interleaving_api_reference(self):
        core = source_file(
            path="/repo/SQLiteStateDecider.swift",
            metadata={"moduleType": "core", "domain": "backend.sqlite", "exemptReason": ""},
            apiReferences=["SQLiteStateDecider"],
            identifiers=["SQLiteStateDecider"],
            decisionSurface=["SQLiteStateDecider"],
            propertyTestSurface=["SQLiteStateDecider"],
            decisionReferences=["SQLiteStateDecider"],
        )
        state = source_file(
            path="/repo/Store.swift",
            metadata={"moduleType": "state", "domain": "backend.sqlite", "exemptReason": ""},
            apiReferences=["SQLiteStore", "Date"],
        )
        incidental_interleaving_test = source_file(
            path="/repo/StoreTests.swift",
            metadata={"moduleType": "stateTest", "domain": "backend.sqlite", "exemptReason": ""},
            propertyChecks=[property_check(["Date"], interleaving=True)],
        )

        violations = evaluate.evaluate([core, state, incidental_interleaving_test])

        self.assertIn(
            "state module must reference a core decision API reached by same-domain property interleavings",
            [violation.message for violation in violations],
        )

    def test_state_module_accepts_reachable_same_domain_interleaving_api_reference(self):
        core = source_file(
            path="/repo/SQLiteStateDecider.swift",
            metadata={"moduleType": "core", "domain": "backend.sqlite", "exemptReason": ""},
            apiReferences=["SQLiteStateDecider"],
            identifiers=["SQLiteStateDecider"],
            decisionSurface=["SQLiteStateDecider"],
            propertyTestSurface=["SQLiteStateDecider"],
            decisionReferences=["SQLiteStateDecider"],
        )
        state = source_file(
            path="/repo/Store.swift",
            metadata={"moduleType": "state", "domain": "backend.sqlite", "exemptReason": ""},
            apiReferences=["SQLiteStore", "SQLiteStateDecider"],
            imports=["PersistenceKit"],
            effectfulImports=["PersistenceKit"],
        )
        linked_interleaving_test = source_file(
            path="/repo/StoreTests.swift",
            testScope="StoreTests",
            metadata={"moduleType": "stateTest", "domain": "backend.sqlite", "exemptReason": ""},
            apiReferences=["SQLiteStateDecider"],
            propertyChecks=[property_check(["SQLiteStateDecider"], interleaving=True)],
        )

        violations = evaluate.evaluate([core, state, linked_interleaving_test])

        self.assertEqual([], violations)

    def test_state_test_interleavings_must_reference_reachable_apis(self):
        state_test = source_file(
            path="/repo/StoreTests.swift",
            metadata={"moduleType": "stateTest", "domain": "backend.sqlite", "exemptReason": ""},
            apiReferences=["inputUse"],
            propertyChecks=[
                property_check(
                    [],
                    interleaving=True,
                    generated_inputs=[generated_input("input", uses=["inputUse"])],
                )
            ],
        )

        violations = evaluate.evaluate([state_test])

        self.assertIn(
            "stateTest module interleavings must reference reachable APIs",
            [violation.message for violation in violations],
        )

    def test_property_interleavings_may_only_appear_in_state_test_modules(self):
        test = source_file(
            path="/repo/CoreTests.swift",
            testScope="CoreTests",
            metadata={"moduleType": "test", "domain": "mail.sync", "exemptReason": ""},
            propertyChecks=[property_check(["decideSync"], interleaving=True)],
        )

        violations = evaluate.evaluate([test])

        self.assertIn(
            "property interleavings may only appear in stateTest modules",
            [violation.message for violation in violations],
        )

    def test_state_test_interleavings_must_reference_same_domain_core_decision_api(self):
        core = source_file(
            path="/repo/SQLiteStateDecider.swift",
            metadata={"moduleType": "core", "domain": "backend.sqlite", "exemptReason": ""},
            apiReferences=["SQLiteStateDecider"],
            identifiers=["SQLiteStateDecider"],
            decisionSurface=["SQLiteStateDecider"],
            propertyTestSurface=["SQLiteStateDecider"],
            decisionReferences=["SQLiteStateDecider"],
        )
        state_test = source_file(
            path="/repo/StoreTests.swift",
            testScope="StoreTests",
            metadata={"moduleType": "stateTest", "domain": "backend.sqlite", "exemptReason": ""},
            apiReferences=["Date"],
            propertyChecks=[property_check(["Date"], interleaving=True)],
        )

        violations = evaluate.evaluate([core, state_test])

        self.assertIn(
            "stateTest module interleavings must reference same-domain core decision APIs",
            [violation.message for violation in violations],
        )

    def test_state_test_module_requires_same_domain_state_module(self):
        core = source_file(
            path="/repo/SQLiteStateDecider.swift",
            metadata={"moduleType": "core", "domain": "backend.sqlite", "exemptReason": ""},
            apiReferences=["SQLiteStateDecider"],
            identifiers=["SQLiteStateDecider"],
            decisionSurface=["SQLiteStateDecider"],
            propertyTestSurface=["SQLiteStateDecider"],
            decisionReferences=["SQLiteStateDecider"],
        )
        state_test = source_file(
            path="/repo/StoreTests.swift",
            testScope="StoreTests",
            metadata={"moduleType": "stateTest", "domain": "backend.sqlite", "exemptReason": ""},
            apiReferences=["SQLiteStateDecider"],
            propertyChecks=[property_check(["SQLiteStateDecider"], interleaving=True)],
        )

        violations = evaluate.evaluate([core, state_test])

        self.assertIn(
            "stateTest module must have a same-domain state module",
            [violation.message for violation in violations],
        )

    def test_state_test_interleavings_accept_same_domain_core_decision_api_reference(self):
        core = source_file(
            path="/repo/SQLiteStateDecider.swift",
            metadata={"moduleType": "core", "domain": "backend.sqlite", "exemptReason": ""},
            apiReferences=["SQLiteStateDecider"],
            identifiers=["SQLiteStateDecider"],
            decisionSurface=["SQLiteStateDecider"],
            propertyTestSurface=["SQLiteStateDecider"],
            decisionReferences=["SQLiteStateDecider"],
        )
        state = source_file(
            path="/repo/Store.swift",
            metadata={"moduleType": "state", "domain": "backend.sqlite", "exemptReason": ""},
            apiReferences=["SQLiteStateDecider"],
            sharedState=[
                {
                    "kind": "test-shared-state",
                    "references": ["TestSharedState"],
                }
            ],
        )
        state_test = source_file(
            path="/repo/StoreTests.swift",
            testScope="StoreTests",
            metadata={"moduleType": "stateTest", "domain": "backend.sqlite", "exemptReason": ""},
            apiReferences=["SQLiteStateDecider"],
            propertyChecks=[property_check(["SQLiteStateDecider"], interleaving=True)],
        )

        violations = evaluate.evaluate([core, state, state_test])

        self.assertEqual([], violations)

    def test_state_module_must_own_stateful_api(self):
        core = source_file(
            path="/repo/SQLiteStateDecider.swift",
            metadata={"moduleType": "core", "domain": "backend.sqlite", "exemptReason": ""},
            apiReferences=["SQLiteStateDecider"],
            decisionSurface=["SQLiteStateDecider"],
            propertyTestSurface=["SQLiteStateDecider"],
            decisionReferences=["SQLiteStateDecider"],
        )
        state = source_file(
            path="/repo/Store.swift",
            metadata={"moduleType": "state", "domain": "backend.sqlite", "exemptReason": ""},
            apiReferences=["SQLiteStateDecider"],
        )
        state_test = source_file(
            path="/repo/StoreTests.swift",
            testScope="StoreTests",
            metadata={"moduleType": "stateTest", "domain": "backend.sqlite", "exemptReason": ""},
            propertyChecks=[property_check(["SQLiteStateDecider"], interleaving=True)],
        )

        violations = evaluate.evaluate([core, state, state_test])

        self.assertIn("state module must own stateful APIs", [violation.message for violation in violations])

    def test_interface_module_reports_adapter_logic_findings(self):
        interface = source_file(
            path="/repo/Types.swift",
            metadata={"moduleType": "interface", "domain": "mail.sync", "exemptReason": ""},
            identifiers=["makeValue"],
            interfaceLogicEvidence={
                **empty_interface_logic_evidence(),
                "functionBodies": ["makeValue"],
            },
        )

        violations = evaluate.evaluate([interface])

        self.assertEqual(
            [evaluate.Violation("/repo/Types.swift", "interface module must not contain function bodies")],
            violations,
        )

    def test_interface_module_policy_messages_are_owned_by_evaluator(self):
        interface = source_file(
            path="/repo/Types.swift",
            metadata={"moduleType": "interface", "domain": "mail.sync", "exemptReason": ""},
            identifiers=["makeValue", "init", "computed", "Widget"],
            interfaceLogicEvidence={
                "functionBodies": ["makeValue"],
                "constructorBodies": ["init"],
                "derivedValueBodies": ["computed"],
                "controlFlow": ["if"],
                "imperativeDeclarations": ["var"],
            },
        )

        violations = evaluate.evaluate([interface])

        self.assertEqual(
            [
                "interface module must not contain function bodies",
                "interface module must not contain constructor bodies",
                "interface module must not contain derived value bodies",
                "interface module must not contain control flow",
                "interface module may only declare imports, types, and constants",
            ],
            [violation.message for violation in violations],
        )

    def test_pure_glue_exemption_must_not_contain_decision_control_flow(self):
        pure_glue = source_file(
            path="/repo/Glue.ml",
            metadata={"moduleType": "exempt", "domain": "", "exemptReason": "pure-glue"},
            interfaceLogicEvidence={
                **empty_interface_logic_evidence(),
                "controlFlow": ["match"],
            },
        )

        violations = evaluate.evaluate([pure_glue])

        self.assertIn(
            "pure-glue exemption must not contain decision control flow",
            [violation.message for violation in violations],
        )

    def test_effect_boundary_exemption_must_touch_effectful_api(self):
        boundary = source_file(
            path="/repo/Boundary.swift",
            metadata={"moduleType": "exempt", "domain": "", "exemptReason": "effect-boundary"},
            imports=[],
        )

        violations = evaluate.evaluate([boundary])

        self.assertIn(
            "effect-boundary exemption must touch effectful APIs",
            [violation.message for violation in violations],
        )

    def test_effect_boundary_exemption_may_own_runtime_shared_state(self):
        boundary = source_file(
            path="/repo/Boundary.ml",
            metadata={"moduleType": "exempt", "domain": "", "exemptReason": "effect-boundary"},
            identifiers=["EffectType", "cache"],
            effectfulIdentifiers=["EffectType"],
            sharedState=[{"kind": "runtime-cache", "references": ["cache"]}],
        )

        violations = evaluate.evaluate([boundary])

        self.assertEqual([], violations)

    def test_effect_facade_exemption_must_not_touch_effectful_api_directly(self):
        facade = source_file(
            path="/repo/Facade.swift",
            metadata={"moduleType": "exempt", "domain": "", "exemptReason": "effect-facade"},
            imports=["EffectFramework"],
            effectfulImports=["EffectFramework"],
        )

        violations = evaluate.evaluate([facade])

        self.assertIn(
            "effect-facade exemption must not touch effectful APIs directly",
            [violation.message for violation in violations],
        )

    def test_pure_glue_exemption_must_not_touch_effectful_api(self):
        pure_glue = source_file(
            path="/repo/Context.ml",
            metadata={"moduleType": "exempt", "domain": "", "exemptReason": "pure-glue"},
            imports=["EffectFramework"],
            effectfulImports=["EffectFramework"],
        )

        violations = evaluate.evaluate([pure_glue])

        self.assertIn(
            "pure-glue exemption must not touch effectful APIs",
            [violation.message for violation in violations],
        )

    def test_static_data_exemption_must_not_touch_effectful_api(self):
        static_data = source_file(
            path="/repo/Data.go",
            metadata={"moduleType": "exempt", "domain": "", "exemptReason": "static-data"},
            imports=["effect.boundary"],
            effectfulImports=["effect.boundary"],
        )

        violations = evaluate.evaluate([static_data])

        self.assertIn(
            "static-data exemption must not touch effectful APIs",
            [violation.message for violation in violations],
        )

    def test_exemption_admissibility_accepts_every_allowed_shape(self):
        valid_exemptions = [
            source_file(
                path="/repo/MailApp.swift",
                metadata={"moduleType": "exempt", "domain": "", "exemptReason": "entrypoint"},
            ),
            source_file(
                path="/repo/View.swift",
                metadata={"moduleType": "exempt", "domain": "", "exemptReason": "pure-glue"},
            ),
            source_file(
                path="/repo/Boundary.swift",
                metadata={"moduleType": "exempt", "domain": "", "exemptReason": "effect-boundary"},
                imports=["EffectFramework"],
                effectfulImports=["EffectFramework"],
            ),
            source_file(
                path="/repo/Facade.swift",
                metadata={"moduleType": "exempt", "domain": "", "exemptReason": "effect-facade"},
            ),
            source_file(
                path="/repo/Context.go",
                metadata={"moduleType": "exempt", "domain": "", "exemptReason": "pure-glue"},
            ),
            source_file(
                path="/repo/Prototype.swift",
                metadata={"moduleType": "exempt", "domain": "", "exemptReason": "static-data"},
            ),
            source_file(
                path="/repo/Fixture.swift",
                metadata={"moduleType": "exempt", "domain": "", "exemptReason": "test-support"},
            ),
        ]

        violations = evaluate.evaluate(valid_exemptions)

        self.assertEqual([], violations)

    def test_exemption_admissibility_does_not_make_exemption_a_domain_module_type(self):
        pure_glue = source_file(
            path="/repo/Glue.ml",
            metadata={"moduleType": "exempt", "domain": "", "exemptReason": "pure-glue"},
            apiReferences=[],
        )

        violations = evaluate.evaluate([pure_glue])

        self.assertEqual([], violations)

    def test_exempt_module_must_not_declare_domain(self):
        exempt = source_file(
            path="/repo/View.swift",
            metadata={"moduleType": "exempt", "domain": "mail.sync", "exemptReason": "pure-glue"},
        )

        violations = evaluate.evaluate([exempt])

        self.assertIn(
            "exempt module must not declare @archlint.domain",
            [violation.message for violation in violations],
        )

    def test_test_module_must_be_declared_in_test_scope(self):
        test_module = source_file(
            path="/repo/Production.swift",
            metadata={"moduleType": "test", "domain": "mail.sync", "exemptReason": ""},
        )

        violations = evaluate.evaluate([test_module])

        self.assertIn(
            "test module must be declared in a test scope",
            [violation.message for violation in violations],
        )

    def test_domain_must_use_lowercase_dot_or_kebab_segments(self):
        module = source_file(
            path="/repo/Core.swift",
            metadata={"moduleType": "core", "domain": "Backend_HTTP", "exemptReason": ""},
        )

        violations = evaluate.evaluate([module])

        self.assertIn(
            "module domain must be lowercase dot-or-kebab segments",
            [violation.message for violation in violations],
        )

    def test_production_module_must_not_be_declared_in_test_scope(self):
        production_module = source_file(
            path="/repo/CoreTests.swift",
            testScope="CoreTests",
            metadata={"moduleType": "core", "domain": "mail.sync", "exemptReason": ""},
        )
        test_module = source_file(
            path="/repo/ActualTests.swift",
            testScope="ActualTests",
            metadata={"moduleType": "test", "domain": "mail.sync", "exemptReason": ""},
            propertyChecks=[property_check(["decideSync"])],
        )

        violations = evaluate.evaluate([production_module, test_module])

        self.assertIn(
            "production module must not be declared in a test scope",
            [violation.message for violation in violations],
        )

    def test_domain_breadth_is_limited_by_structure_not_specific_domain_names(self):
        files = [
            source_file(
                path=f"/repo/Domain/File{index}.swift",
                metadata={"moduleType": "core", "domain": "any.overbroad.domain", "exemptReason": ""},
            )
            for index in range(evaluate.DOMAIN_PRODUCTION_MODULE_LIMIT + 1)
        ]

        violations = evaluate.evaluate(files)

        self.assertIn(
            f"domain has {evaluate.DOMAIN_PRODUCTION_MODULE_LIMIT + 1} production modules; maximum is {evaluate.DOMAIN_PRODUCTION_MODULE_LIMIT}",
            [violation.message for violation in violations],
        )

    def test_domain_breadth_ignores_interfaces_tests_and_exempt_modules(self):
        files = [
            source_file(
                path=f"/repo/Domain/File{index}.swift",
                metadata={"moduleType": "core", "domain": "bounded.domain", "exemptReason": ""},
            )
            for index in range(evaluate.DOMAIN_PRODUCTION_MODULE_LIMIT)
        ]
        files.extend(
            source_file(
                path=f"/repo/Domain/File{index}.swift",
                metadata={"moduleType": "interface", "domain": "bounded.domain", "exemptReason": ""},
                decisionSurface=[],
                propertyTestSurface=[],
                decisionProducts=[],
                decisionReferences=[],
                apiReferences=[],
            )
            for index in range(evaluate.DOMAIN_PRODUCTION_MODULE_LIMIT)
        )
        files.extend(
            source_file(
                path=f"/repo/Domain/File{index}Tests.swift",
                testScope=f"File{index}Tests",
                metadata={"moduleType": "test", "domain": "bounded.domain", "exemptReason": ""},
                decisionSurface=[],
                propertyTestSurface=[],
                decisionProducts=[],
                decisionReferences=[],
                apiReferences=[],
            )
            for index in range(evaluate.DOMAIN_PRODUCTION_MODULE_LIMIT)
        )

        violations = evaluate.evaluate(files)

        self.assertNotIn(
            f"domain has {evaluate.DOMAIN_PRODUCTION_MODULE_LIMIT + 1} production modules; maximum is {evaluate.DOMAIN_PRODUCTION_MODULE_LIMIT}",
            [violation.message for violation in violations],
        )

    def test_domain_breadth_ignores_value_modules(self):
        files = [
            source_file(
                path=f"/repo/Domain/File{index}.swift",
                metadata={"moduleType": "core", "domain": "bounded.domain", "exemptReason": ""},
            )
            for index in range(evaluate.DOMAIN_PRODUCTION_MODULE_LIMIT)
        ]
        files.extend(
            source_file(
                path=f"/repo/Domain/Value{index}.swift",
                metadata={"moduleType": "value", "domain": "bounded.domain", "exemptReason": ""},
                decisionSurface=[],
                propertyTestSurface=[],
                decisionProducts=[],
                decisionReferences=[],
                apiReferences=[],
            )
            for index in range(evaluate.DOMAIN_PRODUCTION_MODULE_LIMIT)
        )

        violations = evaluate.evaluate(files)

        self.assertNotIn(
            f"domain has {evaluate.DOMAIN_PRODUCTION_MODULE_LIMIT + 1} production modules; maximum is {evaluate.DOMAIN_PRODUCTION_MODULE_LIMIT}",
            [violation.message for violation in violations],
        )

    def test_fact_schema_artifact_is_valid_json_schema(self):
        Draft202012Validator.check_schema(evaluate.load_fact_schema())

    def test_evaluator_loads_fact_schema_from_schema_artifact(self):
        self.assertEqual(evaluate.load_fact_schema(), evaluate.FACT_SCHEMA)
        self.assertEqual(
            {"core", "interface", "value", "shell", "state", "test", "stateTest", "exempt"},
            evaluate.VALID_MODULE_TYPES,
        )

    def test_value_module_allows_derived_value_bodies_but_rejects_callable_bodies(self):
        value = source_file(
            path="/repo/Value.swift",
            metadata={"moduleType": "value", "domain": "mail.sync", "exemptReason": ""},
            identifiers=["makeValue", "computed", "Widget"],
            interfaceLogicEvidence={
                **empty_interface_logic_evidence(),
                "functionBodies": ["makeValue"],
                "derivedValueBodies": ["computed"],
                "controlFlow": ["if"],
            },
        )

        violations = evaluate.evaluate([value])

        self.assertEqual(
            [
                evaluate.Violation("/repo/Value.swift", "value module must not contain function bodies"),
                evaluate.Violation("/repo/Value.swift", "value module must not contain control flow"),
            ],
            violations,
        )

    def test_value_module_rejects_imperative_declarations(self):
        value = source_file(
            path="/repo/Value.go",
            metadata={"moduleType": "value", "domain": "mail.sync", "exemptReason": ""},
            interfaceLogicEvidence={
                **empty_interface_logic_evidence(),
                "imperativeDeclarations": ["var"],
            },
        )

        violations = evaluate.evaluate([value])

        self.assertEqual(
            [
                evaluate.Violation(
                    "/repo/Value.go",
                    "value module may only declare imports, types, and constants",
                )
            ],
            violations,
        )

    def test_parse_fact_document_rejects_missing_required_fields(self):
        document = {"files": [{"path": "/repo/Core.swift"}]}

        with self.assertRaisesRegex(ValueError, "fact document schema violation"):
            evaluate.parse_fact_document(document)

    def test_parse_fact_document_rejects_unknown_fields(self):
        document = {"files": [], "version": 1}

        with self.assertRaisesRegex(ValueError, "Additional properties are not allowed"):
            evaluate.parse_fact_document(document)

    def test_parse_fact_document_rejects_wrong_field_types(self):
        document = valid_fact_document()
        document["files"][0]["propertyChecks"] = "false"

        with self.assertRaisesRegex(ValueError, r"\$\.files\[0\]\.propertyChecks"):
            evaluate.parse_fact_document(document)

    def test_parse_fact_document_rejects_derived_fact_fields(self):
        for derived_field in [
            "hasEffectfulImports",
            "hasSharedMutableState",
            "hasPropertyTest",
            "propertyTestReferences",
            "hasPropertyInterleavings",
            "propertyInterleavingReferences",
        ]:
            with self.subTest(derived_field=derived_field):
                document = valid_fact_document()
                document["files"][0][derived_field] = True

                with self.assertRaisesRegex(ValueError, r"\$\.files\[0\]"):
                    evaluate.parse_fact_document(document)

    def test_parse_fact_document_rejects_malformed_shared_state_evidence(self):
        document = valid_fact_document()
        document["files"][0]["sharedState"] = [{"kind": "go-sync"}]

        with self.assertRaisesRegex(ValueError, r"\$\.files\[0\]\.sharedState\[0\]"):
            evaluate.parse_fact_document(document)

    def test_parse_fact_document_rejects_unknown_module_types(self):
        document = valid_fact_document()
        document["files"][0]["metadata"]["moduleType"] = "handler"

        with self.assertRaisesRegex(ValueError, r"\$\.files\[0\]\.metadata\.moduleType"):
            evaluate.parse_fact_document(document)

    def test_parse_fact_document_rejects_unknown_exempt_reasons(self):
        document = valid_fact_document()
        document["files"][0]["metadata"]["exemptReason"] = "miscellaneous"

        with self.assertRaisesRegex(ValueError, r"\$\.files\[0\]\.metadata\.exemptReason"):
            evaluate.parse_fact_document(document)

    def test_parse_fact_document_rejects_empty_file_paths(self):
        document = valid_fact_document()
        document["files"][0]["path"] = ""

        with self.assertRaisesRegex(ValueError, r"\$\.files\[0\]\.path"):
            evaluate.parse_fact_document(document)

    def test_parse_fact_document_rejects_duplicate_list_evidence(self):
        document = valid_fact_document()
        document["files"][0]["identifiers"] = ["decideSync", "decideSync"]

        with self.assertRaisesRegex(ValueError, r"\$\.files\[0\]\.identifiers"):
            evaluate.parse_fact_document(document)

    def test_parse_fact_document_rejects_blank_list_evidence(self):
        document = valid_fact_document()
        document["files"][0]["decisionSurface"] = [""]

        with self.assertRaisesRegex(ValueError, r"\$\.files\[0\]\.decisionSurface\[0\]"):
            evaluate.parse_fact_document(document)

    def test_parse_fact_document_accepts_complete_adapter_schema(self):
        files = evaluate.parse_fact_document(valid_fact_document())

        self.assertEqual(1, len(files))
        self.assertEqual("/repo/Core.swift", files[0].path)
        self.assertEqual({"decideSync"}, files[0].decision_surface)

    def test_evaluate_adapters_evaluates_each_adapter_document_independently(self):
        go_core = source_file(
            path="/repo/apps/backend/internal/mail/decision.go",
            metadata={"moduleType": "core", "domain": "mail.sync", "exemptReason": ""},
            identifiers=["DecideSync"],
            apiReferences=["DecideSync"],
            decisionSurface=["DecideSync"],
            propertyTestSurface=["DecideSync"],
            decisionReferences=["DecideSync"],
        )
        swift_test = source_file(
            path="/repo/apps/ios/MailAppTests/MailDeciderTests.swift",
            testScope="MailDeciderTests",
            metadata={"moduleType": "test", "domain": "mail.sync", "exemptReason": ""},
            identifiers=["DecideSync"],
            apiReferences=["DecideSync"],
            propertyChecks=[property_check(["DecideSync"])],
        )

        def fake_run_adapter(repo_root, adapter, go_module, go_packages, swift_xcodegen, ocaml_root):
            self.assertEqual(Path("/repo"), repo_root)
            self.assertEqual("backend-module", go_module)
            self.assertEqual("./domain/...", go_packages)
            self.assertEqual("client/project.yml", swift_xcodegen)
            self.assertEqual("src", ocaml_root)
            return {"go": [go_core], "swift": [swift_test]}[adapter]

        with mock.patch.object(evaluate, "run_adapter", side_effect=fake_run_adapter):
            violations = evaluate.evaluate_adapters(
                Path("/repo"),
                ["go", "swift"],
                go_module="backend-module",
                go_packages="./domain/...",
                swift_xcodegen="client/project.yml",
                ocaml_root="src",
            )

        self.assertIn(
            evaluate.Violation(
                "/repo/apps/backend/internal/mail/decision.go",
                "core module must have a same-domain test or stateTest module",
            ),
            violations,
        )

    def test_run_adapter_parses_adapter_json_without_evaluating_policy(self):
        payload = {
            "files": [
                {
                    "path": "/repo/apps/backend/internal/mail/decision.go",
                    "testScope": "",
                    "metadata": {"moduleType": "core", "domain": "mail.sync", "exemptReason": ""},
                    "imports": [],
                    "identifiers": ["DecideSync"],
                    "apiReferences": ["DecideSync"],
                    "decisionSurface": ["DecideSync"],
                    "propertyTestSurface": ["DecideSync"],
                    "decisionProducts": [],
                    "decisionReferences": ["DecideSync"],
                    "effectfulImports": [],
                    "effectfulIdentifiers": [],
                    "sharedState": [],
                    "propertyChecks": [],
                    "interfaceLogicEvidence": empty_interface_logic_evidence(),
                }
            ]
        }
        completed = subprocess_result(stdout=evaluate.json.dumps(payload), returncode=0)

        with mock.patch.object(evaluate.subprocess, "run", return_value=completed) as run:
            files = evaluate.run_adapter(
                Path("/repo"),
                "go",
                go_module="backend-module",
                go_packages="./domain/...",
                swift_xcodegen=None,
                ocaml_root=None,
            )

        self.assertEqual(1, len(files))
        self.assertEqual("/repo/apps/backend/internal/mail/decision.go", files[0].path)
        self.assertEqual({"DecideSync"}, files[0].decision_surface)
        self.assertIn("--repo-root", run.call_args.args[0])
        self.assertIn("--go-module", run.call_args.args[0])
        self.assertIn("--go-packages", run.call_args.args[0])
        self.assertEqual("backend-module", run.call_args.args[0][run.call_args.args[0].index("--go-module") + 1])
        self.assertEqual("./domain/...", run.call_args.args[0][run.call_args.args[0].index("--go-packages") + 1])

    def test_run_ocaml_adapter_constructs_dune_command(self):
        payload = valid_fact_document()
        payload["files"][0]["path"] = "/repo/lib/decision.ml"
        completed = subprocess_result(stdout=evaluate.json.dumps(payload), returncode=0)

        with mock.patch.object(evaluate.subprocess, "run", return_value=completed) as run:
            files = evaluate.run_adapter(
                Path("/repo"),
                "ocaml",
                go_module=None,
                go_packages=None,
                swift_xcodegen=None,
                ocaml_root="lib",
            )

        self.assertEqual("/repo/lib/decision.ml", files[0].path)
        command = run.call_args.args[0]
        self.assertEqual("dune", command[0])
        self.assertIn("--root", command)
        self.assertIn("./main.exe", command)
        self.assertEqual("lib", command[command.index("--ocaml-root") + 1])

    def test_run_adapter_reports_adapter_failure_output(self):
        completed = subprocess_result(stdout="partial output\n", stderr="adapter error\n", returncode=2)

        with mock.patch.object(evaluate.subprocess, "run", return_value=completed):
            with self.assertRaisesRegex(RuntimeError, "go adapter failed: partial output\nadapter error"):
                evaluate.run_adapter(
                    Path("/repo"),
                    "go",
                    go_module="backend-module",
                    go_packages="./domain/...",
                    swift_xcodegen=None,
                    ocaml_root=None,
                )

    def test_main_with_adapter_evaluates_adapter_documents(self):
        violation = evaluate.Violation(
            "/repo/Core.swift",
            "core module must have a same-domain test or stateTest module",
        )

        with mock.patch.object(evaluate, "evaluate_adapters", return_value=[violation]):
            with mock.patch.object(
                sys,
                "argv",
                [
                    "evaluate.py",
                    "--repo-root",
                    "/repo",
                    "--adapter",
                    "swift",
                    "--swift-xcodegen",
                    "client/project.yml",
                ],
            ):
                with mock.patch("sys.stdout") as stdout:
                    status = evaluate.main()

        self.assertEqual(1, status)
        rendered = "".join(call.args[0] for call in stdout.write.call_args_list if call.args)
        self.assertIn("core module must have a same-domain test or stateTest module", rendered)


def subprocess_result(stdout="", stderr="", returncode=0):
    return evaluate.subprocess.CompletedProcess(
        args=["adapter"], returncode=returncode, stdout=stdout, stderr=stderr
    )


def valid_fact_document():
    return {
        "files": [
            {
                "path": "/repo/Core.swift",
                "testScope": "",
                "metadata": {
                    "moduleType": "core",
                    "domain": "mail.sync",
                    "exemptReason": "",
                },
                "imports": [],
                "identifiers": ["decideSync"],
                "apiReferences": ["decideSync"],
                "decisionSurface": ["decideSync"],
                "propertyTestSurface": ["decideSync"],
                "decisionProducts": [],
                "decisionReferences": ["decideSync"],
                "effectfulImports": [],
                "effectfulIdentifiers": [],
                "sharedState": [],
                "propertyChecks": [],
                "interfaceLogicEvidence": empty_interface_logic_evidence(),
            }
        ]
    }


def empty_interface_logic_evidence():
    return {
        "functionBodies": [],
        "constructorBodies": [],
        "derivedValueBodies": [],
        "controlFlow": [],
        "imperativeDeclarations": [],
    }


if __name__ == "__main__":
    unittest.main()
