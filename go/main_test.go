package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func lintBackendArchitecture(repoRoot string) []violation {
	command := exec.Command(
		"uv",
		"run",
		"--project",
		"..",
		"python",
		"../evaluate.py",
		"--repo-root",
		repoRoot,
		"--adapter",
		"go",
		"--go-module",
		"apps/backend",
		"--go-packages",
		"./internal/...",
	)
	output, err := command.CombinedOutput()
	if err == nil {
		return nil
	}
	return parseViolationOutput(string(output))
}

func parseViolationOutput(output string) []violation {
	var violations []violation
	for _, line := range strings.Split(output, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		path, message, ok := strings.Cut(line, ": ")
		if !ok {
			violations = append(violations, violation{path: "", message: line})
			continue
		}
		violations = append(violations, violation{path: path, message: message})
	}
	return violations
}

func TestLintBackendArchitectureAcceptsHandlerWithDecisionModule(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/auth/auth_decision.go": `// @archlint.module core
// @archlint.domain auth
package auth

func DecideTokenClaims(subject string) bool {
	return subject != ""
}
`,
		"internal/auth/auth_decision_test.go": `// @archlint.module test
// @archlint.domain auth
package auth

import (
	"testing"
	"testing/quick"
)

func TestDecideTokenClaimsProperty(t *testing.T) {
	property := func(subject string) bool {
		return DecideTokenClaims(subject) == (subject != "")
	}
	if err := quick.Check(property, nil); err != nil {
		t.Fatal(err)
	}
}
`,
		"internal/auth/service.go": `// @archlint.module shell
// @archlint.domain auth
package auth

import "net/http"

func Handle() string {
	if DecideTokenClaims(http.MethodGet) {
		return http.MethodGet
	}
	return ""
}
`,
	})

	assertNoViolations(t, lintBackendArchitecture(backendRoot))
}

func TestLintBackendArchitectureRejectsHandlerWithoutDecisionReference(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/httpapi/http_decision.go": `// @archlint.module core
// @archlint.domain http-api
package httpapi

func DecideRoute() bool {
	return true
}
`,
		"internal/httpapi/http_decision_test.go": `// @archlint.module test
// @archlint.domain http-api
package httpapi

import (
	"testing"
	"testing/quick"
)

func TestDecideRouteProperty(t *testing.T) {
	property := func(input bool) bool {
		return DecideRoute() == true || input
	}
	if err := quick.Check(property, nil); err != nil {
		t.Fatal(err)
	}
}
`,
		"internal/httpapi/router.go": `// @archlint.module shell
// @archlint.domain http-api
package httpapi

import "net/http"

func Route() string {
	return http.MethodGet
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"shell module must reference a core API in the same @archlint.domain",
	})
}

func TestLintBackendArchitectureRejectsHandlerWithOnlyDecisionNamedLocal(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/httpapi/http_decision.go": `// @archlint.module core
// @archlint.domain http-api
package httpapi

func DecideRoute() bool {
	return true
}
`,
		"internal/httpapi/http_decision_test.go": `// @archlint.module test
// @archlint.domain http-api
package httpapi

import (
	"testing"
	"testing/quick"
)

func TestDecideRouteProperty(t *testing.T) {
	property := func(input bool) bool {
		return DecideRoute() == true || input
	}
	if err := quick.Check(property, nil); err != nil {
		t.Fatal(err)
	}
}
`,
		"internal/httpapi/router.go": `// @archlint.module shell
// @archlint.domain http-api
package httpapi

import "net/http"

func Route() string {
	DecideRoute := http.MethodGet
	return DecideRoute
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"shell module must reference a core API in the same @archlint.domain",
	})
}

