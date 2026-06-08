#!/usr/bin/env sh
set -eu

package_root="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(CDPATH= cd -- "$package_root/.." && pwd)"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT INT TERM

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
  mkdir -p "$fixture/apps/ios/MailApp/Backend" "$fixture/apps/ios/MailAppTests"
  cat > "$fixture/apps/ios/project.yml" <<'EOF'
targets:
  MailApp:
    type: application
    sources:
      - MailApp
  MailAppTests:
    type: bundle.unit-test
    sources:
      - MailAppTests
    dependencies:
      - target: MailApp
EOF
  printf '%s\n' "$fixture"
}

passing_fixture="$(new_fixture passing)"
cat > "$passing_fixture/apps/ios/MailApp/Backend/HTTPMailBackendDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.http
enum HTTPMailBackendDecider {
  static func decidePath(_ shard: Int) -> String {
    shard >= 0 ? "/v1/accounts" : "/v1/accounts"
  }
}
EOF
cat > "$passing_fixture/apps/ios/MailAppTests/HTTPMailBackendDeciderTests.swift" <<'EOF'
// @archlint.module test
// @archlint.domain backend.http
import PropertyBased
import Testing
import XCTest

final class HTTPMailBackendDeciderTests: XCTestCase {
  func testPath() {
    XCTAssertEqual(HTTPMailBackendDecider.decidePath(0), "/v1/accounts")
  }
}

@Test
func pathProperty() async {
  await propertyCheck(input: Gen.int(in: 0...10)) { shard in
    #expect(HTTPMailBackendDecider.decidePath(shard) == "/v1/accounts")
  }
}
EOF
cat > "$passing_fixture/apps/ios/MailApp/Backend/HTTPMailBackendClient.swift" <<'EOF'
// @archlint.module shell
// @archlint.domain backend.http
import Foundation

final class HTTPMailBackendClient {
  func makeRequest() -> URLRequest {
    let path = HTTPMailBackendDecider.decidePath(0)
    let url = URL(string: "http://localhost" + path)!
    return URLRequest(url: url)
  }
}
EOF
cat > "$passing_fixture/apps/ios/MailApp/Backend/AddAccountRequest.swift" <<'EOF'
// @archlint.module interface
// @archlint.domain backend.http
struct AddAccountRequest: Equatable {
  let displayName: String
  let emailAddress: String
}
EOF
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
cat > "$cross_file_bare_reference_fixture/apps/ios/MailApp/Backend/HTTPMailBackendDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.http
enum HTTPMailBackendDecider {
  static func decidePath(_ shard: Int) -> String {
    shard >= 0 ? "/v1/accounts" : "/v1/accounts"
  }
}
EOF
cat > "$cross_file_bare_reference_fixture/apps/ios/MailAppTests/HTTPMailBackendDeciderTests.swift" <<'EOF'
// @archlint.module test
// @archlint.domain backend.http
import PropertyBased
import Testing

@Test
func pathProperty() async {
  await propertyCheck(input: Gen.int(in: 0...10)) { shard in
    #expect(HTTPMailBackendDecider.decidePath(shard) == "/v1/accounts")
  }
}
EOF
cat > "$cross_file_bare_reference_fixture/apps/ios/MailApp/Backend/HTTPMailBackendClient.swift" <<'EOF'
// @archlint.module shell
// @archlint.domain backend.http
import Foundation

func decidePathForRequest(_ shard: Int) -> String {
  HTTPMailBackendDecider.decidePath(shard)
}

final class HTTPMailBackendClient {
  func makeRequest() -> URLRequest {
    let path = decidePathForRequest(0)
    let url = URL(string: "http://localhost" + path)!
    return URLRequest(url: url)
  }
}
EOF
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
cat > "$missing_core_reference_fixture/apps/ios/MailApp/Backend/HTTPMailBackendDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.http
enum HTTPMailBackendDecider {
  static func decidePath(_ shard: Int) -> String {
    shard >= 0 ? "/v1/accounts" : "/v1/accounts"
  }
}
EOF
cat > "$missing_core_reference_fixture/apps/ios/MailAppTests/HTTPMailBackendDeciderTests.swift" <<'EOF'
// @archlint.module test
// @archlint.domain backend.http
import PropertyBased

func pathProperty() {
  _ = PropertyBased.self
}
EOF
cat > "$missing_core_reference_fixture/apps/ios/MailApp/Backend/HTTPMailBackendClient.swift" <<'EOF'
// @archlint.module shell
// @archlint.domain backend.http
import Foundation

final class HTTPMailBackendClient {
  func makeRequest() -> URLRequest {
    URLRequest(url: URL(string: "http://localhost")!)
  }
}
EOF
assert_fails_with "$missing_core_reference_fixture" \
  "shell module must reference a core API in the same @archlint.domain"

local_core_name_only_fixture="$(new_fixture local-core-name-only)"
cat > "$local_core_name_only_fixture/apps/ios/MailApp/Backend/HTTPMailBackendDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.http
enum HTTPMailBackendDecider {
  static func decidePath() -> String {
    "/v1/accounts"
  }
}
EOF
cat > "$local_core_name_only_fixture/apps/ios/MailAppTests/HTTPMailBackendDeciderTests.swift" <<'EOF'
// @archlint.module test
// @archlint.domain backend.http
import PropertyBased
import Testing

