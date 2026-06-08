#!/usr/bin/env sh
set -eu

package_root="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(CDPATH= cd -- "$package_root/.." && pwd)"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT INT TERM
export UV_CACHE_DIR="${UV_CACHE_DIR:-$tmp_root/uv-cache}"

ARCHLINT_ROOT="$repo_root"
. "$repo_root/test/lib.sh"

run_lint() {
  uv run --project "$repo_root" python "$repo_root/evaluate.py" --repo-root "$1" --adapter swift --swift-xcodegen apps/ios/project.yml
}

run_adapter() {
  swift run --package-path "$package_root" SwiftArchLint --repo-root "$1" --xcodegen apps/ios/project.yml
}

new_fixture() {
  name="$1"
  fixture="$tmp_root/$name"
  copy_fixture "$package_root/fixtures/_shared" "$fixture"
  copy_fixture "$package_root/fixtures/$name" "$fixture"
  printf '%s\n' "$fixture"
}

passing_fixture="$(new_fixture passing)"
assert_passes "$passing_fixture"

run_adapter "$passing_fixture" > "$tmp_root/passing-facts.json"
assert_facts "$tmp_root/passing-facts.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
shell = [item for item in document["files"] if item["path"].endswith("HTTPMailBackendClient.swift")][0]
assert shell["moduleName"] == "HTTPMailBackendClient", shell
assert "HTTPMailBackendDecider.decidePath" in shell["qualifiedReferences"], shell
core = [item for item in document["files"] if item["path"].endswith("HTTPMailBackendDecider.swift")][0]
assert core["moduleName"] == "HTTPMailBackendDecider", core
assert core["qualifiedReferences"] == [], core
PY

cross_file_bare_reference_fixture="$(new_fixture cross-file-bare-reference)"
run_adapter "$cross_file_bare_reference_fixture" > "$tmp_root/cross-file-bare-reference-facts.json"
assert_facts "$tmp_root/cross-file-bare-reference-facts.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
shell = [item for item in document["files"] if item["path"].endswith("HTTPMailBackendClient.swift")][0]
assert "HTTPMailBackendDecider.decidePath" in shell["qualifiedReferences"], shell
assert "HTTPMailBackendClient.decidePathForRequest" not in shell["qualifiedReferences"], shell
assert "HTTPMailBackendDecider.decidePathForRequest" not in shell["qualifiedReferences"], shell
PY

missing_core_reference_fixture="$(new_fixture missing-core-reference)"
assert_fails_with "$missing_core_reference_fixture" \
  "shell module must reference a core API in the same @archlint.domain"

local_core_name_only_fixture="$(new_fixture local-core-name-only)"
assert_fails_with "$local_core_name_only_fixture" \
  "shell module must reference a core API in the same @archlint.domain"

static_property_decision_surface_fixture="$(new_fixture static-property-decision-surface)"
assert_passes "$static_property_decision_surface_fixture"

closure_fixture="$(new_fixture closure)"
assert_passes "$closure_fixture"

arbitrary_core_type_reference_fixture="$(new_fixture arbitrary-core-type-reference)"
assert_fails_with "$arbitrary_core_type_reference_fixture" \
  "shell module must reference a core API in the same @archlint.domain"

missing_metadata_fixture="$(new_fixture missing-metadata)"
assert_fails_with "$missing_metadata_fixture" "module must declare @archlint.module"

metadata_after_source_fixture="$(new_fixture metadata-after-source)"
assert_fails_with "$metadata_after_source_fixture" "module must declare @archlint.module"

duplicate_module_metadata_fixture="$(new_fixture duplicate-module-metadata)"
assert_fails_with "$duplicate_module_metadata_fixture" "module must declare @archlint.module"

duplicate_domain_metadata_fixture="$(new_fixture duplicate-domain-metadata)"
assert_fails_with "$duplicate_domain_metadata_fixture" "module must declare @archlint.domain"

duplicate_exempt_reason_metadata_fixture="$(new_fixture duplicate-exempt-reason-metadata)"
assert_fails_with "$duplicate_exempt_reason_metadata_fixture" \
  "exempt module must declare @archlint.exempt-reason"

test_module_in_production_fixture="$(new_fixture test-module-in-production)"
assert_fails_with "$test_module_in_production_fixture" \
  "test module must be declared in a test scope"

malformed_domain_fixture="$(new_fixture malformed-domain)"
assert_fails_with "$malformed_domain_fixture" \
  "module domain must be lowercase dot-or-kebab segments"

production_module_in_test_fixture="$(new_fixture production-module-in-test)"
assert_fails_with "$production_module_in_test_fixture" \
  "production module must not be declared in a test scope"

