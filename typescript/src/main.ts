import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import ts from "typescript";

type Metadata = {
  moduleType: string;
  domain: string;
  exemptReason: string;
};

type GeneratedInputFact = {
  name: string;
  uses: string[];
};

type OperationSequenceFact = {
  input: string;
  operations: string[];
  assertions: string[];
};

type PropertyCheckFact = {
  references: string[];
  generatedInputs: GeneratedInputFact[];
  operationSequences: OperationSequenceFact[];
};

type SharedStateFact = {
  kind: string;
  references: string[];
};

type InterfaceLogicEvidence = {
  functionBodies: string[];
  constructorBodies: string[];
  derivedValueBodies: string[];
  controlFlow: string[];
  imperativeDeclarations: string[];
};

type SourceFact = {
  path: string;
  testScope: string;
  metadata: Metadata;
  imports: string[];
  identifiers: string[];
  apiReferences: string[];
  decisionSurface: string[];
  propertyTestSurface: string[];
  decisionProducts: string[];
  decisionReferences: string[];
  moduleName: string;
  qualifiedReferences: string[];
  effectfulImports: string[];
  effectfulIdentifiers: string[];
  sharedState: SharedStateFact[];
  propertyChecks: PropertyCheckFact[];
  interfaceLogicEvidence: InterfaceLogicEvidence;
};

type Facts = {
  imports: Set<string>;
  identifiers: Set<string>;
  apiReferences: Set<string>;
  decisionSurface: Set<string>;
  propertyTestSurface: Set<string>;
  decisionProducts: Set<string>;
  decisionReferences: Set<string>;
  qualifiedReferences: Set<string>;
  effectfulIdentifiers: Set<string>;
  sharedState: Map<string, Set<string>>;
  propertyChecks: PropertyCheckFact[];
  functionReferences: Map<string, Set<string>>;
  functionBodies: Map<string, ts.FunctionLikeDeclaration>;
  interfaceLogicEvidence: InterfaceLogicEvidence;
};

type ParsedFile = {
  filePath: string;
  source: string;
  sourceFile: ts.SourceFile;
  facts: Facts;
};

type ProgramContext = {
  program: ts.Program;
  checker: ts.TypeChecker;
  ownedSourceFiles: Set<string>;
};

const sourceExtensions = new Set([".ts", ".tsx", ".mts", ".cts"]);
const ignoredDirectories = new Set(["node_modules", "dist", "build", "coverage", ".git"]);

const effectfulImports = new Set([
  "child_process",
  "commander",
  "fs",
  "node:child_process",
  "node:fs",
  "node:fs/promises",
  "node:http",
  "node:https",
  "node:net",
  "node:os",
  "node:path",
  "node:process",
  "node:readline",
  "node:stream",
  "node:url",
  "node:worker_threads",
  "process",
]);

const effectfulIdentifiers = new Set([
  "Command",
  "console",
  "fetch",
  "File",
  "process",
  "readFile",
  "readFileSync",
  "writeFile",
  "writeFileSync",
]);

const testImports = new Set(["node:test", "fast-check"]);
const propertyNames = new Set(["property", "asyncProperty"]);
const operationGeneratorNames = new Set(["array", "uniqueArray"]);

function main(): void {
  try {
    const args = parseArgs(process.argv.slice(2));
    const repoRoot = path.resolve(args.get("--repo-root") ?? ".");
    const root = path.resolve(repoRoot, args.get("--typescript-root") ?? ".");
    const files = sourceFiles(root);
    const programContext = buildProgram(files, root);
    const parsedFiles = files.map((filePath) => parseSourceFacts(filePath, programContext));
    const globalFunctionReferences = uniqueGlobalFunctionReferences(parsedFiles);
    const facts = parsedFiles.map((file) => sourceFact(file, globalFunctionReferences, programContext));
    process.stdout.write(`${JSON.stringify({ files: facts })}\n`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`typescript adapter failed: ${message}\n`);
    process.exitCode = 1;
  }
}

function parseArgs(args: string[]): Map<string, string> {
  const parsed = new Map<string, string>();
  for (let index = 0; index < args.length; index += 1) {
    const key = args[index];
    if (key === undefined || !key.startsWith("--")) {
      continue;
    }
    const value = args[index + 1];
    if (value === undefined || value.startsWith("--")) {
      throw new Error(`missing value for ${key}`);
    }
    parsed.set(key, value);
    index += 1;
  }
  return parsed;
}