func TestLintBackendArchitectureRejectsHandlerWithOnlyArbitraryCoreTypeReference(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/httpapi/http_decision.go": `// @archlint.module core
// @archlint.domain http-api
package httpapi

type CoreVocabulary struct{}

func DecideRoute() bool {
	return true
}
`,
		"internal/httpapi/http_decision_test.go": `// @archlint.module test
// @archlint.domain http-api
package httpapi

import (
	"testing"
	"testing/quick"
)

func TestDecideRouteProperty(t *testing.T) {
	property := func(input bool) bool {
		return DecideRoute() == true || input
	}
	if err := quick.Check(property, nil); err != nil {
		t.Fatal(err)
	}
}
`,
		"internal/httpapi/router.go": `// @archlint.module shell
// @archlint.domain http-api
package httpapi

func Route(_ CoreVocabulary) string {
	return ""
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"shell module must reference a core API in the same @archlint.domain",
	})
}

func TestLintBackendArchitectureAcceptsHandlerWithCoreDecisionProductReference(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/httpapi/http_decision.go": `// @archlint.module core
// @archlint.domain http-api
package httpapi

type RoutePlan struct{}

func DecideRoute() RoutePlan {
	return RoutePlan{}
}
`,
		"internal/httpapi/http_decision_test.go": `// @archlint.module test
// @archlint.domain http-api
package httpapi

import (
	"testing"
	"testing/quick"
)

func TestDecideRouteProperty(t *testing.T) {
	property := func(input bool) bool {
		_ = DecideRoute()
		return input == input
	}
	if err := quick.Check(property, nil); err != nil {
		t.Fatal(err)
	}
}
`,
		"internal/httpapi/router.go": `// @archlint.module shell
// @archlint.domain http-api
package httpapi

import "net/http"

func Route(_ RoutePlan) string {
	return http.MethodGet
}
`,
	})

	assertNoViolations(t, lintBackendArchitecture(backendRoot))
}

func TestLintBackendArchitectureRejectsEffectfulCodeOutsideHandlerShape(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/random.go": `// @archlint.module core
// @archlint.domain mail
package mail

import "net/http"

func Method() string {
	return http.MethodGet
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"core module must not import effectful dependencies",
		"effectful identifiers may only appear in shell, state, interface, test, stateTest, or exempt modules",
	})
}

func TestLintBackendArchitectureAcceptsDeclarativeInterfaceModule(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/types.go": `// @archlint.module interface
// @archlint.domain mail
package mail

import "context"

type State struct{}

type StateStore interface {
	LoadState(ctx context.Context, key string) (State, bool, error)
}
`,
	})

	assertNoViolations(t, lintBackendArchitecture(backendRoot))
}

func TestLintBackendArchitectureAcceptsValueModule(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/value.go": `// @archlint.module value
// @archlint.domain mail
package mail

type Message struct {
	ID string
}
`,
	})

	assertNoViolations(t, lintBackendArchitecture(backendRoot))
}

func TestLintBackendArchitectureRejectsValueModuleWithCallableDecision(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/value.go": `// @archlint.module value
// @archlint.domain mail
package mail

type Message struct {
	ID string
}

func DecideMessageID(message Message) string {
	return message.ID
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"value module must not contain function bodies",
	})
}

func TestLintBackendArchitectureRejectsInterfaceModuleWithBusinessLogic(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/types.go": `// @archlint.module interface
// @archlint.domain mail
package mail

type State struct{}

func BuildState() State {
	return State{}
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"interface module must not contain function bodies",
	})
}

func TestLintBackendArchitectureRejectsInterfaceModuleWithControlFlow(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/types.go": `// @archlint.module interface
// @archlint.domain mail
package mail

type State struct {
	Value string
}

func BuildState(flag bool) State {
	if flag {
		return State{Value: "enabled"}
	}
	return State{Value: "disabled"}
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"interface module must not contain control flow",
	})
}

func TestLintBackendArchitectureRequiresExemptReason(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/prototype.go": `// @archlint.module exempt
package mail

func PrototypeState() string {
	return "prototype"
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"exempt module must declare @archlint.exempt-reason",
	})
}

