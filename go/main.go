package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"golang.org/x/tools/go/packages"
)

type violation struct {
	path    string
	message string
}

type moduleMetadata struct {
	moduleType   string
	domain       string
	exemptReason string
}

type architectureFactDocument struct {
	Files []architectureFileFact `json:"files"`
}

type architectureFileFact struct {
	Path                   string                        `json:"path"`
	TestScope              string                        `json:"testScope"`
	Metadata               architectureMetadataFact      `json:"metadata"`
	Imports                []string                      `json:"imports"`
	Identifiers            []string                      `json:"identifiers"`
	APIReferences          []string                      `json:"apiReferences"`
	DecisionSurface        []string                      `json:"decisionSurface"`
	PropertyTestSurface    []string                      `json:"propertyTestSurface"`
	DecisionProducts       []string                      `json:"decisionProducts"`
	DecisionReferences     []string                      `json:"decisionReferences"`
	EffectfulImports       []string                      `json:"effectfulImports"`
	EffectfulIdentifiers   []string                      `json:"effectfulIdentifiers"`
	SharedState            []sharedStateFact             `json:"sharedState"`
	PropertyChecks         []propertyCheckFact           `json:"propertyChecks"`
	InterfaceLogicEvidence architectureInterfaceEvidence `json:"interfaceLogicEvidence"`
}

type sharedStateFact struct {
	Kind       string   `json:"kind"`
	References []string `json:"references"`
}

type propertyCheckFact struct {
	References   []string `json:"references"`
	Interleaving bool     `json:"interleaving"`
}

type architectureMetadataFact struct {
	ModuleType   string `json:"moduleType"`
	Domain       string `json:"domain"`
	ExemptReason string `json:"exemptReason"`
}

type architectureInterfaceEvidence struct {
	FunctionBodies         []string `json:"functionBodies"`
	ConstructorBodies      []string `json:"constructorBodies"`
	DerivedValueBodies     []string `json:"derivedValueBodies"`
	ControlFlow            []string `json:"controlFlow"`
	ImperativeDeclarations []string `json:"imperativeDeclarations"`
}

func main() {
	repoRoot := flag.String("repo-root", "../..", "repository root")
	goModule := flag.String("go-module", "", "Go module path relative to repository root")
	goPackages := flag.String("go-packages", "", "Go package pattern relative to the Go module")
	flag.Parse()
	if *goModule == "" {
		fatal(fmt.Errorf("--go-module is required"))
	}
	if *goPackages == "" {
		fatal(fmt.Errorf("--go-packages is required"))
	}

	absoluteRoot, err := filepath.Abs(*repoRoot)
	if err != nil {
		fatal(err)
	}

	moduleRoot := filepath.Join(absoluteRoot, *goModule)
	facts, violations := goArchitectureFacts(moduleRoot, *goPackages)
	if len(violations) > 0 {
		sortViolations(violations)
		for _, currentViolation := range violations {
			fmt.Fprintf(os.Stderr, "%s: %s\n", currentViolation.path, currentViolation.message)
		}
		os.Exit(1)
	}
	encoder := json.NewEncoder(os.Stdout)
	if err := encoder.Encode(facts); err != nil {
		fatal(err)
	}
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}

func goArchitectureFacts(moduleRoot string, packagePattern string) (architectureFactDocument, []violation) {
	var violations []violation
	loadedPackages, loadViolations := loadGoPackages(moduleRoot, packagePattern)
	violations = append(violations, loadViolations...)

	facts := architectureFactDocument{}
	seenFiles := map[string]struct{}{}
	for _, path := range goPackagePatternFiles(moduleRoot, packagePattern) {
		seenFiles[path] = struct{}{}
		fileFact, factViolations := goArchitectureFileFact(path)
		violations = append(violations, factViolations...)
		if len(factViolations) == 0 {
			facts.Files = append(facts.Files, fileFact)
		}
	}
	for _, loadedPackage := range loadedPackages {
		for _, path := range goPackageFiles(loadedPackage) {
			if filepath.Ext(path) != ".go" {
				continue
			}
			if _, ok := seenFiles[path]; ok {
				continue
			}
			seenFiles[path] = struct{}{}
			fileFact, factViolations := goArchitectureFileFact(path)
			violations = append(violations, factViolations...)
			if len(factViolations) == 0 {
				facts.Files = append(facts.Files, fileFact)
			}
		}
	}
	return facts, violations
}