function sourceFiles(root: string): string[] {
  const files: string[] = [];
  const walk = (current: string): void => {
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      if (entry.isDirectory()) {
        if (!ignoredDirectories.has(entry.name)) {
          walk(path.join(current, entry.name));
        }
        continue;
      }
      if (entry.isFile() && sourceExtensions.has(path.extname(entry.name))) {
        files.push(path.join(current, entry.name));
      }
    }
  };
  walk(root);
  return files.sort();
}

function buildProgram(filePaths: string[], root: string): ProgramContext {
  const configPath = ts.findConfigFile(root, ts.sys.fileExists);
  const parsedConfig = configPath === undefined ? defaultCompilerConfig(filePaths) : compilerConfigFromTsconfig(configPath);
  const rootNames = sorted(new Set([...parsedConfig.fileNames, ...filePaths])).map((filePath) => path.resolve(filePath));
  const program = ts.createProgram({
    rootNames,
    options: parsedConfig.options,
  });
  const diagnostics = relevantProgramDiagnostics(program, root, new Set(filePaths.map(normalizePath)));
  if (diagnostics.length > 0) {
    throw new Error(formatDiagnostics(diagnostics));
  }
  return {
    program,
    checker: program.getTypeChecker(),
    ownedSourceFiles: new Set(filePaths.map(normalizePath)),
  };
}

function defaultCompilerConfig(filePaths: string[]): ts.ParsedCommandLine {
  return {
    options: {
      target: ts.ScriptTarget.ES2022,
      module: ts.ModuleKind.NodeNext,
      moduleResolution: ts.ModuleResolutionKind.NodeNext,
      strict: true,
      skipLibCheck: true,
      esModuleInterop: true,
    },
    fileNames: filePaths,
    errors: [],
  };
}

function compilerConfigFromTsconfig(configPath: string): ts.ParsedCommandLine {
  const config = ts.readConfigFile(configPath, ts.sys.readFile);
  if (config.error !== undefined) {
    throw new Error(formatDiagnostics([config.error]));
  }
  const parsed = ts.parseJsonConfigFileContent(config.config, ts.sys, path.dirname(configPath), undefined, configPath);
  if (parsed.errors.length > 0) {
    throw new Error(formatDiagnostics(parsed.errors));
  }
  return parsed;
}

function relevantProgramDiagnostics(program: ts.Program, root: string, ownedSourceFiles: Set<string>): ts.Diagnostic[] {
  return ts.getPreEmitDiagnostics(program).filter((diagnostic) => {
    if (diagnostic.code === 2307 && diagnostic.file !== undefined) {
      return unresolvedLocalModuleDiagnostic(diagnostic, root, ownedSourceFiles);
    }
    return diagnostic.category === ts.DiagnosticCategory.Error && diagnostic.file === undefined;
  });
}

function unresolvedLocalModuleDiagnostic(diagnostic: ts.Diagnostic, root: string, ownedSourceFiles: Set<string>): boolean {
  const message = ts.flattenDiagnosticMessageText(diagnostic.messageText, "\n");
  const match = message.match(/Cannot find module '([^']+)'/u);
  if (match === null) {
    return true;
  }
  const specifier = match[1];
  if (specifier === undefined || !specifier.startsWith(".")) {
    return false;
  }
  const containingFile = diagnostic.file;
  if (containingFile === undefined) {
    return true;
  }
  const resolved = resolveLocalModuleSpecifier(path.dirname(containingFile.fileName), specifier);
  return resolved === undefined || !ownedSourceFiles.has(normalizePath(resolved)) || !normalizePath(resolved).startsWith(normalizePath(root));
}

function resolveLocalModuleSpecifier(baseDirectory: string, specifier: string): string | undefined {
  const withoutExtension = stripModuleExtension(path.resolve(baseDirectory, specifier));
  const candidates = [
    path.resolve(baseDirectory, specifier),
    ...[...sourceExtensions.values()].map((extension) => `${withoutExtension}${extension}`),
    ...[...sourceExtensions.values()].map((extension) => path.join(path.resolve(baseDirectory, specifier), `index${extension}`)),
  ];
  return candidates.find((candidate) => ts.sys.fileExists(candidate));
}

function formatDiagnostics(diagnostics: ts.Diagnostic[]): string {
  const host: ts.FormatDiagnosticsHost = {
    getCanonicalFileName: (fileName) => fileName,
    getCurrentDirectory: () => process.cwd(),
    getNewLine: () => "\n",
  };
  return ts.formatDiagnosticsWithColorAndContext(diagnostics, host);
}