@Test
func pathProperty() async {
  await propertyCheck(input: Gen.int(in: 0...10)) { _ in
    #expect(HTTPMailBackendDecider.decidePath() == "/v1/accounts")
  }
}
EOF
cat > "$local_core_name_only_fixture/apps/ios/MailApp/Backend/HTTPMailBackendClient.swift" <<'EOF'
// @archlint.module shell
// @archlint.domain backend.http
struct HTTPMailBackendClient {
  func makePath() -> String {
    let decidePath = "/v1/accounts"
    return decidePath
  }
}
EOF
assert_fails_with "$local_core_name_only_fixture" \
  "shell module must reference a core API in the same @archlint.domain"

static_property_decision_surface_fixture="$(new_fixture static-property-decision-surface)"
cat > "$static_property_decision_surface_fixture/apps/ios/MailApp/Backend/SQLiteMailSyncStateDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.sqlite
enum SQLiteMailSyncStateDecider {
  static let createTablesSQL: String = "CREATE TABLE messages(id TEXT)"

  static func loadedState(_ shard: Int) -> String {
    shard >= 0 ? "loaded" : "loaded"
  }
}
EOF
cat > "$static_property_decision_surface_fixture/apps/ios/MailAppTests/SQLiteMailSyncStateDeciderTests.swift" <<'EOF'
// @archlint.module test
// @archlint.domain backend.sqlite
import PropertyBased
import Testing

@Test
func schemaProperty() async {
  await propertyCheck(input: Gen.int(in: 0...10)) { shard in
    #expect(SQLiteMailSyncStateDecider.loadedState(shard) == "loaded")
  }
}
EOF
cat > "$static_property_decision_surface_fixture/apps/ios/MailApp/Backend/SQLiteMailSyncStateSchema.swift" <<'EOF'
// @archlint.module shell
// @archlint.domain backend.sqlite
import Foundation

struct SQLiteMailSyncStateSchema {
  let request = URLRequest(url: URL(string: "http://localhost")!)
  let sql: String = SQLiteMailSyncStateDecider.createTablesSQL
}
EOF
assert_passes "$static_property_decision_surface_fixture"

closure_fixture="$(new_fixture closure)"
cat > "$closure_fixture/apps/ios/MailApp/Backend/ClosureDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.closure
enum ClosureDecider {
  static func decideA(_ shard: Int) -> Bool {
    shard >= 0
  }

  static func decideB(_ shard: Int) -> Bool {
    shard < 0
  }

  static func decideC(_ shard: Int) -> Bool {
    shard == 0
  }
}
EOF
cat > "$closure_fixture/apps/ios/MailAppTests/ClosureDeciderTests.swift" <<'EOF'
// @archlint.module test
// @archlint.domain backend.closure
import PropertyBased
import Testing

func helper(_ shard: Int) -> Bool {
  ClosureDecider.decideC(shard)
}

@Test
func closureProperty() async {
  await propertyCheck(
    input: Gen.int(in: 0...10).map { shard in
      _ = ClosureDecider.decideB(shard)
      return shard
    }
  ) { shard in
    #expect(ClosureDecider.decideA(shard) || helper(shard) || shard >= 0)
  }
}
EOF
cat > "$closure_fixture/apps/ios/MailApp/Backend/ClosureClient.swift" <<'EOF'
// @archlint.module shell
// @archlint.domain backend.closure
import Foundation

struct ClosureClient {
  func handle() -> URLRequest {
    let path = ClosureDecider.decideA(1) ? "/v1/accounts" : "/v1/accounts"
    let url = URL(string: "http://localhost" + path)!
    return URLRequest(url: url)
  }
}
EOF
assert_passes "$closure_fixture"

arbitrary_core_type_reference_fixture="$(new_fixture arbitrary-core-type-reference)"
cat > "$arbitrary_core_type_reference_fixture/apps/ios/MailApp/Backend/HTTPMailBackendDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.http
struct CoreVocabulary {}

enum HTTPMailBackendDecider {
  static func decidePath() -> String {
    "/v1/accounts"
  }
}
EOF
cat > "$arbitrary_core_type_reference_fixture/apps/ios/MailAppTests/HTTPMailBackendDeciderTests.swift" <<'EOF'
// @archlint.module test
// @archlint.domain backend.http
import PropertyBased
import Testing

@Test
func pathProperty() async {
  await propertyCheck(input: Gen.int(in: 0...10)) { _ in
    #expect(HTTPMailBackendDecider.decidePath() == "/v1/accounts")
  }
}
EOF
cat > "$arbitrary_core_type_reference_fixture/apps/ios/MailApp/Backend/HTTPMailBackendClient.swift" <<'EOF'
// @archlint.module shell
// @archlint.domain backend.http
struct HTTPMailBackendClient {
  func handle(_ value: CoreVocabulary) {
    _ = value
  }
}
EOF
assert_fails_with "$arbitrary_core_type_reference_fixture" \
  "shell module must reference a core API in the same @archlint.domain"

missing_metadata_fixture="$(new_fixture missing-metadata)"
cat > "$missing_metadata_fixture/apps/ios/MailApp/Backend/Random.swift" <<'EOF'
struct RandomValue {}
EOF
assert_fails_with "$missing_metadata_fixture" "module must declare @archlint.module"

metadata_after_source_fixture="$(new_fixture metadata-after-source)"
cat > "$metadata_after_source_fixture/apps/ios/MailApp/Backend/Random.swift" <<'EOF'
struct RandomValue {}
// @archlint.module value
// @archlint.domain random.value
EOF
assert_fails_with "$metadata_after_source_fixture" "module must declare @archlint.module"

duplicate_module_metadata_fixture="$(new_fixture duplicate-module-metadata)"
cat > "$duplicate_module_metadata_fixture/apps/ios/MailApp/Backend/Random.swift" <<'EOF'
// @archlint.module core
// @archlint.module value
// @archlint.domain random.value
struct RandomValue {}
EOF
assert_fails_with "$duplicate_module_metadata_fixture" "module must declare @archlint.module"