missing_exempt_reason_fixture="$(new_fixture missing-exempt-reason)"
assert_fails_with "$missing_exempt_reason_fixture" \
  "exempt module must declare @archlint.exempt-reason"

exempt_domain_fixture="$(new_fixture exempt-domain)"
assert_fails_with "$exempt_domain_fixture" \
  "exempt module must not declare @archlint.domain"

unknown_exempt_reason_fixture="$(new_fixture unknown-exempt-reason)"
assert_fails_with "$unknown_exempt_reason_fixture" "metadata.exemptReason"

exempt_reason_outside_exempt_fixture="$(new_fixture exempt-reason-outside-exempt)"
assert_fails_with "$exempt_reason_outside_exempt_fixture" \
  "@archlint.exempt-reason is only valid on exempt modules"

entrypoint_exemption_fixture="$(new_fixture entrypoint-exemption)"
assert_passes "$entrypoint_exemption_fixture"

pure_glue_exemption_fixture="$(new_fixture pure-glue-exemption)"
assert_passes "$pure_glue_exemption_fixture"

effect_boundary_exemption_fixture="$(new_fixture effect-boundary-exemption)"
assert_passes "$effect_boundary_exemption_fixture"

effect_facade_exemption_fixture="$(new_fixture effect-facade-exemption)"
assert_passes "$effect_facade_exemption_fixture"

static_data_exemption_fixture="$(new_fixture static-data-exemption)"
assert_passes "$static_data_exemption_fixture"

test_support_exemption_fixture="$(new_fixture test-support-exemption)"
assert_passes "$test_support_exemption_fixture"

generic_domain_fixture="$(new_fixture generic-domain)"
assert_fails_with "$generic_domain_fixture" \
  "domain has 17 production modules; maximum is 16"

interface_generic_domain_fixture="$(new_fixture interface-generic-domain)"
assert_passes "$interface_generic_domain_fixture"

interface_with_logic_fixture="$(new_fixture interface-with-logic)"
assert_fails_with "$interface_with_logic_fixture" \
  "interface module must not contain derived value bodies"

value_with_computed_property_fixture="$(new_fixture value-with-computed-property)"
assert_passes "$value_with_computed_property_fixture"

value_with_branching_computed_property_fixture="$(new_fixture value-with-branching-computed-property)"
assert_fails_with "$value_with_branching_computed_property_fixture" \
  "value module must not contain control flow"

value_with_callable_decision_fixture="$(new_fixture value-with-callable-decision)"
assert_fails_with "$value_with_callable_decision_fixture" \
  "value module must not contain function bodies"

core_enum_case_matching_shell_method_fixture="$(new_fixture core-enum-case-matching-shell-method)"
assert_fails_with "$core_enum_case_matching_shell_method_fixture" \
  "shell module must reference a core API in the same @archlint.domain"

empty_decider_fixture="$(new_fixture empty-decider)"
assert_fails_with "$empty_decider_fixture" \
  "core module must declare a callable decision API"
assert_fails_with "$empty_decider_fixture" \
  "core module must have a same-domain test or stateTest module"

type_only_decider_fixture="$(new_fixture type-only-decider)"
assert_fails_with "$type_only_decider_fixture" \
  "core module must declare a callable decision API"

effectful_decider_fixture="$(new_fixture effectful-decider)"
assert_fails_with "$effectful_decider_fixture" \
  "effectful identifiers may only appear in shell, state, interface, test, stateTest, or exempt modules"
assert_fails_with "$effectful_decider_fixture" \
  "core module must have a same-domain test or stateTest module"

missing_property_fixture="$(new_fixture missing-property)"
assert_fails_with "$missing_property_fixture" \
  "core module test must contain at least one property test"

property_import_only_fixture="$(new_fixture property-import-only)"
assert_fails_with "$property_import_only_fixture" \
  "core module test must contain at least one property test"

property_name_only_fixture="$(new_fixture property-name-only)"
assert_fails_with "$property_name_only_fixture" \
  "core module test must contain at least one property test"

unrelated_property_test_fixture="$(new_fixture unrelated-property-test)"
assert_fails_with "$unrelated_property_test_fixture" \
  "core module property tests must reference every decision API: decidePath"

property_local_core_name_only_fixture="$(new_fixture property-local-core-name-only)"
assert_fails_with "$property_local_core_name_only_fixture" \
  "core module property tests must reference every decision API: decidePath"

property_reachable_helper_fixture="$(new_fixture property-reachable-helper)"
assert_passes "$property_reachable_helper_fixture"
assert_fact_refs_contain \
  "$property_reachable_helper_fixture" \
  "HTTPMailBackendDeciderPropertySuite.swift" \
  "propertyTestReferences" \
  "decidePath"