function parseSourceFacts(filePath: string, programContext: ProgramContext): ParsedFile {
  const source = readFileSync(filePath, "utf8");
  const sourceFile = programContext.program.getSourceFile(filePath);
  if (sourceFile === undefined) {
    throw new Error(`program did not include ${filePath}`);
  }
  const facts = emptyFacts();
  collectTopLevel(facts, sourceFile);
  return { filePath, source, sourceFile, facts };
}

// Extensions tried longest-first so e.g. "index.d.ts" strips to "index", not
// "index.d".
const moduleExtensions = [".d.ts", ".ts", ".tsx", ".mts", ".cts", ".js", ".jsx", ".mjs", ".cjs"];

function stripModuleExtension(name: string): string {
  for (const extension of moduleExtensions) {
    if (name.endsWith(extension)) {
      return name.slice(0, name.length - extension.length);
    }
  }
  return name;
}

function moduleNameFromPath(filePath: string): string {
  const baseName = stripModuleExtension(path.basename(filePath));
  return baseName === "" ? "" : `${baseName[0]?.toUpperCase() ?? ""}${baseName.slice(1)}`;
}

function sourceFact(file: ParsedFile, globalFunctionReferences: Map<string, Set<string>>, programContext: ProgramContext): SourceFact {
  const { filePath, source, sourceFile, facts } = file;
  for (const [name, references] of globalFunctionReferences) {
    if (!facts.functionReferences.has(name)) {
      facts.functionReferences.set(name, references);
    }
  }
  collectNodeFacts(facts, sourceFile);
  collectQualifiedReferences(facts, sourceFile, programContext);
  const metadata = parseMetadata(source);
  if (metadata.moduleType !== "stateTest") {
    for (const check of facts.propertyChecks) {
      check.operationSequences = [];
    }
  }
  return {
    path: filePath,
    testScope: inferTestScope(filePath, facts),
    metadata,
    imports: sorted(facts.imports),
    identifiers: sorted(facts.identifiers),
    apiReferences: sorted(facts.apiReferences),
    decisionSurface: sorted(facts.decisionSurface),
    propertyTestSurface: sorted(facts.propertyTestSurface),
    decisionProducts: sorted(facts.decisionProducts),
    decisionReferences: sorted(facts.decisionReferences),
    moduleName: moduleNameFromPath(filePath),
    qualifiedReferences: sorted(facts.qualifiedReferences),
    effectfulImports: sorted(intersection(facts.imports, effectfulImports)),
    effectfulIdentifiers: sorted(intersection(facts.identifiers, effectfulIdentifiers)),
    sharedState: sharedStateFacts(facts.sharedState),
    propertyChecks: facts.propertyChecks,
    interfaceLogicEvidence: facts.interfaceLogicEvidence,
  };
}

function collectQualifiedReferences(facts: Facts, sourceFile: ts.SourceFile, programContext: ProgramContext): void {
  const visit = (node: ts.Node): void => {
    if (ts.isIdentifier(node) && isReferenceIdentifier(node)) {
      const reference = qualifiedReferenceForIdentifier(node, sourceFile, programContext);
      if (reference !== undefined) {
        facts.qualifiedReferences.add(reference);
      }
    }
    ts.forEachChild(node, visit);
  };
  visit(sourceFile);
}

function qualifiedReferenceForIdentifier(
  identifier: ts.Identifier,
  sourceFile: ts.SourceFile,
  programContext: ProgramContext,
): string | undefined {
  const symbol = programContext.checker.getSymbolAtLocation(identifier);
  if (symbol === undefined) {
    return undefined;
  }
  const resolved = (symbol.flags & ts.SymbolFlags.Alias) !== 0 ? programContext.checker.getAliasedSymbol(symbol) : symbol;
  const declaration = resolved.valueDeclaration ?? resolved.declarations?.[0];
  if (declaration === undefined) {
    return undefined;
  }
  const ownerFile = declaration.getSourceFile();
  if (normalizePath(ownerFile.fileName) === normalizePath(sourceFile.fileName)) {
    return undefined;
  }
  if (!programContext.ownedSourceFiles.has(normalizePath(ownerFile.fileName))) {
    return undefined;
  }
  return `${moduleNameFromPath(ownerFile.fileName)}.${resolved.getName()}`;
}