func goPackagePatternFiles(moduleRoot string, packagePattern string) []string {
	patternRoot := packagePattern
	if strings.HasSuffix(patternRoot, "/...") {
		patternRoot = strings.TrimSuffix(patternRoot, "/...")
	}
	if patternRoot == "." || patternRoot == "./" {
		patternRoot = ""
	}
	patternRoot = strings.TrimPrefix(patternRoot, "./")

	root := filepath.Join(moduleRoot, patternRoot)
	files := map[string]struct{}{}
	_ = filepath.WalkDir(root, func(path string, entry os.DirEntry, err error) error {
		if err != nil || entry.IsDir() || filepath.Ext(path) != ".go" {
			return nil
		}
		files[path] = struct{}{}
		return nil
	})
	return setToSortedSlice(files)
}

func loadGoPackages(moduleRoot string, packagePattern string) ([]*packages.Package, []violation) {
	config := packages.Config{
		Dir:  moduleRoot,
		Mode: packages.NeedName | packages.NeedFiles | packages.NeedCompiledGoFiles | packages.NeedImports | packages.NeedSyntax,
	}
	loadedPackages, err := packages.Load(&config, packagePattern)
	if err != nil {
		return nil, []violation{{path: moduleRoot, message: err.Error()}}
	}
	var violations []violation
	for _, loadedPackage := range loadedPackages {
		for _, packageError := range loadedPackage.Errors {
			violations = append(violations, violation{
				path:    loadedPackage.PkgPath,
				message: packageError.Msg,
			})
		}
	}
	return loadedPackages, violations
}

func goPackageFiles(loadedPackage *packages.Package) []string {
	packageDirs := map[string]struct{}{}
	for _, path := range append(loadedPackage.GoFiles, loadedPackage.CompiledGoFiles...) {
		packageDirs[filepath.Dir(path)] = struct{}{}
	}

	files := map[string]struct{}{}
	for packageDir := range packageDirs {
		entries, err := os.ReadDir(packageDir)
		if err != nil {
			continue
		}
		for _, entry := range entries {
			if entry.IsDir() || filepath.Ext(entry.Name()) != ".go" {
				continue
			}
			files[filepath.Join(packageDir, entry.Name())] = struct{}{}
		}
	}
	return setToSortedSlice(files)
}

func goArchitectureFileFact(path string) (architectureFileFact, []violation) {
	syntaxFile, err := parser.ParseFile(token.NewFileSet(), path, nil, 0)
	if err != nil {
		return architectureFileFact{}, []violation{{path: path, message: err.Error()}}
	}
	metadata := moduleMetadataForFile(path)
	imports := goImports(syntaxFile)
	identifiers := goIdentifiers(syntaxFile)
	apiReferences := goAPIReferences(syntaxFile)
	decisionSurface := declaredDecisionSurface(syntaxFile)
	decisionProducts := declaredDecisionProducts(syntaxFile)
	decisionReferences := declaredDecisionReferences(syntaxFile)
	propertyEvidence := goPropertyEvidence(syntaxFile)
	if metadata.moduleType != "stateTest" {
		for index := range propertyEvidence.checks {
			propertyEvidence.checks[index].interleaving = false
		}
	}
		return architectureFileFact{
			Path:                   path,
			TestScope:              goTestScope(path),
		Metadata:               architectureMetadataForGo(metadata),
		Imports:                imports,
		Identifiers:            setToSortedSlice(identifiers),
		APIReferences:          setToSortedSlice(apiReferences),
		DecisionSurface:        setToSortedSlice(decisionSurface),
		PropertyTestSurface:    setToSortedSlice(decisionSurface),
		DecisionProducts:       setToSortedSlice(decisionProducts),
		DecisionReferences:     setToSortedSlice(decisionReferences),
		EffectfulImports:       goEffectfulImports(imports),
		EffectfulIdentifiers:   []string{},
		SharedState:            goSharedStateEvidence(syntaxFile),
		PropertyChecks:         goPropertyCheckFacts(propertyEvidence),
		InterfaceLogicEvidence: goInterfaceLogicEvidence(syntaxFile),
	}, nil
}