func TestLintBackendArchitectureRejectsExemptDomain(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/prototype.go": `// @archlint.module exempt
// @archlint.domain mail
// @archlint.exempt-reason static-data
package mail

var DemoAccount = "demo"
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"exempt module must not declare @archlint.domain",
	})
}

func TestLintBackendArchitectureRejectsUnknownExemptReason(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/prototype.go": `// @archlint.module exempt
// @archlint.exempt-reason miscellaneous
package mail

func PrototypeState() string {
	return "prototype"
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"metadata.exemptReason",
	})
}

func TestLintBackendArchitectureRejectsExemptReasonOutsideExemptModule(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/types.go": `// @archlint.module interface
// @archlint.domain mail
// @archlint.exempt-reason static-data
package mail

type State struct{}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"@archlint.exempt-reason is only valid on exempt modules",
	})
}

func TestLintBackendArchitectureAcceptsPrincipalContextExemption(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/principal/context.go": `// @archlint.module exempt
// @archlint.exempt-reason pure-glue
package principal

import "context"

type contextKey struct{}

func WithPrincipal(ctx context.Context, principal string) context.Context {
	return context.WithValue(ctx, contextKey{}, principal)
}
`,
	})

	assertNoViolations(t, lintBackendArchitecture(backendRoot))
}

func TestLintBackendArchitectureRejectsOverbroadDomains(t *testing.T) {
	files := map[string]string{}
	for index := 0; index < 17; index++ {
		files[fmt.Sprintf("internal/mail/types%d.go", index)] = fmt.Sprintf(`// @archlint.module interface
// @archlint.domain overbroad.example
package mail

type State%d struct{}
`, index)
	}
	backendRoot := newBackendFixture(t, files)

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"domain has 17 production modules; maximum is 16",
	})
}

func TestLintBackendArchitectureRejectsEmptyOrEffectfulDecisionModule(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/sync_decision.go": `// @archlint.module core
// @archlint.domain mail
package mail

import "net/http"

func notADecision() string {
	return http.MethodGet
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"core module must not import effectful dependencies",
		"core module must declare a callable decision API",
		"core module must have a same-domain test or stateTest module",
	})
}

func TestLintBackendArchitectureRejectsTypeOnlyDecisionSurface(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/sync_decision.go": `// @archlint.module core
// @archlint.domain mail
package mail

type SyncDecision struct{}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"core module must declare a callable decision API",
		"core module must have a same-domain test or stateTest module",
	})
}

func TestLintBackendArchitectureRejectsDecisionModuleWithoutPropertyTest(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/sync_decision.go": `// @archlint.module core
// @archlint.domain mail
package mail

func DecideSync() bool {
	return true
}
`,
		"internal/mail/sync_decision_test.go": `// @archlint.module test
// @archlint.domain mail
package mail

import "testing"

func TestDecideSync(t *testing.T) {
	if !DecideSync() {
		t.Fatal("expected sync")
	}
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"core module test must contain at least one property test",
	})
}

func TestLintBackendArchitectureRejectsDecisionModuleWithOnlyQuickImportOrReference(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/sync_decision.go": `// @archlint.module core
// @archlint.domain mail
package mail

func DecideSync() bool {
	return true
}
`,
		"internal/mail/sync_decision_test.go": `// @archlint.module test
// @archlint.domain mail
package mail

import (
	"testing"
	"testing/quick"
)

func TestDecideSync(t *testing.T) {
	_ = quick.Check
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"core module test must contain at least one property test",
	})
}