function isReferenceIdentifier(identifier: ts.Identifier): boolean {
  if (isDeclarationName(identifier)) {
    return false;
  }
  const parent = identifier.parent;
  if (parent === undefined) {
    return true;
  }
  if (ts.isPropertyAccessExpression(parent) && parent.name === identifier) {
    return true;
  }
  if (ts.isPropertyAssignment(parent) && parent.name === identifier) {
    return false;
  }
  if (ts.isShorthandPropertyAssignment(parent) && parent.name === identifier) {
    return true;
  }
  if (ts.isImportSpecifier(parent) || ts.isImportClause(parent) || ts.isNamespaceImport(parent) || ts.isImportEqualsDeclaration(parent)) {
    return true;
  }
  if (ts.isExportSpecifier(parent) && parent.name === identifier) {
    return true;
  }
  if (ts.isBindingElement(parent) && parent.propertyName === identifier) {
    return false;
  }
  if (ts.isQualifiedName(parent) && parent.right === identifier) {
    return true;
  }
  return true;
}

function isDeclarationName(identifier: ts.Identifier): boolean {
  const parent = identifier.parent;
  if (parent === undefined) {
    return false;
  }
  if (
    (ts.isFunctionDeclaration(parent)
      || ts.isClassDeclaration(parent)
      || ts.isInterfaceDeclaration(parent)
      || ts.isTypeAliasDeclaration(parent)
      || ts.isEnumDeclaration(parent)
      || ts.isModuleDeclaration(parent)
      || ts.isTypeParameterDeclaration(parent)
      || ts.isParameter(parent)
      || ts.isVariableDeclaration(parent)
      || ts.isMethodDeclaration(parent)
      || ts.isPropertyDeclaration(parent)
      || ts.isEnumMember(parent)) && parent.name === identifier
  ) {
    return true;
  }
  return false;
}

function uniqueGlobalFunctionReferences(files: ParsedFile[]): Map<string, Set<string>> {
  const referencesByName = new Map<string, Set<string>[]>();
  for (const file of files) {
    for (const [name, references] of file.facts.functionReferences) {
      const existing = referencesByName.get(name) ?? [];
      existing.push(references);
      referencesByName.set(name, existing);
    }
  }
  const unique = new Map<string, Set<string>>();
  for (const [name, references] of referencesByName) {
    if (references.length === 1 && references[0] !== undefined) {
      unique.set(name, references[0]);
    }
  }
  return unique;
}

function emptyFacts(): Facts {
  return {
    imports: new Set(),
    identifiers: new Set(),
    apiReferences: new Set(),
    decisionSurface: new Set(),
    propertyTestSurface: new Set(),
    decisionProducts: new Set(),
    decisionReferences: new Set(),
    qualifiedReferences: new Set(),
    effectfulIdentifiers: new Set(),
    sharedState: new Map(),
    propertyChecks: [],
    functionReferences: new Map(),
    functionBodies: new Map(),
    interfaceLogicEvidence: {
      functionBodies: [],
      constructorBodies: [],
      derivedValueBodies: [],
      controlFlow: [],
      imperativeDeclarations: [],
    },
  };
}

function collectTopLevel(facts: Facts, sourceFile: ts.SourceFile): void {
  for (const statement of sourceFile.statements) {
    if (ts.isImportDeclaration(statement)) {
      const specifier = statement.moduleSpecifier;
      if (ts.isStringLiteral(specifier)) {
        facts.imports.add(specifier.text);
      }
      continue;
    }
    if (ts.isExportDeclaration(statement)) {
      const specifier = statement.moduleSpecifier;
      if (specifier !== undefined && ts.isStringLiteral(specifier)) {
        facts.imports.add(specifier.text);
      }
      continue;
    }
    if (ts.isFunctionDeclaration(statement) && statement.name !== undefined) {
      recordFunctionDeclaration(facts, statement);
      continue;
    }
    if (ts.isVariableStatement(statement)) {
      recordVariableStatement(facts, statement, true);
      continue;
    }
    if (ts.isClassDeclaration(statement) && statement.name !== undefined) {
      recordNamedDeclaration(facts, statement.name.text, isExported(statement));
      for (const member of statement.members) {
        if (ts.isConstructorDeclaration(member) && member.body !== undefined) {
          addUnique(facts.interfaceLogicEvidence.constructorBodies, statement.name.text);
        }
        if (ts.isMethodDeclaration(member) && member.name !== undefined) {
          const name = propertyName(member.name);
          if (name !== "" && member.body !== undefined) {
            addUnique(facts.interfaceLogicEvidence.functionBodies, name);
            facts.functionReferences.set(name, apiReferencesInNode(member.body));
          }
        }
      }
      continue;
    }
    if (ts.isInterfaceDeclaration(statement) || ts.isTypeAliasDeclaration(statement) || ts.isEnumDeclaration(statement)) {
      recordNamedDeclaration(facts, statement.name.text, isExported(statement));
    }
  }
}