func architectureMetadataForGo(metadata moduleMetadata) architectureMetadataFact {
	return architectureMetadataFact{
		ModuleType:   metadata.moduleType,
		Domain:       metadata.domain,
		ExemptReason: metadata.exemptReason,
	}
}

func goTestScope(path string) string {
	if !strings.HasSuffix(path, "_test.go") {
		return ""
	}
	return strings.TrimSuffix(path, ".go")
}

func goImports(syntaxFile *ast.File) []string {
	imports := make([]string, 0, len(syntaxFile.Imports))
	for _, currentImport := range syntaxFile.Imports {
		imports = append(imports, importPath(currentImport))
	}
	return imports
}

func goImportNamesByPath(syntaxFile *ast.File) map[string]map[string]bool {
	imports := map[string]map[string]bool{}
	for _, currentImport := range syntaxFile.Imports {
		path := importPath(currentImport)
		if imports[path] == nil {
			imports[path] = map[string]bool{}
		}
		name := filepath.Base(path)
		if currentImport.Name != nil {
			name = currentImport.Name.Name
		}
		if name != "_" {
			imports[path][name] = true
		}
	}
	return imports
}

func importPath(importSpec *ast.ImportSpec) string {
	path, err := strconv.Unquote(importSpec.Path.Value)
	if err != nil {
		return strings.Trim(importSpec.Path.Value, `"`)
	}
	return path
}

func goIdentifiers(syntaxFile *ast.File) map[string]struct{} {
	identifiers := map[string]struct{}{}
	ast.Inspect(syntaxFile, func(node ast.Node) bool {
		identifier, ok := node.(*ast.Ident)
		if ok {
			identifiers[identifier.Name] = struct{}{}
		}
		return true
	})
	return identifiers
}

func goAPIReferences(syntaxFile *ast.File) map[string]struct{} {
	return goAPIReferencesFromNode(syntaxFile)
}

func goAPIReferencesFromNode(root ast.Node) map[string]struct{} {
	references := map[string]struct{}{}
	ast.Inspect(root, func(node ast.Node) bool {
		switch typedNode := node.(type) {
		case *ast.CallExpr:
			recordGoCallableReference(references, typedNode.Fun)
		case *ast.CompositeLit:
			recordGoTypeReference(references, typedNode.Type)
		case *ast.Field:
			recordGoTypeReference(references, typedNode.Type)
		case *ast.ValueSpec:
			recordGoTypeReference(references, typedNode.Type)
		}
		return true
	})
	return references
}

func recordGoCallableReference(references map[string]struct{}, expression ast.Expr) {
	switch typedExpression := expression.(type) {
	case *ast.Ident:
		references[typedExpression.Name] = struct{}{}
	case *ast.SelectorExpr:
		references[typedExpression.Sel.Name] = struct{}{}
		recordGoTypeReference(references, typedExpression.X)
	}
}

func recordGoTypeReference(references map[string]struct{}, expression ast.Expr) {
	switch typedExpression := expression.(type) {
	case *ast.Ident:
		references[typedExpression.Name] = struct{}{}
	case *ast.SelectorExpr:
		references[typedExpression.Sel.Name] = struct{}{}
	case *ast.StarExpr:
		recordGoTypeReference(references, typedExpression.X)
	case *ast.ArrayType:
		recordGoTypeReference(references, typedExpression.Elt)
	case *ast.MapType:
		recordGoTypeReference(references, typedExpression.Key)
		recordGoTypeReference(references, typedExpression.Value)
	case *ast.FuncType:
		if typedExpression.Params != nil {
			for _, field := range typedExpression.Params.List {
				recordGoTypeReference(references, field.Type)
			}
		}
		if typedExpression.Results != nil {
			for _, field := range typedExpression.Results.List {
				recordGoTypeReference(references, field.Type)
			}
		}
	}
}