func TestLintBackendArchitectureAcceptsAliasedQuickCheckPropertyTest(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/sync_decision.go": `// @archlint.module core
// @archlint.domain mail
package mail

func DecideSync(input bool) bool {
	return input
}
`,
		"internal/mail/sync_decision_test.go": `// @archlint.module test
// @archlint.domain mail
package mail

import (
	"testing"
	q "testing/quick"
)

func TestDecideSync(t *testing.T) {
	property := func(input bool) bool {
		return DecideSync(input) == input
	}
	if err := q.Check(property, nil); err != nil {
		t.Fatal(err)
	}
}
`,
	})

	assertNoViolations(t, lintBackendArchitecture(backendRoot))
}

func TestGoArchitectureFileFactEmitsPropertyAndInterleavingReferencesFromReachableHelpers(t *testing.T) {
	repoRoot := t.TempDir()
	path := filepath.Join(repoRoot, "apps/backend/internal/mail/sync_decision_test.go")
	writeFixtureFile(t, repoRoot, "apps/backend/internal/mail/sync_decision_test.go", `// @archlint.module stateTest
// @archlint.domain mail
package mail

import (
	"testing"
	"testing/quick"
)

func TestDecideSyncInterleavingsProperty(t *testing.T) {
	property := func(inputs []bool) bool {
		for _, input := range inputs {
			if !helper(input) {
				return false
			}
		}
		return true
	}
	if err := quick.Check(property, nil); err != nil {
		t.Fatal(err)
	}
}

func helper(input bool) bool {
	return DecideSync(input) == input
}

func unrelated() bool {
	return DecideUnrelated()
}
`)

	fileFact, violations := goArchitectureFileFact(path)

	assertNoViolations(t, violations)
	if len(fileFact.PropertyChecks) != 1 {
		t.Fatalf("expected one property check, got %#v", fileFact.PropertyChecks)
	}
	if !fileFact.PropertyChecks[0].Interleaving {
		t.Fatal("expected stateTest property check to emit interleaving evidence")
	}
	assertStringSliceContains(t, fileFact.PropertyChecks[0].References, "DecideSync")
	assertStringSliceDoesNotContain(t, fileFact.PropertyChecks[0].References, "DecideUnrelated")
}

func TestGoArchitectureFileFactDoesNotEmitInterleavingsFromOrdinaryArrayPropertyTest(t *testing.T) {
	repoRoot := t.TempDir()
	path := filepath.Join(repoRoot, "apps/backend/internal/mail/sync_decision_test.go")
	writeFixtureFile(t, repoRoot, "apps/backend/internal/mail/sync_decision_test.go", `// @archlint.module test
// @archlint.domain mail
package mail

import (
	"testing"
	"testing/quick"
)

func TestDecideSyncAcceptsGeneratedBytesProperty(t *testing.T) {
	property := func(inputs []byte) bool {
		return DecideSync(inputs)
	}
	if err := quick.Check(property, nil); err != nil {
		t.Fatal(err)
	}
}

func DecideSync(inputs []byte) bool {
	return len(inputs) >= 0
}
`)

	fileFact, violations := goArchitectureFileFact(path)

	assertNoViolations(t, violations)
	if len(fileFact.PropertyChecks) != 1 {
		t.Fatalf("expected one property check, got %#v", fileFact.PropertyChecks)
	}
	if fileFact.PropertyChecks[0].Interleaving {
		t.Fatal("ordinary test module emitted property interleavings")
	}
	assertStringSliceContains(t, fileFact.PropertyChecks[0].References, "DecideSync")
}

func TestLintBackendArchitectureRejectsLocalQuickCheckSpoof(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/sync_decision.go": `// @archlint.module core
// @archlint.domain mail
package mail

func DecideSync(input bool) bool {
	return input
}
`,
		"internal/mail/sync_decision_test.go": `// @archlint.module test
// @archlint.domain mail
package mail

import "testing"

type fakeQuick struct{}

func (fakeQuick) Check(any, any) error {
	return nil
}

var quick fakeQuick

func TestDecideSync(t *testing.T) {
	property := func(input bool) bool {
		return DecideSync(input) == input
	}
	if err := quick.Check(property, nil); err != nil {
		t.Fatal(err)
	}
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"core module test must contain at least one property test",
	})
}