function recordFunctionDeclaration(facts: Facts, declaration: ts.FunctionDeclaration): void {
  if (declaration.name === undefined) {
    return;
  }
  const name = declaration.name.text;
  recordNamedDeclaration(facts, name, isExported(declaration));
  if (isExported(declaration)) {
    facts.decisionSurface.add(name);
    if (!isInertConstructorFunction(declaration)) {
      facts.propertyTestSurface.add(name);
    }
  }
  if (declaration.body !== undefined) {
    addUnique(facts.interfaceLogicEvidence.functionBodies, name);
    facts.functionReferences.set(name, apiReferencesInNode(declaration.body));
    facts.functionBodies.set(name, declaration);
  }
  recordReturnTypeProducts(facts, declaration.type);
}

function recordVariableStatement(facts: Facts, statement: ts.VariableStatement, topLevel: boolean): void {
  const exported = isExported(statement);
  const mutable = (statement.declarationList.flags & ts.NodeFlags.Const) === 0;
  for (const declaration of statement.declarationList.declarations) {
    for (const name of bindingNames(declaration.name)) {
      facts.identifiers.add(name);
      facts.decisionReferences.add(name);
      if (exported) {
        facts.decisionReferences.add(name);
      }
      if (topLevel && mutable) {
        addSharedState(facts, "typescript-top-level-mutable-binding", name);
      }
      if (declaration.initializer !== undefined && isFunctionLikeExpression(declaration.initializer)) {
        if (exported) {
          facts.decisionSurface.add(name);
          if (!isInertConstructorFunction(declaration.initializer)) {
            facts.propertyTestSurface.add(name);
          }
        }
        addUnique(facts.interfaceLogicEvidence.functionBodies, name);
        facts.functionReferences.set(name, apiReferencesInNode(declaration.initializer));
        facts.functionBodies.set(name, declaration.initializer);
      } else if (declaration.initializer !== undefined && !isLiteralLike(declaration.initializer)) {
        addUnique(facts.interfaceLogicEvidence.derivedValueBodies, name);
        facts.functionReferences.set(name, apiReferencesInNode(declaration.initializer));
      }
    }
  }
}

function recordNamedDeclaration(facts: Facts, name: string, exported: boolean): void {
  facts.identifiers.add(name);
  if (exported) {
    facts.decisionReferences.add(name);
  }
}

function collectNodeFacts(facts: Facts, sourceFile: ts.SourceFile): void {
  const visit = (node: ts.Node): void => {
    if (ts.isIdentifier(node)) {
      facts.identifiers.add(node.text);
      if (effectfulIdentifiers.has(node.text)) {
        facts.effectfulIdentifiers.add(node.text);
      }
    }
    if (ts.isCallExpression(node)) {
      recordCallableReference(facts.apiReferences, node.expression);
      const propertyCheck = propertyCheckForCall(facts, node);
      if (propertyCheck !== undefined) {
        for (const reference of propertyCheck.references) {
          facts.apiReferences.add(reference);
        }
        for (const sequence of propertyCheck.operationSequences) {
          for (const reference of [...sequence.operations, ...sequence.assertions]) {
            facts.apiReferences.add(reference);
          }
        }
        facts.propertyChecks.push(propertyCheck);
      }
    }
    if (ts.isNewExpression(node)) {
      recordCallableReference(facts.apiReferences, node.expression);
    }
    if (ts.isTypeReferenceNode(node)) {
      recordEntityReference(facts.apiReferences, node.typeName);
    }
    if (ts.isIfStatement(node) || ts.isSwitchStatement(node) || ts.isForStatement(node) || ts.isForOfStatement(node) || ts.isForInStatement(node) || ts.isWhileStatement(node) || ts.isDoStatement(node) || ts.isConditionalExpression(node)) {
      addUnique(facts.interfaceLogicEvidence.controlFlow, ts.SyntaxKind[node.kind]);
    }
    if (ts.isVariableStatement(node) && node.parent === sourceFile) {
      // Top-level declarations are handled in the first pass.
    } else if (ts.isVariableStatement(node)) {
      addUnique(facts.interfaceLogicEvidence.imperativeDeclarations, "variable");
    }
    if (ts.isBinaryExpression(node) && isMutationOperator(node.operatorToken.kind)) {
      addUnique(facts.interfaceLogicEvidence.imperativeDeclarations, "mutation");
    }
    ts.forEachChild(node, visit);
  };
  visit(sourceFile);
}