func moduleMetadataForFile(path string) moduleMetadata {
	contents, err := os.ReadFile(path)
	if err != nil {
		return moduleMetadata{}
	}
	return parseModuleMetadata(string(contents))
}

func parseModuleMetadata(source string) moduleMetadata {
	metadata := moduleMetadata{}
	seenModuleType := false
	seenDomain := false
	seenExemptReason := false
	duplicateModuleType := false
	duplicateDomain := false
	duplicateExemptReason := false
	for _, line := range strings.Split(source, "\n") {
		trimmedLine := strings.TrimSpace(line)
		if trimmedLine == "" {
			continue
		}
		if !strings.HasPrefix(trimmedLine, "//") {
			break
		}
		trimmed := strings.TrimSpace(strings.TrimPrefix(trimmedLine, "//"))
		fields := strings.Fields(trimmed)
		if len(fields) != 2 {
			continue
		}
		switch fields[0] {
		case "@archlint.module":
			if seenModuleType {
				duplicateModuleType = true
			}
			seenModuleType = true
			metadata.moduleType = fields[1]
		case "@archlint.domain":
			if seenDomain {
				duplicateDomain = true
			}
			seenDomain = true
			metadata.domain = fields[1]
		case "@archlint.exempt-reason":
			if seenExemptReason {
				duplicateExemptReason = true
			}
			seenExemptReason = true
			metadata.exemptReason = fields[1]
		}
	}
	if duplicateModuleType {
		metadata.moduleType = ""
	}
	if duplicateDomain {
		metadata.domain = ""
	}
	if duplicateExemptReason {
		metadata.exemptReason = ""
	}
	return metadata
}

func goEffectfulImports(imports []string) []string {
	effectfulImports := map[string]struct{}{}
	for _, importPath := range imports {
		if _, ok := goRealEffectImports()[importPath]; ok {
			effectfulImports[importPath] = struct{}{}
		}
	}
	return setToSortedSlice(effectfulImports)
}

func goRealEffectImports() map[string]struct{} {
	return map[string]struct{}{
		"crypto/rand":                    {},
		"crypto/tls":                     {},
		"database/sql":                   {},
		"encoding/json":                  {},
		"io":                             {},
		"io/fs":                          {},
		"net":                            {},
		"net/http":                       {},
		"os":                             {},
		"path/filepath":                  {},
		"github.com/emersion/go-imap/v2": {},
		"github.com/emersion/go-imap/v2/imapclient": {},
		"github.com/emersion/go-message":            {},
		"github.com/emersion/go-message/charset":    {},
		"github.com/emersion/go-message/mail":       {},
		"github.com/emersion/go-sasl":               {},
		"github.com/emersion/go-smtp":               {},
		"github.com/go-chi/chi/v5":                  {},
		"github.com/golang-jwt/jwt/v5":              {},
		"github.com/joho/godotenv":                  {},
	}
}

func declaredDecisionSurface(syntaxFile *ast.File) map[string]struct{} {
	apis := map[string]struct{}{}
	for _, declaration := range syntaxFile.Decls {
		typedDeclaration, ok := declaration.(*ast.FuncDecl)
		if ok && typedDeclaration.Recv == nil && ast.IsExported(typedDeclaration.Name.Name) {
			apis[typedDeclaration.Name.Name] = struct{}{}
		}
	}
	return apis
}

func declaredDecisionProducts(syntaxFile *ast.File) map[string]struct{} {
	products := map[string]struct{}{}
	for _, declaration := range syntaxFile.Decls {
		functionDeclaration, ok := declaration.(*ast.FuncDecl)
		if !ok || functionDeclaration.Recv != nil || !ast.IsExported(functionDeclaration.Name.Name) {
			continue
		}
		recordGoResultProducts(products, functionDeclaration.Type.Results)
	}
	return products
}

func recordGoResultProducts(products map[string]struct{}, results *ast.FieldList) {
	if results == nil {
		return
	}
	for _, field := range results.List {
		recordGoNamedType(products, field.Type)
	}
}