func TestLintBackendArchitectureRejectsDecisionModuleWithOnlyPropertyNamedTest(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/sync_decision.go": `// @archlint.module core
// @archlint.domain mail
package mail

func DecideSync() bool {
	return true
}
`,
		"internal/mail/sync_decision_test.go": `// @archlint.module test
// @archlint.domain mail
package mail

import "testing"

func TestDecideSyncProperty(t *testing.T) {
	if !DecideSync() {
		t.Fatal("expected sync")
	}
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"core module test must contain at least one property test",
	})
}

func TestLintBackendArchitectureRejectsDecisionModuleWithUnrelatedPropertyTest(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/sync_decision.go": `// @archlint.module core
// @archlint.domain mail
package mail

func DecideSync() bool {
	return true
}
`,
		"internal/mail/sync_decision_test.go": `// @archlint.module test
// @archlint.domain mail
package mail

import (
	"testing"
	"testing/quick"
)

func TestUnrelatedProperty(t *testing.T) {
	property := func(input string) bool {
		return input == input
	}
	if err := quick.Check(property, nil); err != nil {
		t.Fatal(err)
	}
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"core module property tests must reference every decision API: DecideSync",
	})
}

func TestLintBackendArchitectureRejectsDecisionModuleWithOnlyDecisionNamedLocalInPropertyTest(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/sync_decision.go": `// @archlint.module core
// @archlint.domain mail
package mail

func DecideSync(input bool) bool {
	return input
}
`,
		"internal/mail/sync_decision_test.go": `// @archlint.module test
// @archlint.domain mail
package mail

import (
	"testing"
	"testing/quick"
)

func TestDecideSyncProperty(t *testing.T) {
	property := func(input bool) bool {
		DecideSync := input
		return DecideSync == input
	}
	if err := quick.Check(property, nil); err != nil {
		t.Fatal(err)
	}
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"core module property tests must reference every decision API: DecideSync",
	})
}

func TestLintBackendArchitectureRejectsDecisionModuleWithWrongDomainTest(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/sync_decision.go": `// @archlint.module core
// @archlint.domain mail
package mail

func DecideSync() bool {
	return true
}
`,
		"internal/mail/sync_decision_test.go": `// @archlint.module test
// @archlint.domain auth
package mail

import "testing/quick"

func TestDecideSyncProperty() {
	_ = quick.Check
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"core module must have a same-domain test or stateTest module",
	})
}

func TestLintBackendArchitectureRejectsDecisionModuleWithWrongTestModuleType(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/sync_decision.go": `// @archlint.module core
// @archlint.domain mail
package mail

func DecideSync() bool {
	return true
}
`,
		"internal/mail/sync_decision_test.go": `// @archlint.module interface
// @archlint.domain mail
package mail

import "testing/quick"

func TestDecideSyncProperty() {
	_ = quick.Check
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"core module must have a same-domain test or stateTest module",
	})
}

func TestLintBackendArchitectureRejectsStateTestWithoutInterleavings(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/decision_test.go": `// @archlint.module stateTest
// @archlint.domain mail
package mail

import (
	"testing"
	"testing/quick"
)

func TestDecisionInterleavingsProperty(t *testing.T) {
	if err := quick.Check(func(input string) bool { return input == input }, nil); err != nil {
		t.Fatal(err)
	}
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"stateTest module must contain property interleavings",
	})
}

func TestLintBackendArchitectureRejectsInterleavingsWithoutReachableAPIReferences(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/decision_test.go": `// @archlint.module stateTest
// @archlint.domain mail
package mail

import (
	"testing"
	"testing/quick"
)

func TestDecisionInterleavingsProperty(t *testing.T) {
	if err := quick.Check(func(inputs []uint8) bool {
		for _, input := range inputs {
			if input > 255 {
				return false
			}
		}
		return true
	}, nil); err != nil {
		t.Fatal(err)
	}
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"stateTest module interleavings must reference reachable APIs",
	})
}