function propertyCheckForCall(facts: Facts, call: ts.CallExpression): PropertyCheckFact | undefined {
  if (!isFastCheckPropertyCall(call.expression) || call.arguments.length === 0) {
    return undefined;
  }
  const callbackExpression = call.arguments[call.arguments.length - 1];
  if (callbackExpression === undefined) {
    return undefined;
  }
  const callback = propertyCallbackForExpression(facts, callbackExpression);
  if (callback === undefined) {
    return undefined;
  }
  const directReferences = call.arguments.reduce(
    (acc, argument) => union(acc, propertyConstructionReferences(facts, argument)),
    new Set<string>(),
  );
  const references = sorted(expandedApiReferences(facts, directReferences, new Set()));
  const generatedInputs = callback.parameters.flatMap((parameter) =>
    bindingNames(parameter.name).map((name) => ({
      name,
      uses: sorted(generatedInputUses(callback.body ?? callback, name)),
    })),
  );
  const operationSequences = operationSequencesForProperty(facts, call, callback, generatedInputs);
  return { references, generatedInputs, operationSequences };
}

function propertyConstructionReferences(facts: Facts, node: ts.Node): Set<string> {
  const references = apiReferencesInNode(node);
  for (const identifier of identifiersInNode(node)) {
    if (facts.functionReferences.has(identifier)) {
      for (const expanded of expandedApiReferences(facts, new Set([identifier]), new Set())) {
        references.add(expanded);
      }
    } else {
      references.add(identifier);
    }
  }
  return references;
}

function identifiersInNode(node: ts.Node): Set<string> {
  const identifiers = new Set<string>();
  const visit = (current: ts.Node): void => {
    if (ts.isIdentifier(current) && !isDeclarationName(current)) {
      identifiers.add(current.text);
    }
    ts.forEachChild(current, visit);
  };
  visit(node);
  return identifiers;
}

function propertyCallbackForExpression(facts: Facts, expression: ts.Expression): ts.FunctionLikeDeclaration | undefined {
  if (isFunctionLikeExpression(expression)) {
    return expression;
  }
  if (ts.isIdentifier(expression)) {
    return facts.functionBodies.get(expression.text);
  }
  if (ts.isCallExpression(expression) && ts.isIdentifier(expression.expression)) {
    const builder = facts.functionBodies.get(expression.expression.text);
    if (builder?.body !== undefined) {
      return returnedFunctionLike(builder.body);
    }
  }
  return undefined;
}

function returnedFunctionLike(node: ts.Node): ts.FunctionLikeDeclaration | undefined {
  let returned: ts.FunctionLikeDeclaration | undefined;
  const visit = (current: ts.Node): void => {
    if (returned !== undefined) {
      return;
    }
    if (ts.isReturnStatement(current) && current.expression !== undefined && isFunctionLikeExpression(current.expression)) {
      returned = current.expression;
      return;
    }
    ts.forEachChild(current, visit);
  };
  visit(node);
  return returned;
}

function isFastCheckPropertyCall(expression: ts.Expression): boolean {
  if (!ts.isPropertyAccessExpression(expression)) {
    return false;
  }
  if (!propertyNames.has(expression.name.text)) {
    return false;
  }
  return expression.expression.getText() === "fc";
}

function operationSequencesForProperty(
  facts: Facts,
  call: ts.CallExpression,
  callback: ts.FunctionLikeDeclaration,
  generatedInputs: GeneratedInputFact[],
): OperationSequenceFact[] {
  const generators = call.arguments.slice(0, -1);
  const assertions = sorted(expandedApiReferences(facts, apiReferencesInNode(callback), new Set()));
  return generatedInputs.flatMap((input, index) => {
    const generator = generators[index];
    if (generator === undefined || !containsOperationSequenceGenerator(generator) || input.uses.length === 0 || assertions.length === 0) {
      return [];
    }
    const operations = sorted(generatedInputApiUses(facts, callback.body ?? callback, input.name));
    if (operations.length === 0) {
      return [];
    }
    return [{ input: input.name, operations, assertions }];
  });
}

function containsOperationSequenceGenerator(node: ts.Node): boolean {
  let found = false;
  const visit = (current: ts.Node): void => {
    if (ts.isPropertyAccessExpression(current) && operationGeneratorNames.has(current.name.text)) {
      found = true;
    }
    if (!found) {
      ts.forEachChild(current, visit);
    }
  };
  visit(node);
  return found;
}

function generatedInputUses(body: ts.Node, name: string): Set<string> {
  return nodeContainsIdentifier(body, name) ? new Set([name]) : new Set();
}

function generatedInputApiUses(facts: Facts, body: ts.Node, name: string): Set<string> {
  const uses = new Set<string>();
  const visit = (node: ts.Node): void => {
    if (ts.isCallExpression(node) && nodeContainsIdentifier(node, name)) {
      for (const reference of expandedApiReferences(facts, apiReferencesInNode(node), new Set())) {
        uses.add(reference);
      }
    }
    ts.forEachChild(node, visit);
  };
  visit(body);
  return uses;
}