func recordGoNamedType(products map[string]struct{}, expression ast.Expr) {
	switch typedExpression := expression.(type) {
	case *ast.Ident:
		if ast.IsExported(typedExpression.Name) {
			products[typedExpression.Name] = struct{}{}
		}
	case *ast.SelectorExpr:
		if ast.IsExported(typedExpression.Sel.Name) {
			products[typedExpression.Sel.Name] = struct{}{}
		}
	case *ast.StarExpr:
		recordGoNamedType(products, typedExpression.X)
	case *ast.ArrayType:
		recordGoNamedType(products, typedExpression.Elt)
	case *ast.MapType:
		recordGoNamedType(products, typedExpression.Key)
		recordGoNamedType(products, typedExpression.Value)
	}
}

func declaredDecisionReferences(syntaxFile *ast.File) map[string]struct{} {
	references := declaredDecisionSurface(syntaxFile)
	for _, declaration := range syntaxFile.Decls {
		genericDeclaration, ok := declaration.(*ast.GenDecl)
		if !ok {
			continue
		}
		for _, spec := range genericDeclaration.Specs {
			typeSpec, ok := spec.(*ast.TypeSpec)
			if ok && ast.IsExported(typeSpec.Name.Name) {
				references[typeSpec.Name.Name] = struct{}{}
			}
		}
	}
	return references
}

func setToSortedSlice(values map[string]struct{}) []string {
	slice := make([]string, 0, len(values))
	for value := range values {
		slice = append(slice, value)
	}
	sort.Strings(slice)
	return slice
}

func sortedUniqueStrings(values []string) []string {
	uniqueValues := map[string]struct{}{}
	for _, value := range values {
		uniqueValues[value] = struct{}{}
	}
	return setToSortedSlice(uniqueValues)
}

func goSharedStateEvidence(syntaxFile *ast.File) []sharedStateFact {
	importsByName := goImportNamesByPath(syntaxFile)
	syncNames := importsByName["sync"]
	atomicNames := importsByName["sync/atomic"]
	evidence := map[string]map[string]struct{}{}
	ast.Inspect(syntaxFile, func(node ast.Node) bool {
		selector, ok := node.(*ast.SelectorExpr)
		if !ok {
			return true
		}
		receiver, ok := selector.X.(*ast.Ident)
		if !ok {
			return true
		}
		if syncNames[receiver.Name] && isSyncStateType(selector.Sel.Name) {
			addSharedStateReference(evidence, "go-sync", "sync."+selector.Sel.Name)
			return true
		}
		if atomicNames[receiver.Name] {
			addSharedStateReference(evidence, "go-atomic", "sync/atomic."+selector.Sel.Name)
			return true
		}
		return true
	})
	for _, reference := range dotImportedSyncStateReferences(syntaxFile, syncNames, atomicNames) {
		addSharedStateReference(evidence, "go-sync", reference)
	}
	return sharedStateFacts(evidence)
}

func isSyncStateType(name string) bool {
	switch name {
	case "Map", "Mutex", "RWMutex":
		return true
	default:
		return false
	}
}

func dotImportedSyncStateReferences(
	syntaxFile *ast.File,
	syncNames map[string]bool,
	atomicNames map[string]bool,
) []string {
	if atomicNames["."] {
		return []string{"sync/atomic.*"}
	}
	if !syncNames["."] {
		return []string{}
	}
	references := map[string]struct{}{}
	ast.Inspect(syntaxFile, func(node ast.Node) bool {
		identifier, ok := node.(*ast.Ident)
		if ok && isSyncStateType(identifier.Name) {
			references["sync."+identifier.Name] = struct{}{}
		}
		return true
	})
	return setToSortedSlice(references)
}

func addSharedStateReference(evidence map[string]map[string]struct{}, kind string, reference string) {
	if _, ok := evidence[kind]; !ok {
		evidence[kind] = map[string]struct{}{}
	}
	evidence[kind][reference] = struct{}{}
}