func TestLintBackendArchitectureRejectsStateTestInterleavingsWithoutCoreDecisionReferences(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/decision.go": `// @archlint.module core
// @archlint.domain mail
package mail

func DecideSync(input uint8) bool {
	return input%2 == 0
}
`,
		"internal/mail/decision_test.go": `// @archlint.module stateTest
// @archlint.domain mail
package mail

import (
	"testing"
	"testing/quick"
)

func TestDecisionInterleavingsProperty(t *testing.T) {
	if err := quick.Check(func(inputs []uint8) bool {
		for _, input := range inputs {
			if !helper(input) {
				return false
			}
		}
		return true
	}, nil); err != nil {
		t.Fatal(err)
	}
}

func TestDecideSyncProperty(t *testing.T) {
	if err := quick.Check(func(input uint8) bool {
		return DecideSync(input) == DecideSync(input)
	}, nil); err != nil {
		t.Fatal(err)
	}
}

func helper(input uint8) bool {
	return input <= 255
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"stateTest module interleavings must reference same-domain core decision APIs",
	})
}

func TestLintBackendArchitectureRejectsStateModuleUnrelatedToInterleavings(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/store.go": `// @archlint.module state
// @archlint.domain mail
package mail

import "sync"

type Store struct {
	mu sync.Mutex
}

func NewStore() *Store {
	return &Store{}
}

func (store *Store) Save() {
	store.mu.Lock()
	defer store.mu.Unlock()
	persistStoreState()
}

func persistStoreState() {}
`,
		"internal/mail/decision_test.go": `// @archlint.module stateTest
// @archlint.domain mail
package mail

import (
	"testing"
	"testing/quick"
)

func TestOtherDecisionInterleavingsProperty(t *testing.T) {
	if err := quick.Check(func(inputs []uint8) bool {
		for _, input := range inputs {
			if !otherDecision(input) {
				return false
			}
		}
		return true
	}, nil); err != nil {
		t.Fatal(err)
	}
}

func otherDecision(input uint8) bool {
	return input <= 255
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"state module must reference a core decision API reached by same-domain property interleavings",
	})
}

func TestLintBackendArchitectureRejectsUnmarkedSharedMutableState(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/mock_service.go": `// @archlint.module shell
// @archlint.domain mail
package mail

import "sync"

type MockService struct {
	mu sync.Mutex
}

func (service *MockService) Handle() {}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"shared mutable state may only appear in state, test, or stateTest modules",
	})
}

func TestLintBackendArchitectureRejectsAliasedSyncMutexOutsideState(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/mock_service.go": `// @archlint.module shell
// @archlint.domain mail
package mail

import s "sync"

type MockService struct {
	mu s.Mutex
}

func (service *MockService) Handle() {}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"shared mutable state may only appear in state, test, or stateTest modules",
	})
}

func TestGoArchitectureFileFactEmitsSharedStateEvidence(t *testing.T) {
	repoRoot := t.TempDir()
	path := filepath.Join(repoRoot, "apps/backend/internal/mail/mock_service.go")
	writeFixtureFile(t, repoRoot, "apps/backend/internal/mail/mock_service.go", `// @archlint.module state
// @archlint.domain mail
package mail

import "sync"

type MockService struct {
	mu sync.Mutex
}
`)

	fileFact, violations := goArchitectureFileFact(path)

	assertNoViolations(t, violations)
	if len(fileFact.SharedState) != 1 {
		t.Fatalf("expected one shared state fact, got %#v", fileFact.SharedState)
	}
	if fileFact.SharedState[0].Kind != "go-sync" {
		t.Fatalf("unexpected shared state kind: %s", fileFact.SharedState[0].Kind)
	}
	assertStringSliceContains(t, fileFact.SharedState[0].References, "sync.Mutex")
}