function apiReferencesInNode(node: ts.Node): Set<string> {
  const references = new Set<string>();
  const visit = (current: ts.Node): void => {
    if (ts.isCallExpression(current)) {
      recordCallableReference(references, current.expression);
    }
    if (ts.isNewExpression(current)) {
      recordCallableReference(references, current.expression);
    }
    if (ts.isTypeReferenceNode(current)) {
      recordEntityReference(references, current.typeName);
    }
    ts.forEachChild(current, visit);
  };
  visit(node);
  return references;
}

function expandedApiReferences(facts: Facts, references: Set<string>, visited: Set<string>): Set<string> {
  const expanded = new Set<string>();
  for (const reference of references) {
    expanded.add(reference);
    if (visited.has(reference)) {
      continue;
    }
    visited.add(reference);
    const helperReferences = facts.functionReferences.get(reference);
    if (helperReferences !== undefined) {
      for (const helperReference of expandedApiReferences(facts, helperReferences, visited)) {
        expanded.add(helperReference);
      }
    }
  }
  return expanded;
}

function nodeContainsIdentifier(node: ts.Node, name: string): boolean {
  let found = false;
  const visit = (current: ts.Node): void => {
    if (ts.isIdentifier(current) && current.text === name) {
      found = true;
    }
    if (!found) {
      ts.forEachChild(current, visit);
    }
  };
  visit(node);
  return found;
}

function recordCallableReference(references: Set<string>, expression: ts.Expression): void {
  if (ts.isIdentifier(expression)) {
    references.add(expression.text);
  } else if (ts.isPropertyAccessExpression(expression)) {
    references.add(expression.name.text);
    recordEntityReference(references, expression.expression);
  } else if (ts.isElementAccessExpression(expression)) {
    recordEntityReference(references, expression.expression);
  }
}

function recordEntityReference(references: Set<string>, node: ts.Node): void {
  if (ts.isIdentifier(node)) {
    references.add(node.text);
  } else if (ts.isQualifiedName(node)) {
    references.add(node.right.text);
    recordEntityReference(references, node.left);
  } else if (ts.isPropertyAccessExpression(node)) {
    references.add(node.name.text);
    recordEntityReference(references, node.expression);
  }
}

function parseMetadata(source: string): Metadata {
  const metadata: Metadata = { moduleType: "", domain: "", exemptReason: "" };
  const seen = new Set<string>();
  const duplicates = new Set<string>();
  const record = (body: string): void => {
    for (const rawLine of body.split(/\r?\n/u)) {
      const line = rawLine.trim().replace(/^\*\s?/u, "");
      const [tag, value, extra] = line.split(/\s+/u);
      if (extra !== undefined || value === undefined) {
        continue;
      }
      if (tag === "@archlint.module") {
        seen.has(tag) ? duplicates.add(tag) : seen.add(tag);
        metadata.moduleType = value;
      } else if (tag === "@archlint.domain") {
        seen.has(tag) ? duplicates.add(tag) : seen.add(tag);
        metadata.domain = value;
      } else if (tag === "@archlint.exempt-reason") {
        seen.has(tag) ? duplicates.add(tag) : seen.add(tag);
        metadata.exemptReason = value;
      }
    }
  };

  let index = 0;
  if (source.startsWith("#!")) {
    const end = source.indexOf("\n");
    index = end === -1 ? source.length : end + 1;
  }
  while (index < source.length) {
    const rest = source.slice(index);
    const whitespace = rest.match(/^\s+/u);
    if (whitespace !== null) {
      index += whitespace[0].length;
      continue;
    }
    if (source.startsWith("//", index)) {
      const end = source.indexOf("\n", index);
      const stop = end === -1 ? source.length : end;
      record(source.slice(index + 2, stop));
      index = stop + 1;
      continue;
    }
    if (source.startsWith("/*", index)) {
      const end = source.indexOf("*/", index + 2);
      if (end === -1) {
        break;
      }
      record(source.slice(index + 2, end));
      index = end + 2;
      continue;
    }
    break;
  }

  if (duplicates.has("@archlint.module")) {
    metadata.moduleType = "";
  }
  if (duplicates.has("@archlint.domain")) {
    metadata.domain = "";
  }
  if (duplicates.has("@archlint.exempt-reason")) {
    metadata.exemptReason = "";
  }
  return metadata;
}