func sharedStateFacts(evidence map[string]map[string]struct{}) []sharedStateFact {
	kinds := make([]string, 0, len(evidence))
	for kind := range evidence {
		kinds = append(kinds, kind)
	}
	sort.Strings(kinds)
	facts := make([]sharedStateFact, 0, len(kinds))
	for _, kind := range kinds {
		facts = append(facts, sharedStateFact{
			Kind:       kind,
			References: setToSortedSlice(evidence[kind]),
		})
	}
	return facts
}

func goInterfaceLogicEvidence(syntaxFile *ast.File) architectureInterfaceEvidence {
	functionBodies := map[string]struct{}{}
	imperativeDeclarations := map[string]struct{}{}
	for _, declaration := range syntaxFile.Decls {
		switch typedDeclaration := declaration.(type) {
		case *ast.FuncDecl:
			if typedDeclaration.Body != nil {
				functionBodies[typedDeclaration.Name.Name] = struct{}{}
			}
		case *ast.GenDecl:
			switch typedDeclaration.Tok.String() {
			case "import", "type", "const":
			default:
				imperativeDeclarations[typedDeclaration.Tok.String()] = struct{}{}
			}
		default:
			imperativeDeclarations[fmt.Sprintf("%T", declaration)] = struct{}{}
		}
	}
	return architectureInterfaceEvidence{
		FunctionBodies:         setToSortedSlice(functionBodies),
		ConstructorBodies:      []string{},
		DerivedValueBodies:     []string{},
		ControlFlow:            goControlFlowEvidence(syntaxFile),
		ImperativeDeclarations: setToSortedSlice(imperativeDeclarations),
	}
}

func goControlFlowEvidence(syntaxFile *ast.File) []string {
	controlFlow := map[string]struct{}{}
	ast.Inspect(syntaxFile, func(node ast.Node) bool {
		switch node.(type) {
		case *ast.IfStmt:
			controlFlow["if"] = struct{}{}
		case *ast.SwitchStmt:
			controlFlow["switch"] = struct{}{}
		case *ast.TypeSwitchStmt:
			controlFlow["type-switch"] = struct{}{}
		case *ast.ForStmt:
			controlFlow["for"] = struct{}{}
		case *ast.RangeStmt:
			controlFlow["range"] = struct{}{}
		case *ast.SelectStmt:
			controlFlow["select"] = struct{}{}
		default:
		}
		return true
	})
	return setToSortedSlice(controlFlow)
}

type goPropertyEvidenceResult struct {
	checks []goPropertyCheckEvidence
}

type goPropertyCheckEvidence struct {
	references   map[string]struct{}
	interleaving bool
}

func goPropertyEvidence(syntaxFile *ast.File) goPropertyEvidenceResult {
	globalFunctions := goFunctionDeclarationsByName(syntaxFile)
	quickNames := goImportNamesByPath(syntaxFile)["testing/quick"]
	result := goPropertyEvidenceResult{}
	for _, declaration := range syntaxFile.Decls {
		functionDeclaration, ok := declaration.(*ast.FuncDecl)
		if !ok || functionDeclaration.Body == nil {
			continue
		}
		propertyFunctions := copyGoPropertyFunctions(globalFunctions)
		for name, propertyFunction := range goAssignedFunctionLiteralsByName(functionDeclaration.Body) {
			propertyFunctions[name] = propertyFunction
		}
		ast.Inspect(functionDeclaration.Body, func(node ast.Node) bool {
			call, ok := node.(*ast.CallExpr)
			if !ok || !isGoQuickCheckCall(call, quickNames) {
				return true
			}
			propertyFunction := goQuickCheckPropertyFunction(call, propertyFunctions)
			references := map[string]struct{}{}
			if propertyFunction != nil {
				for reference := range goReachablePropertyReferences(propertyFunction, propertyFunctions, map[string]bool{}) {
					references[reference] = struct{}{}
				}
			}
			result.checks = append(result.checks, goPropertyCheckEvidence{
				references:   references,
				interleaving: goFunctionHasSliceParameter(propertyFunction),
			})
			return true
		})
	}
	return result
}

func goPropertyCheckFacts(evidence goPropertyEvidenceResult) []propertyCheckFact {
	facts := make([]propertyCheckFact, 0, len(evidence.checks))
	for _, check := range evidence.checks {
		facts = append(facts, propertyCheckFact{
			References:   setToSortedSlice(check.references),
			Interleaving: check.interleaving,
		})
	}
	return facts
}