func TestLintBackendArchitectureIgnoresLocalMutexIdentifier(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/types.go": `// @archlint.module interface
// @archlint.domain mail
package mail

type Mutex struct{}

type Mailbox struct {
	Name string
}
`,
	})

	assertNoViolations(t, lintBackendArchitecture(backendRoot))
}

func TestLintBackendArchitectureRejectsStateModuleWithoutStateTest(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/decision.go": `// @archlint.module core
// @archlint.domain mail
package mail

func DecideState() bool {
	return true
}
`,
		"internal/mail/decision_test.go": `// @archlint.module test
// @archlint.domain mail
package mail

import "testing/quick"

func TestDecideStateProperty() {
	_ = quick.Check
}
`,
		"internal/mail/mock_service.go": `// @archlint.module state
// @archlint.domain mail
package mail

import "sync"

type MockServiceSharedMutableState struct{}

type MockService struct {
	mu sync.Mutex
}

func (service *MockService) Handle() {
	_ = DecideState()
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"state module must have a same-domain stateTest with property interleavings",
	})
}

func TestLintBackendArchitectureRejectsStateModuleWithoutStatefulAPIs(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/decision.go": `// @archlint.module core
// @archlint.domain mail
package mail

func DecideState(input uint8) bool {
	return input%2 == 0
}
`,
		"internal/mail/decision_test.go": `// @archlint.module stateTest
// @archlint.domain mail
package mail

import (
	"testing"
	"testing/quick"
)

func TestDecideStateInterleavingsProperty(t *testing.T) {
	if err := quick.Check(func(inputs []uint8) bool {
		for _, input := range inputs {
			_ = DecideState(input)
		}
		return true
	}, nil); err != nil {
		t.Fatal(err)
	}
}
`,
		"internal/mail/store.go": `// @archlint.module state
// @archlint.domain mail
package mail

func Snapshot(input uint8) bool {
	return DecideState(input)
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"state module must own stateful APIs",
	})
}

func TestLintBackendArchitectureRejectsStateModuleWithOnlyWrongDomainStateTest(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/decision.go": `// @archlint.module core
// @archlint.domain mail
package mail

func DecideState() bool {
	return true
}
`,
		"internal/mail/decision_test.go": `// @archlint.module stateTest
// @archlint.domain auth
package mail

import "testing/quick"

func TestDecideStateInterleavingsProperty() {
	_ = quick.Check
}
`,
		"internal/mail/mock_service.go": `// @archlint.module state
// @archlint.domain mail
package mail

import "sync"

type MockService struct {
	mu sync.Mutex
}

func (service *MockService) Handle() {
	_ = DecideState()
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"core module must have a same-domain test or stateTest module",
		"state module must have a same-domain stateTest with property interleavings",
	})
}

func TestLintBackendArchitectureRejectsStateTestWithoutStateModule(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/decision.go": `// @archlint.module core
// @archlint.domain mail
package mail

func DecideState(input uint8) bool {
	return input%2 == 0
}
`,
		"internal/mail/decision_test.go": `// @archlint.module stateTest
// @archlint.domain mail
package mail

import (
	"testing"
	"testing/quick"
)

func TestDecideStateInterleavingsProperty(t *testing.T) {
	if err := quick.Check(func(inputs []uint8) bool {
		for _, input := range inputs {
			_ = DecideState(input)
		}
		return true
	}, nil); err != nil {
		t.Fatal(err)
	}
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"stateTest module must have a same-domain state module",
	})
}

func TestLintBackendArchitectureRejectsMissingMetadata(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/decision.go": `package mail

func DecideState() bool {
	return true
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"module must declare @archlint.module",
	})
}

func TestLintBackendArchitectureRejectsMetadataAfterSourceBody(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/decision.go": `package mail

// @archlint.module core
// @archlint.domain mail
func DecideState() bool {
	return true
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"module must declare @archlint.module",
	})
}