duplicate_domain_metadata_fixture="$(new_fixture duplicate-domain-metadata)"
cat > "$duplicate_domain_metadata_fixture/apps/ios/MailApp/Backend/Random.swift" <<'EOF'
// @archlint.module value
// @archlint.domain random.value
// @archlint.domain random.other
struct RandomValue {}
EOF
assert_fails_with "$duplicate_domain_metadata_fixture" "module must declare @archlint.domain"

duplicate_exempt_reason_metadata_fixture="$(new_fixture duplicate-exempt-reason-metadata)"
cat > "$duplicate_exempt_reason_metadata_fixture/apps/ios/MailApp/Backend/MailPrototypeData.swift" <<'EOF'
// @archlint.module exempt
// @archlint.exempt-reason static-data
// @archlint.exempt-reason test-support
enum MailPrototypeData {
  static let account = "demo"
}
EOF
assert_fails_with "$duplicate_exempt_reason_metadata_fixture" \
  "exempt module must declare @archlint.exempt-reason"

test_module_in_production_fixture="$(new_fixture test-module-in-production)"
cat > "$test_module_in_production_fixture/apps/ios/MailApp/Backend/RandomTests.swift" <<'EOF'
// @archlint.module test
// @archlint.domain random.value
struct RandomTests {}
EOF
assert_fails_with "$test_module_in_production_fixture" \
  "test module must be declared in a test scope"

malformed_domain_fixture="$(new_fixture malformed-domain)"
cat > "$malformed_domain_fixture/apps/ios/MailApp/Backend/RandomDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain Backend_HTTP
enum RandomDecider {
  static func decide() -> Bool {
    true
  }
}
EOF
assert_fails_with "$malformed_domain_fixture" \
  "module domain must be lowercase dot-or-kebab segments"

production_module_in_test_fixture="$(new_fixture production-module-in-test)"
cat > "$production_module_in_test_fixture/apps/ios/MailAppTests/RandomDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain random.value
enum RandomDecider {
  static func decide() -> Bool {
    true
  }
}
EOF
assert_fails_with "$production_module_in_test_fixture" \
  "production module must not be declared in a test scope"

missing_exempt_reason_fixture="$(new_fixture missing-exempt-reason)"
cat > "$missing_exempt_reason_fixture/apps/ios/MailApp/Backend/InstallationCredential.swift" <<'EOF'
// @archlint.module exempt
struct InstallationCredential {
  let accessToken: String?
}
EOF
assert_fails_with "$missing_exempt_reason_fixture" \
  "exempt module must declare @archlint.exempt-reason"

exempt_domain_fixture="$(new_fixture exempt-domain)"
cat > "$exempt_domain_fixture/apps/ios/MailApp/Backend/MailPrototypeData.swift" <<'EOF'
// @archlint.module exempt
// @archlint.domain mail.sync
// @archlint.exempt-reason static-data
enum MailPrototypeData {
  static let account = "demo"
}
EOF
assert_fails_with "$exempt_domain_fixture" \
  "exempt module must not declare @archlint.domain"

unknown_exempt_reason_fixture="$(new_fixture unknown-exempt-reason)"
cat > "$unknown_exempt_reason_fixture/apps/ios/MailApp/Backend/InstallationCredential.swift" <<'EOF'
// @archlint.module exempt
// @archlint.exempt-reason miscellaneous
struct InstallationCredential {
  let accessToken: String?
}
EOF
assert_fails_with "$unknown_exempt_reason_fixture" "metadata.exemptReason"

exempt_reason_outside_exempt_fixture="$(new_fixture exempt-reason-outside-exempt)"
cat > "$exempt_reason_outside_exempt_fixture/apps/ios/MailApp/Backend/AddAccountRequest.swift" <<'EOF'
// @archlint.module interface
// @archlint.domain backend.http
// @archlint.exempt-reason static-data
struct AddAccountRequest {
  let displayName: String
}
EOF
assert_fails_with "$exempt_reason_outside_exempt_fixture" \
  "@archlint.exempt-reason is only valid on exempt modules"

entrypoint_exemption_fixture="$(new_fixture entrypoint-exemption)"
mkdir -p "$entrypoint_exemption_fixture/apps/ios/MailApp/App"
cat > "$entrypoint_exemption_fixture/apps/ios/MailApp/App/MailApp.swift" <<'EOF'
// @archlint.module exempt
// @archlint.exempt-reason entrypoint
import SwiftUI

@main
struct MailApp: App {
  var body: some Scene {
    WindowGroup {
      Text("Mail")
    }
  }
}
EOF
assert_passes "$entrypoint_exemption_fixture"

pure_glue_exemption_fixture="$(new_fixture pure-glue-exemption)"
mkdir -p "$pure_glue_exemption_fixture/apps/ios/MailApp/Features/Mailboxes"
cat > "$pure_glue_exemption_fixture/apps/ios/MailApp/Features/Mailboxes/MailboxRoute.swift" <<'EOF'
// @archlint.module exempt
// @archlint.exempt-reason pure-glue

struct MailboxRoute {
  let accountID: String
  let mailboxID: String
}
EOF
assert_passes "$pure_glue_exemption_fixture"

effect_boundary_exemption_fixture="$(new_fixture effect-boundary-exemption)"
cat > "$effect_boundary_exemption_fixture/apps/ios/MailApp/Backend/SystemKeychainClient.swift" <<'EOF'
// @archlint.module exempt
// @archlint.exempt-reason effect-boundary
import Security

