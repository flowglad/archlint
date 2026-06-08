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
  interfaceLogicEvidence: InterfaceLogicEvidence;
};

type ParsedFile = {
  filePath: string;
  source: string;
  sourceFile: ts.SourceFile;
  facts: Facts;
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
  const args = parseArgs(process.argv.slice(2));
  const repoRoot = path.resolve(args.get("--repo-root") ?? ".");
  const root = path.resolve(repoRoot, args.get("--typescript-root") ?? ".");
  const files = sourceFiles(root);
  const parsedFiles = files.map(parseSourceFacts);
  const globalFunctionReferences = uniqueGlobalFunctionReferences(parsedFiles);
  const facts = parsedFiles.map((file) => sourceFact(file, globalFunctionReferences));
  process.stdout.write(`${JSON.stringify({ files: facts })}\n`);
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

function parseSourceFacts(filePath: string): ParsedFile {
  const source = readFileSync(filePath, "utf8");
  const sourceFile = ts.createSourceFile(filePath, source, ts.ScriptTarget.Latest, true);
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

function sourceFact(file: ParsedFile, globalFunctionReferences: Map<string, Set<string>>): SourceFact {
  const { filePath, source, sourceFile, facts } = file;
  for (const [name, references] of globalFunctionReferences) {
    if (!facts.functionReferences.has(name)) {
      facts.functionReferences.set(name, references);
    }
  }
  collectNodeFacts(facts, sourceFile);
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
      } else if (declaration.initializer !== undefined && !isLiteralLike(declaration.initializer)) {
        addUnique(facts.interfaceLogicEvidence.derivedValueBodies, name);
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
  const callback = call.arguments[call.arguments.length - 1];
  if (callback === undefined || !isFunctionLikeExpression(callback)) {
    return undefined;
  }
  const references = sorted(expandedApiReferences(facts, apiReferencesInNode(callback), new Set()));
  const generatedInputs = callback.parameters.flatMap((parameter) =>
    bindingNames(parameter.name).map((name) => ({
      name,
      uses: sorted(generatedInputUses(callback.body ?? callback, name)),
    })),
  );
  const operationSequences = operationSequencesForProperty(facts, call, callback, generatedInputs);
  return { references, generatedInputs, operationSequences };
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

main();