ordinary_array_property_fixture="$(new_fixture ordinary-array-property)"
assert_passes "$ordinary_array_property_fixture"
assert_fact_refs_contain \
  "$ordinary_array_property_fixture" \
  "HTTPMailBackendDeciderPropertySuite.swift" \
  "propertyTestReferences" \
  "decode"
assert_fact_refs_not_contain \
  "$ordinary_array_property_fixture" \
  "HTTPMailBackendDeciderPropertySuite.swift" \
  "propertyOperationSequenceReferences" \
  "decode"

property_unreachable_helper_fixture="$(new_fixture property-unreachable-helper)"
assert_fails_with "$property_unreachable_helper_fixture" \
  "core module property tests must reference every decision API: decidePath"

wrong_domain_test_fixture="$(new_fixture wrong-domain-test)"
assert_fails_with "$wrong_domain_test_fixture" \
  "core module must have a same-domain test or stateTest module"

wrong_test_module_type_fixture="$(new_fixture wrong-test-module-type)"
assert_fails_with "$wrong_test_module_type_fixture" \
  "core module must have a same-domain test or stateTest module"

non_decider_core_fixture="$(new_fixture non-decider-core)"
assert_fails_with "$non_decider_core_fixture" \
  "core module must have a same-domain test or stateTest module"

state_test_without_operation_sequences_fixture="$(new_fixture state-test-without-operation-sequences)"
assert_fails_with "$state_test_without_operation_sequences_fixture" \
  "stateTest module must contain property operation sequences"

state_test_operation_sequences_without_refs_fixture="$(new_fixture state-test-operation-sequences-without-refs)"
assert_fails_with "$state_test_operation_sequences_without_refs_fixture" \
  "stateTest module must contain property operation sequences"

state_test_operation_sequences_without_core_refs_fixture="$(new_fixture state-test-operation-sequences-without-core-refs)"
assert_fails_with "$state_test_operation_sequences_without_core_refs_fixture" \
  "stateTest module operation sequences must reference same-domain core decision APIs"

state_test_without_state_module_fixture="$(new_fixture state-test-without-state-module)"
assert_fails_with "$state_test_without_state_module_fixture" \
  "stateTest module must have a same-domain state module"

state_test_operation_sequence_refs_fixture="$(new_fixture state-test-operation-sequence-refs)"
assert_fact_refs_contain \
  "$state_test_operation_sequence_refs_fixture" \
  "SQLiteMailSyncStateDeciderPropertySuite.swift" \
  "propertyOperationSequenceReferences" \
  "reduce"

state_unrelated_to_operation_sequences_fixture="$(new_fixture state-unrelated-to-operation-sequences)"
assert_fails_with "$state_unrelated_to_operation_sequences_fixture" \
  "state module must reference a core decision API reached by same-domain property operation sequences"

state_without_stateful_apis_fixture="$(new_fixture state-without-stateful-apis)"
assert_fails_with "$state_without_stateful_apis_fixture" \
  "state module must own stateful APIs"

shared_state_without_state_test_fixture="$(new_fixture shared-state-without-state-test)"
assert_fails_with "$shared_state_without_state_test_fixture" \
  "state module must have a same-domain stateTest with property operation sequences"

shared_state_outside_state_fixture="$(new_fixture shared-state-outside-state)"
assert_fails_with "$shared_state_outside_state_fixture" \
  "shared mutable state may only appear in state, test, or stateTest modules"
assert_shared_state_contains "$shared_state_outside_state_fixture" \
  "FakeMailBackendClient.swift" "swift-actor-var" "FakeMailBackendClient"

shared_state_comment_only_fixture="$(new_fixture shared-state-comment-only)"
assert_passes "$shared_state_comment_only_fixture"

published_state_outside_state_fixture="$(new_fixture published-state-outside-state)"
assert_fails_with "$published_state_outside_state_fixture" \
  "shared mutable state may only appear in state, test, or stateTest modules"
assert_shared_state_contains "$published_state_outside_state_fixture" \
  "FakeMailBackendClient.swift" "swift-published" "@Published"

database_queue_state_outside_state_fixture="$(new_fixture database-queue-state-outside-state)"
assert_fails_with "$database_queue_state_outside_state_fixture" \
  "shared mutable state may only appear in state, test, or stateTest modules"
assert_shared_state_contains "$database_queue_state_outside_state_fixture" \
  "FakeMailBackendClient.swift" "swift-database-queue" "DatabaseQueue"

user_defaults_state_outside_state_fixture="$(new_fixture user-defaults-state-outside-state)"
assert_fails_with "$user_defaults_state_outside_state_fixture" \
  "shared mutable state may only appear in state, test, or stateTest modules"
assert_shared_state_contains "$user_defaults_state_outside_state_fixture" \
  "FakeMailBackendClient.swift" "swift-user-defaults" "UserDefaults.standard"