struct SystemKeychainClient {
  let keychainClass: CFString
}
EOF
assert_passes "$effect_boundary_exemption_fixture"

effect_facade_exemption_fixture="$(new_fixture effect-facade-exemption)"
cat > "$effect_facade_exemption_fixture/apps/ios/MailApp/Backend/MailBackendClient.swift" <<'EOF'
// @archlint.module exempt
// @archlint.exempt-reason effect-facade
protocol MailBackendClient {
  func sync() async throws
}
EOF
assert_passes "$effect_facade_exemption_fixture"

static_data_exemption_fixture="$(new_fixture static-data-exemption)"
mkdir -p "$static_data_exemption_fixture/apps/ios/MailApp/Domain"
cat > "$static_data_exemption_fixture/apps/ios/MailApp/Domain/MailStaticData.swift" <<'EOF'
// @archlint.module exempt
// @archlint.exempt-reason static-data
enum MailStaticData {
  static let account = "demo"
}
EOF
assert_passes "$static_data_exemption_fixture"

test_support_exemption_fixture="$(new_fixture test-support-exemption)"
cat > "$test_support_exemption_fixture/apps/ios/MailAppTests/FailingMailSyncStateStore.swift" <<'EOF'
// @archlint.module exempt
// @archlint.exempt-reason test-support
struct FailingMailSyncStateStore {
  let reason: String
}
EOF
assert_passes "$test_support_exemption_fixture"

generic_domain_fixture="$(new_fixture generic-domain)"
for index in $(seq 1 17); do
  cat > "$generic_domain_fixture/apps/ios/MailApp/Backend/BroadDomainDecision$index.swift" <<EOF
// @archlint.module core
// @archlint.domain overbroad.example
func decideBroadDomain$index() -> Bool {
  true
}
EOF
done
assert_fails_with "$generic_domain_fixture" \
  "domain has 17 production modules; maximum is 16"

interface_generic_domain_fixture="$(new_fixture interface-generic-domain)"
for index in $(seq 1 17); do
  cat > "$interface_generic_domain_fixture/apps/ios/MailApp/Backend/BroadDomain$index.swift" <<EOF
// @archlint.module interface
// @archlint.domain overbroad.example
struct BroadDomain$index {
  let value: String
}
EOF
done
assert_passes "$interface_generic_domain_fixture"

interface_with_logic_fixture="$(new_fixture interface-with-logic)"
cat > "$interface_with_logic_fixture/apps/ios/MailApp/Backend/AddAccountRequest.swift" <<'EOF'
// @archlint.module interface
// @archlint.domain backend.http
struct AddAccountRequest {
  let displayName: String