func TestLintBackendArchitectureRejectsDuplicateModuleMetadata(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/decision.go": `// @archlint.module core
// @archlint.module shell
// @archlint.domain mail
package mail

func DecideState() bool {
	return true
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"module must declare @archlint.module",
	})
}

func TestLintBackendArchitectureRejectsDuplicateDomainMetadata(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/decision.go": `// @archlint.module core
// @archlint.domain mail
// @archlint.domain mail.sync
package mail

func DecideState() bool {
	return true
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"module must declare @archlint.domain",
	})
}

func TestLintBackendArchitectureRejectsDuplicateExemptReasonMetadata(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/prototype.go": `// @archlint.module exempt
// @archlint.exempt-reason static-data
// @archlint.exempt-reason test-support
package mail

var DemoAccount = "demo"
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"exempt module must declare @archlint.exempt-reason",
	})
}

func TestLintBackendArchitectureRejectsTestModuleInProductionFile(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/helper.go": `// @archlint.module test
// @archlint.domain mail
package mail

func helper() bool {
	return true
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"test module must be declared in a test scope",
	})
}

func TestLintBackendArchitectureRejectsMalformedDomain(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/decision.go": `// @archlint.module core
// @archlint.domain Backend_HTTP
package mail

func DecideState() bool {
	return true
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"module domain must be lowercase dot-or-kebab segments",
	})
}

func TestLintBackendArchitectureRejectsProductionModuleInTestFile(t *testing.T) {
	backendRoot := newBackendFixture(t, map[string]string{
		"internal/mail/decision_test.go": `// @archlint.module core
// @archlint.domain mail
package mail

func DecideState() bool {
	return true
}
`,
	})

	assertViolationsContain(t, lintBackendArchitecture(backendRoot), []string{
		"production module must not be declared in a test scope",
	})
}

func newBackendFixture(t *testing.T, files map[string]string) string {
	t.Helper()

	repoRoot := t.TempDir()
	backendRoot := filepath.Join(repoRoot, "apps/backend")
	writeFixtureFile(t, backendRoot, "go.mod", "module archlintfixture\n\ngo 1.25\n")
	for relativePath, contents := range files {
		writeFixtureFile(t, backendRoot, relativePath, contents)
	}
	return repoRoot
}

func writeFixtureFile(t *testing.T, root string, relativePath string, contents string) {
	t.Helper()

	path := filepath.Join(root, relativePath)
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(contents), 0644); err != nil {
		t.Fatal(err)
	}
}

func assertNoViolations(t *testing.T, violations []violation) {
	t.Helper()

	if len(violations) == 0 {
		return
	}

	var rendered []string
	for _, violation := range violations {
		rendered = append(rendered, violation.message)
	}
	t.Fatalf("expected no violations, got %v", rendered)
}

func assertViolationsContain(t *testing.T, violations []violation, expectedMessages []string) {
	t.Helper()

	var actualMessages []string
	for _, violation := range violations {
		actualMessages = append(actualMessages, violation.message)
	}
	for _, expectedMessage := range expectedMessages {
		found := false
		for _, actualMessage := range actualMessages {
			if strings.Contains(actualMessage, expectedMessage) {
				found = true
				break
			}
		}
		if !found {
			t.Fatalf("expected violation containing %q, got %v", expectedMessage, actualMessages)
		}
	}
}

func assertStringSliceContains(t *testing.T, values []string, expected string) {
	t.Helper()

	for _, value := range values {
		if value == expected {
			return
		}
	}
	t.Fatalf("expected %q in %v", expected, values)
}

func assertStringSliceDoesNotContain(t *testing.T, values []string, expected string) {
	t.Helper()

	for _, value := range values {
		if value == expected {
			t.Fatalf("did not expect %q in %v", expected, values)
		}
	}
}