function inferTestScope(filePath: string, facts: Facts): string {
  if (hasIntersection(facts.imports, testImports)) {
    return path.basename(filePath, path.extname(filePath));
  }
  return "";
}

function recordReturnTypeProducts(facts: Facts, typeNode: ts.TypeNode | undefined): void {
  if (typeNode === undefined) {
    return;
  }
  for (const reference of apiReferencesInNode(typeNode)) {
    facts.decisionProducts.add(reference);
  }
}

function bindingNames(name: ts.BindingName): string[] {
  if (ts.isIdentifier(name)) {
    return [name.text];
  }
  return name.elements.flatMap((element) => {
    if (ts.isBindingElement(element)) {
      return bindingNames(element.name);
    }
    return [];
  });
}

function propertyName(name: ts.PropertyName): string {
  if (ts.isIdentifier(name) || ts.isStringLiteral(name) || ts.isNumericLiteral(name)) {
    return name.text;
  }
  return "";
}

function isExported(node: ts.Node): boolean {
  return ts.canHaveModifiers(node) && (ts.getModifiers(node) ?? []).some((modifier) => modifier.kind === ts.SyntaxKind.ExportKeyword);
}

function isFunctionLikeExpression(node: ts.Node): node is ts.ArrowFunction | ts.FunctionExpression {
  return ts.isArrowFunction(node) || ts.isFunctionExpression(node);
}

function isInertConstructorFunction(node: ts.FunctionLikeDeclaration): boolean {
  const body = node.body;
  if (body === undefined) {
    return false;
  }
  if (ts.isExpression(body)) {
    return isInertConstructorExpression(body);
  }
  if (body.statements.length !== 1) {
    return false;
  }
  const [statement] = body.statements;
  return statement !== undefined
    && ts.isReturnStatement(statement)
    && statement.expression !== undefined
    && isInertConstructorExpression(statement.expression);
}

function isInertConstructorExpression(node: ts.Expression): boolean {
  if (
    ts.isObjectLiteralExpression(node)
    || ts.isArrayLiteralExpression(node)
    || ts.isStringLiteralLike(node)
    || ts.isNumericLiteral(node)
    || ts.isIdentifier(node)
    || node.kind === ts.SyntaxKind.TrueKeyword
    || node.kind === ts.SyntaxKind.FalseKeyword
    || node.kind === ts.SyntaxKind.NullKeyword
  ) {
    return true;
  }
  if (ts.isParenthesizedExpression(node) || ts.isAsExpression(node) || ts.isSatisfiesExpression(node)) {
    return isInertConstructorExpression(node.expression);
  }
  return false;
}

function isLiteralLike(node: ts.Expression): boolean {
  return ts.isStringLiteralLike(node) || ts.isNumericLiteral(node) || node.kind === ts.SyntaxKind.TrueKeyword || node.kind === ts.SyntaxKind.FalseKeyword || node.kind === ts.SyntaxKind.NullKeyword || ts.isArrayLiteralExpression(node) || ts.isObjectLiteralExpression(node);
}

function isMutationOperator(kind: ts.SyntaxKind): boolean {
  return kind === ts.SyntaxKind.EqualsToken || kind === ts.SyntaxKind.PlusEqualsToken || kind === ts.SyntaxKind.MinusEqualsToken || kind === ts.SyntaxKind.AsteriskEqualsToken || kind === ts.SyntaxKind.SlashEqualsToken;
}

function addSharedState(facts: Facts, kind: string, reference: string): void {
  const references = facts.sharedState.get(kind) ?? new Set<string>();
  references.add(reference);
  facts.sharedState.set(kind, references);
}

function sharedStateFacts(evidence: Map<string, Set<string>>): SharedStateFact[] {
  return [...evidence.entries()].map(([kind, references]) => ({ kind, references: sorted(references) })).sort((left, right) => left.kind.localeCompare(right.kind));
}

function intersection(left: Set<string>, right: Set<string>): Set<string> {
  return new Set([...left].filter((value) => right.has(value)));
}

function union(left: Set<string>, right: Set<string>): Set<string> {
  const values = new Set(left);
  for (const value of right) {
    values.add(value);
  }
  return values;
}

function hasIntersection(left: Set<string>, right: Set<string>): boolean {
  for (const value of left) {
    if (right.has(value)) {
      return true;
    }
  }
  return false;
}

function addUnique(values: string[], value: string): void {
  if (value !== "" && !values.includes(value)) {
    values.push(value);
  }
}

function sorted(values: Iterable<string>): string[] {
  return [...new Set(values)].filter((value) => value !== "").sort();
}

function normalizePath(filePath: string): string {
  return path.resolve(filePath);
}

main();