  var normalizedDisplayName: String {
    displayName.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
EOF
assert_fails_with "$interface_with_logic_fixture" \
  "interface module must not contain derived value bodies"

value_with_computed_property_fixture="$(new_fixture value-with-computed-property)"
cat > "$value_with_computed_property_fixture/apps/ios/MailApp/Backend/AddAccountRequest.swift" <<'EOF'
// @archlint.module value
// @archlint.domain backend.http
struct AddAccountRequest {
  let displayName: String

  var normalizedDisplayName: String {
    displayName.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
EOF
assert_passes "$value_with_computed_property_fixture"

value_with_branching_computed_property_fixture="$(new_fixture value-with-branching-computed-property)"
cat > "$value_with_branching_computed_property_fixture/apps/ios/MailApp/Backend/AddAccountRequest.swift" <<'EOF'
// @archlint.module value
// @archlint.domain backend.http
struct AddAccountRequest {
  let displayName: String

  var normalizedDisplayName: String {
    if displayName.isEmpty {
      return "Mailbox"
    }
    return displayName
  }
}
EOF
assert_fails_with "$value_with_branching_computed_property_fixture" \
  "value module must not contain control flow"

value_with_callable_decision_fixture="$(new_fixture value-with-callable-decision)"
cat > "$value_with_callable_decision_fixture/apps/ios/MailApp/Backend/AddAccountRequest.swift" <<'EOF'
// @archlint.module value
// @archlint.domain backend.http
struct AddAccountRequest {
  let displayName: String

  func normalizedDisplayName() -> String {
    displayName.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
EOF
assert_fails_with "$value_with_callable_decision_fixture" \
  "value module must not contain function bodies"

core_enum_case_matching_shell_method_fixture="$(new_fixture core-enum-case-matching-shell-method)"
cat > "$core_enum_case_matching_shell_method_fixture/apps/ios/MailApp/Backend/HTTPMailBackendDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.http
enum HTTPMailBackendDecider {
  enum Decision {
    case add
  }

  static func decide(_ shard: Int) -> Decision {
    shard >= 0 ? .add : .add
  }
}
EOF
cat > "$core_enum_case_matching_shell_method_fixture/apps/ios/MailAppTests/HTTPMailBackendDeciderTests.swift" <<'EOF'
// @archlint.module test
// @archlint.domain backend.http
import PropertyBased
import Testing

@Test
func decisionProperty() async {
  await propertyCheck(input: Gen.int(in: 0...10)) { shard in
    #expect(HTTPMailBackendDecider.decide(shard) == .add)
  }
}
EOF
cat > "$core_enum_case_matching_shell_method_fixture/apps/ios/MailApp/Backend/HTTPMailBackendClient.swift" <<'EOF'
// @archlint.module shell
// @archlint.domain backend.http
import Foundation

struct HTTPMailBackendClient {
  func add() -> URLRequest {
    _ = HTTPMailBackendDecider.decide(0)
    return URLRequest(url: URL(string: "http://localhost")!)
  }
}
EOF
assert_passes "$core_enum_case_matching_shell_method_fixture"

empty_decider_fixture="$(new_fixture empty-decider)"
cat > "$empty_decider_fixture/apps/ios/MailApp/Backend/SQLiteMailSyncStateDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.http
enum SQLiteMailSyncStateDecider {}
EOF
assert_fails_with "$empty_decider_fixture" \
  "core module must declare a callable decision API"
assert_fails_with "$empty_decider_fixture" \
  "core module must have a same-domain test or stateTest module"

type_only_decider_fixture="$(new_fixture type-only-decider)"
cat > "$type_only_decider_fixture/apps/ios/MailApp/Backend/SQLiteMailSyncStateDecision.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.http
struct SQLiteMailSyncStateDecision {}
EOF
assert_fails_with "$type_only_decider_fixture" \
  "core module must declare a callable decision API"

effectful_decider_fixture="$(new_fixture effectful-decider)"
cat > "$effectful_decider_fixture/apps/ios/MailApp/Backend/SQLiteMailSyncStateDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.http
import Foundation

enum SQLiteMailSyncStateDecider {
  static func decideRequest() -> URLRequest {
    URLRequest(url: URL(string: "http://localhost")!)
  }
}
EOF
assert_fails_with "$effectful_decider_fixture" \
  "effectful identifiers may only appear in shell, state, interface, test, stateTest, or exempt modules"
assert_fails_with "$effectful_decider_fixture" \
  "core module must have a same-domain test or stateTest module"

missing_property_fixture="$(new_fixture missing-property)"
cat > "$missing_property_fixture/apps/ios/MailApp/Backend/HTTPMailBackendDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.http
enum HTTPMailBackendDecider {
  static func decidePath() -> String {
    "/v1/accounts"
  }
}
EOF
cat > "$missing_property_fixture/apps/ios/MailAppTests/HTTPMailBackendDeciderTests.swift" <<'EOF'
// @archlint.module test
// @archlint.domain backend.http
import XCTest

final class HTTPMailBackendDeciderTests: XCTestCase {
  func testPath() {
    XCTAssertEqual(HTTPMailBackendDecider.decidePath(), "/v1/accounts")
  }
}
EOF
assert_fails_with "$missing_property_fixture" \
  "core module test must contain at least one property test"

property_import_only_fixture="$(new_fixture property-import-only)"
cat > "$property_import_only_fixture/apps/ios/MailApp/Backend/HTTPMailBackendDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.http
enum HTTPMailBackendDecider {
  static func decidePath() -> String {
    "/v1/accounts"
  }
}
EOF
cat > "$property_import_only_fixture/apps/ios/MailAppTests/HTTPMailBackendDeciderPropertySuite.swift" <<'EOF'
// @archlint.module test
// @archlint.domain backend.http
import PropertyBased
import XCTest

enum HTTPMailBackendDeciderPropertySuite {
  static func testPath() {
    _ = PropertyBased.self
  }
}
EOF
assert_fails_with "$property_import_only_fixture" \
  "core module test must contain at least one property test"

property_name_only_fixture="$(new_fixture property-name-only)"
cat > "$property_name_only_fixture/apps/ios/MailApp/Backend/HTTPMailBackendDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.http
enum HTTPMailBackendDecider {
  static func decidePath() -> String {
    "/v1/accounts"
  }
}
EOF
cat > "$property_name_only_fixture/apps/ios/MailAppTests/HTTPMailBackendDeciderTests.swift" <<'EOF'
// @archlint.module test
// @archlint.domain backend.http
import Testing

@Test
func pathProperty() {
  #expect(HTTPMailBackendDecider.decidePath() == "/v1/accounts")
}
EOF
assert_fails_with "$property_name_only_fixture" \
  "core module test must contain at least one property test"

unrelated_property_test_fixture="$(new_fixture unrelated-property-test)"
cat > "$unrelated_property_test_fixture/apps/ios/MailApp/Backend/HTTPMailBackendDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.http
enum HTTPMailBackendDecider {
  static func decidePath() -> String {
    "/v1/accounts"
  }
}
EOF
cat > "$unrelated_property_test_fixture/apps/ios/MailAppTests/HTTPMailBackendDeciderPropertySuite.swift" <<'EOF'
// @archlint.module test
// @archlint.domain backend.http
import PropertyBased
import Testing

enum HTTPMailBackendDeciderPropertySuite {
  @Test
  static func unrelatedProperty() async {
    await propertyCheck(input: Gen.int(in: 0...10)) { value in
      #expect(value == value)
    }
  }
}
EOF
assert_fails_with "$unrelated_property_test_fixture" \
  "core module property tests must reference every decision API: decidePath"

property_local_core_name_only_fixture="$(new_fixture property-local-core-name-only)"
cat > "$property_local_core_name_only_fixture/apps/ios/MailApp/Backend/HTTPMailBackendDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.http
enum HTTPMailBackendDecider {
  static func decidePath() -> String {
    "/v1/accounts"
  }
}
EOF
cat > "$property_local_core_name_only_fixture/apps/ios/MailAppTests/HTTPMailBackendDeciderPropertySuite.swift" <<'EOF'
// @archlint.module test
// @archlint.domain backend.http
import PropertyBased
import Testing

enum HTTPMailBackendDeciderPropertySuite {
  @Test
  static func pathProperty() async {
    await propertyCheck(input: Gen.int(in: 0...10)) { value in
      let decidePath = value
      #expect(decidePath == value)
    }
  }
}
EOF
assert_fails_with "$property_local_core_name_only_fixture" \
  "core module property tests must reference every decision API: decidePath"

property_reachable_helper_fixture="$(new_fixture property-reachable-helper)"
cat > "$property_reachable_helper_fixture/apps/ios/MailApp/Backend/HTTPMailBackendDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.http
enum HTTPMailBackendDecider {
  static func decidePath() -> String {
    "/v1/accounts"
  }
}
EOF
cat > "$property_reachable_helper_fixture/apps/ios/MailAppTests/HTTPMailBackendDeciderPropertySuite.swift" <<'EOF'
// @archlint.module test
// @archlint.domain backend.http
import PropertyBased
import Testing

enum HTTPMailBackendDeciderPropertySuite {
  @Test
  static func pathProperty() async {
    await propertyCheck(input: Gen.int(in: 0...10)) { shard in
      #expect(helperPath(shard) == "/v1/accounts")
    }
  }

  static func helperPath(_ shard: Int) -> String {
    HTTPMailBackendDecider.decidePath(shard)
  }
}
EOF
assert_passes "$property_reachable_helper_fixture"
assert_fact_refs_contain \
  "$property_reachable_helper_fixture" \
  "HTTPMailBackendDeciderPropertySuite.swift" \
  "propertyTestReferences" \
  "decidePath"

ordinary_array_property_fixture="$(new_fixture ordinary-array-property)"
cat > "$ordinary_array_property_fixture/apps/ios/MailApp/Backend/HTTPMailBackendDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.http
enum HTTPMailBackendDecider {
  static func decode(_ values: [Int]) -> Int {
    values.count
  }
}
EOF
cat > "$ordinary_array_property_fixture/apps/ios/MailAppTests/HTTPMailBackendDeciderPropertySuite.swift" <<'EOF'
// @archlint.module test
// @archlint.domain backend.http
import PropertyBased
import Testing

enum HTTPMailBackendDeciderPropertySuite {
  @Test
  static func decodeAcceptsGeneratedArraysProperty() async {
    await propertyCheck(input: Gen.int(in: 0...10).array(of: 0...20)) { values in
      #expect(HTTPMailBackendDecider.decode(values) == values.count)
    }
  }
}
EOF
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
cat > "$property_unreachable_helper_fixture/apps/ios/MailApp/Backend/HTTPMailBackendDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.http
enum HTTPMailBackendDecider {
  static func decidePath() -> String {
    "/v1/accounts"
  }
}
EOF
cat > "$property_unreachable_helper_fixture/apps/ios/MailAppTests/HTTPMailBackendDeciderPropertySuite.swift" <<'EOF'
// @archlint.module test
// @archlint.domain backend.http
import PropertyBased
import Testing

enum HTTPMailBackendDeciderPropertySuite {
  @Test
  static func pathProperty() async {
    await propertyCheck(input: Gen.int(in: 0...10)) { value in
      #expect(value == value)
    }
  }

  static func helperPath() -> String {
    HTTPMailBackendDecider.decidePath()
  }
}
EOF
assert_fails_with "$property_unreachable_helper_fixture" \
  "core module property tests must reference every decision API: decidePath"

wrong_domain_test_fixture="$(new_fixture wrong-domain-test)"
cat > "$wrong_domain_test_fixture/apps/ios/MailApp/Backend/HTTPMailBackendDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.http
enum HTTPMailBackendDecider {
  static func decidePath() -> String {
    "/v1/accounts"
  }
}
EOF
cat > "$wrong_domain_test_fixture/apps/ios/MailAppTests/HTTPMailBackendDeciderTests.swift" <<'EOF'
// @archlint.module test
// @archlint.domain mail.sync
import PropertyBased

func pathProperty() {
  _ = PropertyBased.self
}
EOF
assert_fails_with "$wrong_domain_test_fixture" \
  "core module must have a same-domain test or stateTest module"

wrong_test_module_type_fixture="$(new_fixture wrong-test-module-type)"
cat > "$wrong_test_module_type_fixture/apps/ios/MailApp/Backend/HTTPMailBackendDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.http
enum HTTPMailBackendDecider {
  static func decidePath() -> String {
    "/v1/accounts"
  }
}
EOF
cat > "$wrong_test_module_type_fixture/apps/ios/MailAppTests/HTTPMailBackendDeciderTests.swift" <<'EOF'
// @archlint.module interface
// @archlint.domain backend.http
import PropertyBased

func pathProperty() {
  _ = PropertyBased.self
}
EOF
assert_fails_with "$wrong_test_module_type_fixture" \
  "core module must have a same-domain test or stateTest module"

non_decider_core_fixture="$(new_fixture non-decider-core)"
cat > "$non_decider_core_fixture/apps/ios/MailApp/Backend/HTTPMailBackendCore.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.http
enum HTTPMailBackendCore {
  static func decidePath() -> String {
    "/v1/accounts"
  }
}
EOF
assert_fails_with "$non_decider_core_fixture" \
  "core module must have a same-domain test or stateTest module"

state_test_without_operation_sequences_fixture="$(new_fixture state-test-without-operation-sequences)"
cat > "$state_test_without_operation_sequences_fixture/apps/ios/MailAppTests/SQLiteMailSyncStateDeciderPropertySuite.swift" <<'EOF'
// @archlint.module stateTest
// @archlint.domain backend.sqlite
import PropertyBased
import Testing

enum SQLiteMailSyncStateDeciderPropertySuite {
  @Test
  static func roundTripOperationSequencesProperty() async {
    await propertyCheck(input: Gen.int(in: 0...10)) { value in
      #expect(value == value)
    }
  }
}
EOF
assert_fails_with "$state_test_without_operation_sequences_fixture" \
  "stateTest module must contain property operation sequences"

state_test_operation_sequences_without_refs_fixture="$(new_fixture state-test-operation-sequences-without-refs)"
cat > "$state_test_operation_sequences_without_refs_fixture/apps/ios/MailAppTests/SQLiteMailSyncStateDeciderPropertySuite.swift" <<'EOF'
// @archlint.module stateTest
// @archlint.domain backend.sqlite
import PropertyBased
import Testing

enum SQLiteMailSyncStateDeciderPropertySuite {
  @Test
  static func roundTripOperationSequencesProperty() async {
    await propertyCheck(input: Gen.int(in: 0...10).array(of: 0...20)) { values in
      for value in values {
        #expect(value == value)
      }
    }
  }
}
EOF
assert_fails_with "$state_test_operation_sequences_without_refs_fixture" \
  "stateTest module must contain property operation sequences"

state_test_operation_sequences_without_core_refs_fixture="$(new_fixture state-test-operation-sequences-without-core-refs)"
cat > "$state_test_operation_sequences_without_core_refs_fixture/apps/ios/MailApp/Backend/SQLiteMailSyncStateDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.sqlite
enum SQLiteMailSyncStateDecider {
  static func reduce(_ value: Int) -> Int {
    value
  }
}
EOF
cat > "$state_test_operation_sequences_without_core_refs_fixture/apps/ios/MailAppTests/SQLiteMailSyncStateDeciderPropertySuite.swift" <<'EOF'
// @archlint.module stateTest
// @archlint.domain backend.sqlite
import PropertyBased
import Testing

enum SQLiteMailSyncStateDeciderPropertySuite {
  @Test
  static func reduceProperty() async {
    await propertyCheck(input: Gen.int(in: 0...10)) { value in
      #expect(SQLiteMailSyncStateDecider.reduce(value) == value)
    }
  }

  @Test
  static func unrelatedOperationSequencesProperty() async {
    await propertyCheck(input: Gen.int(in: 0...10).array(of: 0...20)) { values in
      for value in values {
        #expect(helper(value) == value)
      }
    }
  }

  static func helper(_ value: Int) -> Int {
    value
  }
}
EOF
assert_fails_with "$state_test_operation_sequences_without_core_refs_fixture" \
  "stateTest module operation sequences must reference same-domain core decision APIs"

state_test_without_state_module_fixture="$(new_fixture state-test-without-state-module)"
cat > "$state_test_without_state_module_fixture/apps/ios/MailApp/Backend/SQLiteMailSyncStateDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.sqlite
enum SQLiteMailSyncStateDecider {
  static func reduce(_ value: Int) -> Int {
    value
  }
}
EOF
cat > "$state_test_without_state_module_fixture/apps/ios/MailAppTests/SQLiteMailSyncStateDeciderPropertySuite.swift" <<'EOF'
// @archlint.module stateTest
// @archlint.domain backend.sqlite
import PropertyBased
import Testing

enum SQLiteMailSyncStateDeciderPropertySuite {
  @Test
  static func reduceOperationSequencesProperty() async {
    await propertyCheck(input: Gen.int(in: 0...10).array(of: 0...20)) { values in
      for value in values {
        #expect(SQLiteMailSyncStateDecider.reduce(value) == value)
      }
    }
  }
}
EOF
assert_fails_with "$state_test_without_state_module_fixture" \
  "stateTest module must have a same-domain state module"

state_test_operation_sequence_refs_fixture="$(new_fixture state-test-operation-sequence-refs)"
cat > "$state_test_operation_sequence_refs_fixture/apps/ios/MailAppTests/SQLiteMailSyncStateDeciderPropertySuite.swift" <<'EOF'
// @archlint.module stateTest
// @archlint.domain backend.sqlite
import PropertyBased
import Testing

enum SQLiteMailSyncStateDeciderPropertySuite {
  @Test
  static func roundTripOperationSequencesProperty() async {
    await propertyCheck(input: Gen.int(in: 0...10).array(of: 0...20)) { values in
      for value in values {
        #expect(helper(value) == value)
      }
    }
  }

  static func helper(_ value: Int) -> Int {
    SQLiteMailSyncStateDecider.reduce(value)
  }
}
EOF
assert_fact_refs_contain \
  "$state_test_operation_sequence_refs_fixture" \
  "SQLiteMailSyncStateDeciderPropertySuite.swift" \
  "propertyOperationSequenceReferences" \
  "reduce"

state_unrelated_to_operation_sequences_fixture="$(new_fixture state-unrelated-to-operation-sequences)"
cat > "$state_unrelated_to_operation_sequences_fixture/apps/ios/MailApp/Backend/FakeMailBackendClient.swift" <<'EOF'
// @archlint.module state
// @archlint.domain backend.http
import Foundation

actor FakeMailBackendClient {
  private var accounts: [String] = []

  func add(_ account: String) {
    accounts.append(account)
  }
}
EOF
cat > "$state_unrelated_to_operation_sequences_fixture/apps/ios/MailAppTests/HTTPMailBackendStatePropertySuite.swift" <<'EOF'
// @archlint.module stateTest
// @archlint.domain backend.http
import PropertyBased
import Testing

enum HTTPMailBackendStatePropertySuite {
  @Test
  static func unrelatedOperationSequencesProperty() async {
    await propertyCheck(input: Gen.int(in: 0...10).array(of: 0...20)) { values in
      for value in values {
        #expect(OtherDecider.reduce(value) == value)
      }
    }
  }
}
EOF
assert_fails_with "$state_unrelated_to_operation_sequences_fixture" \
  "state module must reference a core decision API reached by same-domain property operation sequences"

state_without_stateful_apis_fixture="$(new_fixture state-without-stateful-apis)"
cat > "$state_without_stateful_apis_fixture/apps/ios/MailApp/Backend/SQLiteMailSyncStateDecider.swift" <<'EOF'
// @archlint.module core
// @archlint.domain backend.sqlite
enum SQLiteMailSyncStateDecider {
  static func reduce(_ value: Int) -> Int {
    value
  }
}
EOF
cat > "$state_without_stateful_apis_fixture/apps/ios/MailApp/Backend/SQLiteMailSyncStateStore.swift" <<'EOF'
// @archlint.module state
// @archlint.domain backend.sqlite
struct SQLiteMailSyncStateStore {
  func snapshot(_ value: Int) -> Int {
    SQLiteMailSyncStateDecider.reduce(value)
  }
}
EOF
cat > "$state_without_stateful_apis_fixture/apps/ios/MailAppTests/SQLiteMailSyncStateDeciderPropertySuite.swift" <<'EOF'
// @archlint.module stateTest
// @archlint.domain backend.sqlite
import PropertyBased
import Testing

enum SQLiteMailSyncStateDeciderPropertySuite {
  @Test
  static func reduceOperationSequencesProperty() async {
    await propertyCheck(input: Gen.int(in: 0...10).array(of: 0...20)) { values in
      for value in values {
        #expect(SQLiteMailSyncStateDecider.reduce(value) == value)
      }
    }
  }
}
EOF
assert_fails_with "$state_without_stateful_apis_fixture" \
  "state module must own stateful APIs"

shared_state_without_state_test_fixture="$(new_fixture shared-state-without-state-test)"
cat > "$shared_state_without_state_test_fixture/apps/ios/MailApp/Backend/FakeMailBackendClient.swift" <<'EOF'
// @archlint.module state
// @archlint.domain backend.http
import Foundation

actor FakeMailBackendClient {
  private var accounts: [String] = []

  func add(_ account: String) {
    accounts.append(account)
  }
}
EOF
assert_fails_with "$shared_state_without_state_test_fixture" \
  "state module must have a same-domain stateTest with property operation sequences"

shared_state_outside_state_fixture="$(new_fixture shared-state-outside-state)"
cat > "$shared_state_outside_state_fixture/apps/ios/MailApp/Backend/FakeMailBackendClient.swift" <<'EOF'
// @archlint.module shell
// @archlint.domain backend.http
import Foundation

actor FakeMailBackendClient {
  private var accounts: [String] = []

  func add(_ account: String) {
    accounts.append(account)
  }
}
EOF
assert_fails_with "$shared_state_outside_state_fixture" \
  "shared mutable state may only appear in state, test, or stateTest modules"
assert_shared_state_contains "$shared_state_outside_state_fixture" \
  "FakeMailBackendClient.swift" "swift-actor-var" "FakeMailBackendClient"

shared_state_comment_only_fixture="$(new_fixture shared-state-comment-only)"
cat > "$shared_state_comment_only_fixture/apps/ios/MailApp/Backend/FakeMailBackendClient.swift" <<'EOF'
// @archlint.module interface
// @archlint.domain backend.http
// actor CommentOnly { private var accounts: [String] = [] }
// @Published var commentOnly: String = ""
// DatabaseQueue and UserDefaults.standard are mentioned in prose only.

struct FakeMailBackendClient {
  let endpoint: String
}
EOF
assert_passes "$shared_state_comment_only_fixture"

published_state_outside_state_fixture="$(new_fixture published-state-outside-state)"
cat > "$published_state_outside_state_fixture/apps/ios/MailApp/Backend/FakeMailBackendClient.swift" <<'EOF'
// @archlint.module shell
// @archlint.domain backend.http
import Combine

final class FakeMailBackendClient {
  @Published var accounts: [String] = []
}
EOF
assert_fails_with "$published_state_outside_state_fixture" \
  "shared mutable state may only appear in state, test, or stateTest modules"
assert_shared_state_contains "$published_state_outside_state_fixture" \
  "FakeMailBackendClient.swift" "swift-published" "@Published"

database_queue_state_outside_state_fixture="$(new_fixture database-queue-state-outside-state)"
cat > "$database_queue_state_outside_state_fixture/apps/ios/MailApp/Backend/FakeMailBackendClient.swift" <<'EOF'
// @archlint.module shell
// @archlint.domain backend.http
import GRDB

struct FakeMailBackendClient {
  let database: DatabaseQueue
}
EOF
assert_fails_with "$database_queue_state_outside_state_fixture" \
  "shared mutable state may only appear in state, test, or stateTest modules"
assert_shared_state_contains "$database_queue_state_outside_state_fixture" \
  "FakeMailBackendClient.swift" "swift-database-queue" "DatabaseQueue"

user_defaults_state_outside_state_fixture="$(new_fixture user-defaults-state-outside-state)"
cat > "$user_defaults_state_outside_state_fixture/apps/ios/MailApp/Backend/FakeMailBackendClient.swift" <<'EOF'
// @archlint.module shell
// @archlint.domain backend.http
import Foundation

struct FakeMailBackendClient {
  func load() -> String {
    UserDefaults.standard.string(forKey: "lastAccount") ?? ""
  }
}
EOF
assert_fails_with "$user_defaults_state_outside_state_fixture" \
  "shared mutable state may only appear in state, test, or stateTest modules"
assert_shared_state_contains "$user_defaults_state_outside_state_fixture" \
  "FakeMailBackendClient.swift" "swift-user-defaults" "UserDefaults.standard"