func isGoQuickCheckCall(call *ast.CallExpr, quickNames map[string]bool) bool {
	selector, ok := call.Fun.(*ast.SelectorExpr)
	if !ok {
		return false
	}
	receiver, ok := selector.X.(*ast.Ident)
	return ok && quickNames[receiver.Name] && selector.Sel.Name == "Check"
}

type goPropertyFunction struct {
	functionType *ast.FuncType
	body         ast.Node
}

func goFunctionDeclarationsByName(syntaxFile *ast.File) map[string]goPropertyFunction {
	propertyFunctions := map[string]goPropertyFunction{}
	for _, declaration := range syntaxFile.Decls {
		functionDeclaration, ok := declaration.(*ast.FuncDecl)
		if ok && functionDeclaration.Body != nil {
			propertyFunctions[functionDeclaration.Name.Name] = goPropertyFunction{
				functionType: functionDeclaration.Type,
				body:         functionDeclaration.Body,
			}
		}
	}
	return propertyFunctions
}

func goAssignedFunctionLiteralsByName(root ast.Node) map[string]goPropertyFunction {
	propertyFunctions := map[string]goPropertyFunction{}
	ast.Inspect(root, func(node ast.Node) bool {
		assign, ok := node.(*ast.AssignStmt)
		if !ok {
			return true
		}
		for index, left := range assign.Lhs {
			if index >= len(assign.Rhs) {
				continue
			}
			name, ok := left.(*ast.Ident)
			if !ok {
				continue
			}
			functionLiteral, ok := assign.Rhs[index].(*ast.FuncLit)
			if ok {
				propertyFunctions[name.Name] = goPropertyFunction{
					functionType: functionLiteral.Type,
					body:         functionLiteral.Body,
				}
			}
		}
		return true
	})
	return propertyFunctions
}

func copyGoPropertyFunctions(values map[string]goPropertyFunction) map[string]goPropertyFunction {
	copied := map[string]goPropertyFunction{}
	for name, value := range values {
		copied[name] = value
	}
	return copied
}

func goQuickCheckPropertyFunction(
	call *ast.CallExpr,
	propertyFunctions map[string]goPropertyFunction,
) *goPropertyFunction {
	if len(call.Args) == 0 {
		return nil
	}
	switch firstArgument := call.Args[0].(type) {
	case *ast.FuncLit:
		return &goPropertyFunction{functionType: firstArgument.Type, body: firstArgument.Body}
	case *ast.Ident:
		if propertyFunction, ok := propertyFunctions[firstArgument.Name]; ok {
			return &propertyFunction
		}
		return nil
	default:
		return nil
	}
}

func goReachablePropertyReferences(
	propertyFunction *goPropertyFunction,
	propertyFunctions map[string]goPropertyFunction,
	visited map[string]bool,
) map[string]struct{} {
	if propertyFunction == nil {
		return map[string]struct{}{}
	}
	references := goAPIReferencesFromNode(propertyFunction.body)
	for reference := range references {
		if visited[reference] {
			continue
		}
		referencedFunction, ok := propertyFunctions[reference]
		if !ok {
			continue
		}
		visited[reference] = true
		for nestedReference := range goReachablePropertyReferences(&referencedFunction, propertyFunctions, visited) {
			references[nestedReference] = struct{}{}
		}
	}
	return references
}

func goFunctionHasSliceParameter(propertyFunction *goPropertyFunction) bool {
	if propertyFunction == nil || propertyFunction.functionType == nil || propertyFunction.functionType.Params == nil {
		return false
	}
	for _, field := range propertyFunction.functionType.Params.List {
		if _, ok := field.Type.(*ast.ArrayType); ok {
			return true
		}
	}
	return false
}

func sortViolations(violations []violation) {
	sort.Slice(violations, func(leftIndex, rightIndex int) bool {
		left := violations[leftIndex]
		right := violations[rightIndex]
		if left.path == right.path {
			return left.message < right.message
		}
		return left.path < right.path
	})
}
