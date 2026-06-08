import { existsSync, realpathSync, readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
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

type EffectfulReferenceFact = {
  kind: string;
  category: string;
  reference: string;
  origin: string;
  enclosingIdentifier: string;
  packageName: string;
  summaryId: string;
  receiverType: string;
  evidence: string[];
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
  effectfulReferences: EffectfulReferenceFact[];
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
  effectfulReferences: Map<string, EffectfulReferenceFact>;
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
  dependencySummaries: DependencySummary[];
  workspacePackageRoots: Set<string>;
};

type LocalCallGraph = {
  functionReferences: Map<string, Set<string>>;
  effectfulFunctions: Map<string, EffectfulReferenceFact[]>;
};

type DependencySummaryDocument = {
  dependencies: DependencySummary[];
};

type DependencySummary = {
  packageName: string;
  versionRange: string;
  rules: DependencyEffectRule[];
};

type DependencyEffectRule = {
  id: string;
  effectCategory: string;
  receiverTypeNames: string[];
  memberPaths: string[];
  evidence: string[];
};

type EffectRequirementClassification = {
  category: string;
  reference: string;
  packageName: string;
  summaryId: string;
  receiverType: string;
  evidence: string;
};

const sourceExtensions = new Set([".ts", ".tsx", ".mts", ".cts"]);
const ignoredDirectories = new Set(["node_modules", "dist", "build", "coverage", ".git"]);

const effectfulImports = new Set([
  "bun",
  "child_process",
  "commander",
  "fs",
  "node:cluster",
  "node:child_process",
  "node:dgram",
  "node:dns",
  "node:dns/promises",
  "node:fs",
  "node:fs/promises",
  "node:http",
  "node:https",
  "node:inspector",
  "node:net",
  "node:os",
  "node:path",
  "node:process",
  "node:readline",
  "node:readline/promises",
  "node:sqlite",
  "node:stream",
  "node:timers",
  "node:timers/promises",
  "node:tls",
  "node:tty",
  "node:url",
  "node:worker_threads",
  "process",
]);

const effectfulBindingImports = new Set([
  "bun",
  "child_process",
  "fs",
  "node:cluster",
  "node:child_process",
  "node:dgram",
  "node:dns",
  "node:dns/promises",
  "node:fs",
  "node:fs/promises",
  "node:http",
  "node:https",
  "node:inspector",
  "node:net",
  "node:process",
  "node:readline",
  "node:readline/promises",
  "node:sqlite",
  "node:timers",
  "node:timers/promises",
  "node:tls",
  "node:tty",
  "node:worker_threads",
  "process",
]);

const effectfulIdentifiers = new Set([
  "Bun",
  "Command",
  "BroadcastChannel",
  "Deno",
  "EventSource",
  "console",
  "caches",
  "clearImmediate",
  "clearInterval",
  "clearTimeout",
  "crypto",
  "document",
  "fetch",
  "File",
  "indexedDB",
  "localStorage",
  "navigator",
  "process",
  "queueMicrotask",
  "readFile",
  "readFileSync",
  "sessionStorage",
  "setImmediate",
  "setInterval",
  "setTimeout",
  "SharedWorker",
  "WebSocket",
  "window",
  "Worker",
  "writeFile",
  "writeFileSync",
  "XMLHttpRequest",
]);

const effectfulImportCategories = new Map([
  ["bun", "process"],
  ["child_process", "process"],
  ["commander", "process"],
  ["fs", "filesystem"],
  ["node:cluster", "process"],
  ["node:child_process", "process"],
  ["node:dgram", "network"],
  ["node:dns", "network"],
  ["node:dns/promises", "network"],
  ["node:fs", "filesystem"],
  ["node:fs/promises", "filesystem"],
  ["node:http", "network"],
  ["node:https", "network"],
  ["node:inspector", "process"],
  ["node:net", "network"],
  ["node:process", "process"],
  ["node:readline", "process"],
  ["node:readline/promises", "process"],
  ["node:sqlite", "filesystem"],
  ["node:timers", "timer"],
  ["node:timers/promises", "timer"],
  ["node:tls", "network"],
  ["node:tty", "process"],
  ["node:worker_threads", "process"],
  ["process", "process"],
]);

const effectfulIdentifierCategories = new Map([
  ["Bun", "process"],
  ["Command", "process"],
  ["BroadcastChannel", "browser"],
  ["Deno", "process"],
  ["EventSource", "network"],
  ["console", "console"],
  ["caches", "storage"],
  ["clearImmediate", "timer"],
  ["clearInterval", "timer"],
  ["clearTimeout", "timer"],
  ["crypto", "unknown"],
  ["document", "browser"],
  ["fetch", "network"],
  ["File", "filesystem"],
  ["indexedDB", "storage"],
  ["localStorage", "storage"],
  ["navigator", "browser"],
  ["process", "process"],
  ["queueMicrotask", "timer"],
  ["readFile", "filesystem"],
  ["readFileSync", "filesystem"],
  ["sessionStorage", "storage"],
  ["setImmediate", "timer"],
  ["setInterval", "timer"],
  ["setTimeout", "timer"],
  ["SharedWorker", "browser"],
  ["WebSocket", "network"],
  ["window", "browser"],
  ["Worker", "browser"],
  ["writeFile", "filesystem"],
  ["writeFileSync", "filesystem"],
  ["XMLHttpRequest", "network"],
]);

const testImports = new Set(["bun:test", "node:test", "fast-check"]);
const propertyNames = new Set(["property", "asyncProperty"]);
const operationGeneratorNames = new Set(["array", "uniqueArray"]);

const effectRequirementClassifications = new Map<string, EffectRequirementClassification>([
  [
    "@effect/sql:SqlClient",
    {
      category: "database",
      reference: "SqlClient.SqlClient",
      packageName: "@effect/sql",
      summaryId: "effect-requirement-sqlclient",
      receiverType: "SqlClient",
      evidence: "Effect requirement channel includes @effect/sql SqlClient.SqlClient",
    },
  ],
  [
    "@effect/sql-pg:PgClient",
    {
      category: "database",
      reference: "PgClient.PgClient",
      packageName: "@effect/sql-pg",
      summaryId: "effect-requirement-pgclient",
      receiverType: "PgClient",
      evidence: "Effect requirement channel includes @effect/sql-pg PgClient.PgClient",
    },
  ],
  [
    "effect:Clock",
    {
      category: "timer",
      reference: "Clock.Clock",
      packageName: "effect",
      summaryId: "effect-requirement-clock",
      receiverType: "Clock",
      evidence: "Effect requirement channel includes effect Clock.Clock",
    },
  ],
  [
    "effect:Random",
    {
      category: "unknown",
      reference: "Random.Random",
      packageName: "effect",
      summaryId: "effect-requirement-random",
      receiverType: "Random",
      evidence: "Effect requirement channel includes effect Random.Random",
    },
  ],
  [
    "effect:Scope",
    {
      category: "unknown",
      reference: "Scope.Scope",
      packageName: "effect",
      summaryId: "effect-requirement-scope",
      receiverType: "Scope",
      evidence: "Effect requirement channel includes effect Scope.Scope",
    },
  ],
]);

const effectRunnerMemberPaths = new Set([
  "runCallback",
  "runFork",
  "runPromise",
  "runPromiseExit",
  "runRequestBlock",
  "runSync",
  "runSyncExit",
]);

const effectConstructorMemberPaths = new Set([
  "async",
  "promise",
  "suspend",
  "sync",
  "tryPromise",
]);

function main(): void {
  try {
    const args = parseArgs(process.argv.slice(2));
    const repoRoot = path.resolve(args.get("--repo-root") ?? ".");
    const root = path.resolve(repoRoot, args.get("--typescript-root") ?? ".");
    const files = sourceFiles(root);
    const programContext = buildProgram(files, root, repoRoot, loadDependencySummaries());
    const parsedFiles = files.map((filePath) => parseSourceFacts(filePath, programContext));
    const localCallGraph = collectLocalCallGraph(programContext);
    const globalFunctionReferences = uniqueGlobalFunctionReferences(parsedFiles);
    const facts = parsedFiles.map((file) => sourceFact(file, globalFunctionReferences, localCallGraph, programContext));
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

function loadDependencySummaries(): DependencySummary[] {
  const adapterRoot = path.dirname(fileURLToPath(import.meta.url));
  const summaryPath = path.resolve(adapterRoot, "../dependency-summaries/npm.json");
  const document = JSON.parse(readFileSync(summaryPath, "utf8")) as DependencySummaryDocument;
  return document.dependencies;
}

function buildProgram(
  filePaths: string[],
  root: string,
  repoRoot: string,
  dependencySummaries: DependencySummary[],
): ProgramContext {
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
    dependencySummaries,
    workspacePackageRoots: discoverWorkspacePackageRoots(repoRoot),
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

function discoverWorkspacePackageRoots(repoRoot: string): Set<string> {
  const packageJsonPath = path.join(repoRoot, "package.json");
  if (!existsSync(packageJsonPath)) {
    return new Set();
  }
  const packageJson = JSON.parse(readFileSync(packageJsonPath, "utf8")) as {
    workspaces?: unknown;
  };
  const workspacePatterns = workspacePatternsFromPackageJson(packageJson.workspaces);
  if (workspacePatterns.length === 0) {
    return new Set();
  }
  const roots = new Set<string>();
  for (const pattern of workspacePatterns) {
    for (const directory of expandWorkspacePattern(repoRoot, pattern)) {
      const childPackageJson = path.join(directory, "package.json");
      if (existsSync(childPackageJson)) {
        roots.add(realNormalizePath(directory));
      }
    }
  }
  return roots;
}

function workspacePatternsFromPackageJson(workspaces: unknown): string[] {
  if (Array.isArray(workspaces)) {
    return workspaces.filter((value): value is string => typeof value === "string");
  }
  if (workspaces !== null && typeof workspaces === "object" && "packages" in workspaces) {
    const packages = (workspaces as { packages?: unknown }).packages;
    if (Array.isArray(packages)) {
      return packages.filter((value): value is string => typeof value === "string");
    }
  }
  return [];
}

function expandWorkspacePattern(repoRoot: string, pattern: string): string[] {
  const segments = pattern.split(/[\\/]+/u).filter((segment) => segment !== "");
  const results: string[] = [];
  const visit = (directory: string, index: number): void => {
    if (index >= segments.length) {
      results.push(directory);
      return;
    }
    const segment = segments[index];
    if (segment === undefined) {
      return;
    }
    if (segment === "*") {
      for (const entry of safeReadDirectories(directory)) {
        visit(path.join(directory, entry), index + 1);
      }
      return;
    }
    if (segment === "**") {
      visit(directory, index + 1);
      for (const entry of safeReadDirectories(directory)) {
        visit(path.join(directory, entry), index);
      }
      return;
    }
    visit(path.join(directory, segment), index + 1);
  };
  visit(repoRoot, 0);
  return results;
}

function safeReadDirectories(directory: string): string[] {
  if (!existsSync(directory)) {
    return [];
  }
  return readdirSync(directory, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && !ignoredDirectories.has(entry.name))
    .map((entry) => entry.name)
    .sort();
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
  collectTopLevel(facts, sourceFile, programContext);
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

function sourceFact(
  file: ParsedFile,
  globalFunctionReferences: Map<string, Set<string>>,
  localCallGraph: LocalCallGraph,
  programContext: ProgramContext,
): SourceFact {
  const { filePath, source, sourceFile, facts } = file;
  for (const [name, references] of globalFunctionReferences) {
    if (!facts.functionReferences.has(name)) {
      facts.functionReferences.set(name, references);
    }
  }
  for (const [name, references] of localCallGraph.functionReferences) {
    if (!facts.functionReferences.has(name)) {
      facts.functionReferences.set(name, references);
    }
  }
  collectNodeFacts(facts, sourceFile, programContext);
  expandEffectfulIdentifiers(facts, localCallGraph.effectfulFunctions);
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
    effectfulIdentifiers: sorted(facts.effectfulIdentifiers),
    effectfulReferences: effectfulReferenceFacts(facts.effectfulReferences),
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
    effectfulReferences: new Map(),
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

function collectLocalCallGraph(programContext: ProgramContext): LocalCallGraph {
  const functionReferences = new Map<string, Set<string>>();
  const effectfulFunctions = new Map<string, EffectfulReferenceFact[]>();
  for (const sourceFile of localProgramSourceFiles(programContext)) {
    const facts = emptyFacts();
    collectTopLevel(facts, sourceFile, programContext);
    collectNodeFacts(facts, sourceFile, programContext);
    for (const [name, references] of facts.functionReferences) {
      functionReferences.set(qualifiedLocalReference(sourceFile, name), references);
    }
    expandEffectfulIdentifiers(facts, new Map());
    for (const identifier of facts.effectfulIdentifiers) {
      const qualified = qualifiedLocalReference(sourceFile, identifier);
      effectfulFunctions.set(qualified, effectfulReferenceFactsForIdentifier(facts, identifier));
    }
  }
  return { functionReferences, effectfulFunctions };
}

function localProgramSourceFiles(programContext: ProgramContext): ts.SourceFile[] {
  return programContext.program.getSourceFiles().filter((sourceFile) =>
    !sourceFile.isDeclarationFile
    && !normalizePath(sourceFile.fileName).includes(`${path.sep}node_modules${path.sep}`)
    && sourceExtensions.has(path.extname(sourceFile.fileName))
  );
}

function qualifiedLocalReference(sourceFile: ts.SourceFile, name: string): string {
  return `${moduleNameFromPath(sourceFile.fileName)}.${name}`;
}

function collectTopLevel(facts: Facts, sourceFile: ts.SourceFile, programContext: ProgramContext): void {
  for (const statement of sourceFile.statements) {
    if (ts.isImportDeclaration(statement)) {
      const specifier = statement.moduleSpecifier;
      if (ts.isStringLiteral(specifier)) {
        facts.imports.add(specifier.text);
        if (effectfulImports.has(specifier.text)) {
          addEffectfulReference(facts, {
            kind: "import",
            category: effectfulImportCategories.get(specifier.text) ?? "unknown",
            reference: specifier.text,
            origin: "standard-library",
            enclosingIdentifier: "",
            packageName: "",
            summaryId: "",
            receiverType: "",
            evidence: [`effectful import root: ${specifier.text}`],
          });
        }
        if (!statement.importClause?.isTypeOnly && effectfulBindingImports.has(specifier.text)) {
          for (const name of importBindingNames(statement.importClause)) {
            facts.effectfulIdentifiers.add(name);
          }
        }
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
      recordFunctionDeclaration(facts, statement, sourceFile, programContext);
      continue;
    }
    if (ts.isVariableStatement(statement)) {
      recordVariableStatement(facts, statement, true, sourceFile, programContext);
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
            facts.functionReferences.set(name, apiReferencesInNode(member.body, sourceFile, programContext));
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

function importBindingNames(importClause: ts.ImportClause | undefined): string[] {
  if (importClause === undefined) {
    return [];
  }
  const names: string[] = [];
  if (importClause.name !== undefined) {
    names.push(importClause.name.text);
  }
  const namedBindings = importClause.namedBindings;
  if (namedBindings === undefined) {
    return names;
  }
  if (ts.isNamespaceImport(namedBindings)) {
    names.push(namedBindings.name.text);
    return names;
  }
  for (const element of namedBindings.elements) {
    if (!element.isTypeOnly) {
      names.push(element.name.text);
    }
  }
  return names;
}

function recordFunctionDeclaration(
  facts: Facts,
  declaration: ts.FunctionDeclaration,
  sourceFile: ts.SourceFile,
  programContext: ProgramContext,
): void {
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
    facts.functionReferences.set(name, apiReferencesInNode(declaration.body, sourceFile, programContext));
    facts.functionBodies.set(name, declaration);
  }
  recordReturnTypeProducts(facts, declaration.type);
}

function recordVariableStatement(
  facts: Facts,
  statement: ts.VariableStatement,
  topLevel: boolean,
  sourceFile: ts.SourceFile,
  programContext: ProgramContext,
): void {
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
        facts.functionReferences.set(name, apiReferencesInNode(declaration.initializer, sourceFile, programContext));
        facts.functionBodies.set(name, declaration.initializer);
      } else if (declaration.initializer !== undefined && !isLiteralLike(declaration.initializer)) {
        addUnique(facts.interfaceLogicEvidence.derivedValueBodies, name);
        facts.functionReferences.set(name, apiReferencesInNode(declaration.initializer, sourceFile, programContext));
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

function collectNodeFacts(facts: Facts, sourceFile: ts.SourceFile, programContext: ProgramContext): void {
  const visit = (node: ts.Node): void => {
    if (ts.isFunctionDeclaration(node) && node.name !== undefined) {
      recordEffectRequirementsForFunction(facts, node, programContext);
    }
    if (ts.isMethodDeclaration(node) && node.name !== undefined) {
      recordEffectRequirementsForFunction(facts, node, programContext);
    }
    if (ts.isVariableDeclaration(node)) {
      recordEffectRequirementsForVariable(facts, node, programContext);
    }
    if (ts.isIdentifier(node)) {
      facts.identifiers.add(node.text);
      if (effectfulIdentifiers.has(node.text)) {
        facts.effectfulIdentifiers.add(node.text);
        addEffectfulReference(facts, {
          kind: "identifier",
          category: effectfulIdentifierCategories.get(node.text) ?? "unknown",
          reference: node.text,
          origin: "global",
          enclosingIdentifier: enclosingIdentifier(node),
          packageName: "",
          summaryId: "",
          receiverType: "",
          evidence: [`effectful global identifier: ${node.text}`],
        });
      }
    }
    if (ts.isCallExpression(node)) {
      recordCallableReference(facts.apiReferences, node.expression);
      recordLocalCallableReference(facts.apiReferences, node.expression, sourceFile, programContext);
      recordDependencyEffectfulReference(facts, node, node.expression, "call", programContext);
      recordEffectRequirementsForExpression(facts, node, programContext, "call");
      recordEffectRequirementsForRunnerArgument(facts, node, programContext);
      recordEffectRunnerArgumentReferences(facts, node, sourceFile, programContext);
      recordEffectConstructorCallbackReferences(facts, node, sourceFile, programContext);
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
      recordLocalCallableReference(facts.apiReferences, node.expression, sourceFile, programContext);
      recordDependencyEffectfulReference(facts, node, node.expression, "new", programContext);
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

function expandEffectfulIdentifiers(facts: Facts, localEffectfulFunctions: Map<string, EffectfulReferenceFact[]>): void {
  let changed = true;
  while (changed) {
    changed = false;
    for (const [name, references] of facts.functionReferences) {
      if (!facts.identifiers.has(name) || facts.effectfulIdentifiers.has(name)) {
        continue;
      }
      const expandedReferences = expandedApiReferences(facts, references, new Set());
      const reachedLocalEffects = reachedLocalEffectfulReferences(expandedReferences, localEffectfulFunctions);
      if (hasIntersection(expandedReferences, facts.effectfulIdentifiers) || reachedLocalEffects.length > 0) {
        facts.effectfulIdentifiers.add(name);
        for (const reached of reachedLocalEffects) {
          addEffectfulReference(facts, {
            kind: "call",
            category: reached.effect.category,
            reference: reached.reference,
            origin: "local-call-expansion",
            enclosingIdentifier: name,
            packageName: reached.effect.packageName,
            summaryId: reached.effect.summaryId,
            receiverType: reached.effect.receiverType,
            evidence: sorted([
              `local call expansion reached ${reached.reference}`,
              ...reached.effect.evidence,
            ]),
          });
        }
        changed = true;
      }
    }
  }
}

function reachedLocalEffectfulReferences(
  expandedReferences: Set<string>,
  localEffectfulFunctions: Map<string, EffectfulReferenceFact[]>,
): { reference: string; effect: EffectfulReferenceFact }[] {
  const reached: { reference: string; effect: EffectfulReferenceFact }[] = [];
  for (const reference of expandedReferences) {
    const effects = localEffectfulFunctions.get(reference);
    if (effects === undefined) {
      continue;
    }
    for (const effect of effects) {
      reached.push({ reference, effect });
    }
  }
  return reached;
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

function apiReferencesInNode(
  node: ts.Node,
  sourceFile?: ts.SourceFile,
  programContext?: ProgramContext,
): Set<string> {
  const references = new Set<string>();
  const visit = (current: ts.Node): void => {
    if (ts.isCallExpression(current)) {
      recordCallableReference(references, current.expression);
      if (sourceFile !== undefined && programContext !== undefined) {
        recordLocalCallableReference(references, current.expression, sourceFile, programContext);
      }
    }
    if (ts.isNewExpression(current)) {
      recordCallableReference(references, current.expression);
      if (sourceFile !== undefined && programContext !== undefined) {
        recordLocalCallableReference(references, current.expression, sourceFile, programContext);
      }
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

function recordLocalCallableReference(
  references: Set<string>,
  expression: ts.Expression,
  sourceFile: ts.SourceFile,
  programContext: ProgramContext,
): void {
  const reference = localCallableReference(expression, sourceFile, programContext);
  if (reference !== undefined) {
    references.add(reference);
  }
}

function localCallableReference(
  expression: ts.Expression,
  sourceFile: ts.SourceFile,
  programContext: ProgramContext,
): string | undefined {
  const symbolNode = ts.isPropertyAccessExpression(expression) ? expression.name : expression;
  const symbol = programContext.checker.getSymbolAtLocation(symbolNode);
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
  if (
    !relativeImportTargetFiles(sourceFile).has(normalizePath(ownerFile.fileName))
    && !isWorkspaceSourceFile(ownerFile, programContext)
  ) {
    return undefined;
  }
  return qualifiedLocalReference(ownerFile, resolved.getName());
}

function isWorkspaceSourceFile(sourceFile: ts.SourceFile, programContext: ProgramContext): boolean {
  return workspacePackageRootForFile(sourceFile.fileName, programContext) !== undefined;
}

function workspacePackageRootForFile(filePath: string, programContext: ProgramContext): string | undefined {
  let current = realNormalizePath(filePath);
  if (!existsSync(current) || path.extname(current) !== "") {
    current = path.dirname(current);
  }
  while (current !== path.dirname(current)) {
    if (programContext.workspacePackageRoots.has(current)) {
      return current;
    }
    current = path.dirname(current);
  }
  return undefined;
}

const relativeImportTargetFileCache = new Map<string, Set<string>>();

function relativeImportTargetFiles(sourceFile: ts.SourceFile): Set<string> {
  const sourcePath = normalizePath(sourceFile.fileName);
  const cached = relativeImportTargetFileCache.get(sourcePath);
  if (cached !== undefined) {
    return cached;
  }
  const targets = new Set<string>();
  for (const statement of sourceFile.statements) {
    if (!ts.isImportDeclaration(statement) && !ts.isExportDeclaration(statement)) {
      continue;
    }
    const specifier = statement.moduleSpecifier;
    if (specifier === undefined || !ts.isStringLiteral(specifier) || !specifier.text.startsWith(".")) {
      continue;
    }
    const resolved = resolveLocalModuleSpecifier(path.dirname(sourceFile.fileName), specifier.text);
    if (resolved !== undefined) {
      targets.add(normalizePath(resolved));
    }
  }
  relativeImportTargetFileCache.set(sourcePath, targets);
  return targets;
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

function recordDependencyEffectfulReference(
  facts: Facts,
  node: ts.Node,
  expression: ts.Expression,
  kind: string,
  programContext: ProgramContext,
): void {
  const chain = propertyAccessPrefixes(expression);
  if (chain.length < 2) {
    return;
  }
  const fullSegments = chain[chain.length - 1]?.segments ?? [];
  for (let index = 0; index < chain.length - 1; index += 1) {
    const prefix = chain[index];
    if (prefix === undefined) {
      continue;
    }
    const memberPath = fullSegments.slice(prefix.segments.length).join(".");
    if (memberPath === "") {
      continue;
    }
    const typeInfo = dependencyTypeInfo(prefix.node, programContext);
    if (typeInfo === undefined) {
      continue;
    }
    for (const summary of programContext.dependencySummaries) {
      if (summary.packageName !== typeInfo.packageName) {
        continue;
      }
      for (const rule of summary.rules) {
        if (!rule.memberPaths.includes(memberPath) || !receiverTypeMatches(typeInfo.typeNames, rule.receiverTypeNames)) {
          continue;
        }
        const enclosing = enclosingIdentifier(node);
        addEffectfulReference(facts, {
          kind,
          category: rule.effectCategory,
          reference: memberPath,
          origin: "dependency-summary",
          enclosingIdentifier: enclosing,
          packageName: summary.packageName,
          summaryId: rule.id,
          receiverType: sorted(typeInfo.typeNames)[0] ?? "",
          evidence: rule.evidence,
        });
        if (enclosing !== "") {
          facts.effectfulIdentifiers.add(enclosing);
        }
      }
    }
  }
}

function recordEffectRequirementsForFunction(
  facts: Facts,
  declaration: ts.FunctionDeclaration | ts.MethodDeclaration,
  programContext: ProgramContext,
): void {
  const signature = programContext.checker.getSignatureFromDeclaration(declaration);
  if (signature === undefined) {
    return;
  }
  recordEffectRequirementsFromType(
    facts,
    declaration,
    programContext.checker.getReturnTypeOfSignature(signature),
    programContext,
    "identifier",
    "function return type",
  );
}

function recordEffectRequirementsForVariable(
  facts: Facts,
  declaration: ts.VariableDeclaration,
  programContext: ProgramContext,
): void {
  recordEffectRequirementsFromType(
    facts,
    declaration,
    programContext.checker.getTypeAtLocation(declaration.name),
    programContext,
    "identifier",
    "variable type",
  );
  if (declaration.initializer !== undefined) {
    recordEffectRequirementsFromType(
      facts,
      declaration,
      programContext.checker.getTypeAtLocation(declaration.initializer),
      programContext,
      "identifier",
      "variable initializer type",
    );
  }
}

function recordEffectRequirementsForExpression(
  facts: Facts,
  expression: ts.Expression,
  programContext: ProgramContext,
  kind: string,
): void {
  recordEffectRequirementsFromType(
    facts,
    expression,
    programContext.checker.getTypeAtLocation(expression),
    programContext,
    kind,
    "expression type",
  );
}

function recordEffectRequirementsForRunnerArgument(
  facts: Facts,
  call: ts.CallExpression,
  programContext: ProgramContext,
): void {
  if (!isEffectRunnerCall(call.expression, programContext)) {
    return;
  }
  const executed = call.arguments[0];
  if (executed === undefined) {
    return;
  }
  recordEffectRequirementsFromType(
    facts,
    call,
    programContext.checker.getTypeAtLocation(executed),
    programContext,
    "call",
    "executed deferred computation type",
  );
}

function recordEffectRunnerArgumentReferences(
  facts: Facts,
  call: ts.CallExpression,
  sourceFile: ts.SourceFile,
  programContext: ProgramContext,
): void {
  if (!isEffectRunnerCall(call.expression, programContext)) {
    return;
  }
  const executed = call.arguments[0];
  if (executed === undefined) {
    return;
  }
  addReferencesToEnclosingIdentifier(
    facts,
    call,
    expressionAsApiReferences(executed, sourceFile, programContext),
  );
}

function isEffectRunnerCall(expression: ts.Expression, programContext: ProgramContext): boolean {
  return isEffectNamespaceMemberCall(expression, effectRunnerMemberPaths, programContext);
}

function recordEffectConstructorCallbackReferences(
  facts: Facts,
  call: ts.CallExpression,
  sourceFile: ts.SourceFile,
  programContext: ProgramContext,
): void {
  if (!isEffectConstructorCall(call.expression, programContext)) {
    return;
  }
  const callbackReferences = unionAll(
    effectConstructorCallbackExpressions(call).map((expression) =>
      expressionAsApiReferences(expression, sourceFile, programContext),
    ),
  );
  addReferencesToEnclosingIdentifier(facts, call, callbackReferences);
}

function isEffectConstructorCall(expression: ts.Expression, programContext: ProgramContext): boolean {
  return isEffectNamespaceMemberCall(expression, effectConstructorMemberPaths, programContext);
}

function isEffectNamespaceMemberCall(
  expression: ts.Expression,
  memberNames: Set<string>,
  programContext: ProgramContext,
): boolean {
  if (!ts.isPropertyAccessExpression(expression) || !memberNames.has(expression.name.text)) {
    return false;
  }
  const typeInfo = dependencyTypeInfo(expression.expression, programContext);
  return typeInfo?.packageName === "effect" && typeInfo.typeNames.has("Effect");
}

function effectConstructorCallbackExpressions(call: ts.CallExpression): ts.Expression[] {
  const memberName = ts.isPropertyAccessExpression(call.expression) ? call.expression.name.text : "";
  const first = call.arguments[0];
  if (first === undefined) {
    return [];
  }
  if (memberName === "tryPromise" && ts.isObjectLiteralExpression(first)) {
    return first.properties.flatMap((property) => {
      if (!ts.isPropertyAssignment(property) || propertyName(property.name) !== "try") {
        return [];
      }
      return [property.initializer];
    });
  }
  return [first];
}

function expressionAsApiReferences(
  expression: ts.Expression,
  sourceFile: ts.SourceFile,
  programContext: ProgramContext,
): Set<string> {
  if (isFunctionLikeExpression(expression)) {
    return apiReferencesInNode(expression.body ?? expression, sourceFile, programContext);
  }
  const references = new Set<string>();
  recordCallableReference(references, expression);
  recordLocalCallableReference(references, expression, sourceFile, programContext);
  return references;
}

function addReferencesToEnclosingIdentifier(facts: Facts, node: ts.Node, references: Set<string>): void {
  if (references.size === 0) {
    return;
  }
  const enclosing = enclosingIdentifier(node);
  if (enclosing === "") {
    return;
  }
  const existing = facts.functionReferences.get(enclosing) ?? new Set<string>();
  for (const reference of references) {
    existing.add(reference);
  }
  facts.functionReferences.set(enclosing, existing);
}

function unionAll(sets: Set<string>[]): Set<string> {
  const values = new Set<string>();
  for (const set of sets) {
    for (const value of set) {
      values.add(value);
    }
  }
  return values;
}

function recordEffectRequirementsFromType(
  facts: Facts,
  node: ts.Node,
  type: ts.Type,
  programContext: ProgramContext,
  kind: string,
  evidenceContext: string,
): void {
  const enclosing = enclosingIdentifier(node);
  if (enclosing === "") {
    return;
  }
  for (const classification of classifiedEffectRequirements(type, programContext.checker, new Set())) {
    addEffectfulReference(facts, {
      kind,
      category: classification.category,
      reference: classification.reference,
      origin: "dependency-summary",
      enclosingIdentifier: enclosing,
      packageName: classification.packageName,
      summaryId: classification.summaryId,
      receiverType: classification.receiverType,
      evidence: [`${evidenceContext}: ${classification.evidence}`],
    });
    facts.effectfulIdentifiers.add(enclosing);
  }
}

function classifiedEffectRequirements(
  type: ts.Type,
  checker: ts.TypeChecker,
  visited: Set<number>,
): EffectRequirementClassification[] {
  const id = typeId(type);
  if (id !== undefined) {
    if (visited.has(id)) {
      return [];
    }
    visited.add(id);
  }
  const requirements = effectRequirementTypes(type, checker);
  const classifications = requirements.flatMap((requirement) =>
    classifiedRequirementTypes(requirement, checker, visited),
  );
  return uniqueClassifications(classifications);
}

function effectRequirementTypes(type: ts.Type, checker: ts.TypeChecker): ts.Type[] {
  const requirements: ts.Type[] = [];
  collectEffectRequirementTypes(type, checker, requirements, new Set());
  return requirements;
}

function collectEffectRequirementTypes(
  type: ts.Type,
  checker: ts.TypeChecker,
  requirements: ts.Type[],
  visited: Set<number>,
): void {
  const id = typeId(type);
  if (id !== undefined) {
    if (visited.has(id)) {
      return;
    }
    visited.add(id);
  }
  if (type.isUnionOrIntersection()) {
    for (const subtype of type.types) {
      collectEffectRequirementTypes(subtype, checker, requirements, visited);
    }
  }
  const reference = typeReferenceInfo(type, checker);
  if (reference === undefined) {
    return;
  }
  if (reference.packageName === "effect" && reference.typeName === "Effect") {
    const requirement = reference.typeArguments[2];
    if (requirement !== undefined && !isEmptyRequirementType(requirement)) {
      requirements.push(requirement);
    }
  }
  if (reference.packageName === "effect" && reference.typeName === "Layer") {
    const requirement = reference.typeArguments[2];
    if (requirement !== undefined && !isEmptyRequirementType(requirement)) {
      requirements.push(requirement);
    }
  }
}

function classifiedRequirementTypes(
  type: ts.Type,
  checker: ts.TypeChecker,
  visited: Set<number>,
): EffectRequirementClassification[] {
  const id = typeId(type);
  if (id !== undefined) {
    if (visited.has(id)) {
      return [];
    }
    visited.add(id);
  }
  if (isEmptyRequirementType(type)) {
    return [];
  }
  if (type.isUnionOrIntersection()) {
    return uniqueClassifications(type.types.flatMap((subtype) => classifiedRequirementTypes(subtype, checker, visited)));
  }
  const classifications: EffectRequirementClassification[] = [];
  for (const symbol of symbolsForType(type, checker)) {
    const packageName = packageNameForSymbol(symbol);
    if (packageName === undefined) {
      continue;
    }
    const key = `${packageName}:${symbol.getName()}`;
    const classification = effectRequirementClassifications.get(key);
    if (classification !== undefined) {
      classifications.push(classification);
    }
  }
  return uniqueClassifications(classifications);
}

function uniqueClassifications(classifications: EffectRequirementClassification[]): EffectRequirementClassification[] {
  const byKey = new Map<string, EffectRequirementClassification>();
  for (const classification of classifications) {
    byKey.set(`${classification.packageName}:${classification.summaryId}:${classification.reference}`, classification);
  }
  return [...byKey.values()];
}

function typeReferenceInfo(
  type: ts.Type,
  checker: ts.TypeChecker,
): { packageName: string; typeName: string; typeArguments: readonly ts.Type[] } | undefined {
  for (const candidate of [type, checker.getApparentType(type)]) {
    const symbol = candidate.aliasSymbol ?? candidate.symbol;
    if (symbol === undefined) {
      continue;
    }
    const packageName = packageNameForSymbol(symbol);
    if (packageName === undefined) {
      continue;
    }
    const typeArguments = typeReferenceArguments(candidate, checker);
    return {
      packageName,
      typeName: symbol.getName(),
      typeArguments,
    };
  }
  return undefined;
}

function typeReferenceArguments(type: ts.Type, checker: ts.TypeChecker): readonly ts.Type[] {
  if ((type.flags & ts.TypeFlags.Object) === 0) {
    return [];
  }
  const objectType = type as ts.ObjectType;
  if ((objectType.objectFlags & ts.ObjectFlags.Reference) === 0) {
    return [];
  }
  return checker.getTypeArguments(objectType as ts.TypeReference);
}

function symbolsForType(type: ts.Type, checker: ts.TypeChecker): ts.Symbol[] {
  return [
    type.aliasSymbol,
    type.symbol,
    checker.getApparentType(type).aliasSymbol,
    checker.getApparentType(type).symbol,
  ].filter(isDefined);
}

function packageNameForSymbol(symbol: ts.Symbol): string | undefined {
  const declaration = symbol.valueDeclaration ?? symbol.declarations?.[0];
  if (declaration === undefined) {
    return undefined;
  }
  return packageNameForFile(declaration.getSourceFile().fileName);
}

function isEmptyRequirementType(type: ts.Type): boolean {
  return (type.flags & (ts.TypeFlags.Never | ts.TypeFlags.Any | ts.TypeFlags.Unknown)) !== 0;
}

function typeId(type: ts.Type): number | undefined {
  return (type as { id?: number }).id;
}

function propertyAccessPrefixes(expression: ts.Expression): { node: ts.Expression; segments: string[] }[] {
  if (ts.isIdentifier(expression)) {
    return [{ node: expression, segments: [expression.text] }];
  }
  if (ts.isPropertyAccessExpression(expression)) {
    const prefixes = propertyAccessPrefixes(expression.expression);
    const previous = prefixes[prefixes.length - 1];
    if (previous === undefined) {
      return [];
    }
    return [...prefixes, { node: expression, segments: [...previous.segments, expression.name.text] }];
  }
  return [];
}

function dependencyTypeInfo(
  expression: ts.Expression,
  programContext: ProgramContext,
): { packageName: string; typeNames: Set<string> } | undefined {
  const type = programContext.checker.getTypeAtLocation(expression);
  const declarations = declarationsForType(type, programContext.checker);
  const packageNames = new Set(declarations.map((declaration) => packageNameForFile(declaration.getSourceFile().fileName)).filter(isDefined));
  for (const packageName of packageNamesForExpressionSymbol(expression, programContext)) {
    packageNames.add(packageName);
  }
  if (packageNames.size === 0) {
    return undefined;
  }
  const typeNames = typeNamesForType(type, programContext.checker);
  const symbolName = expressionSymbolName(expression, programContext);
  if (symbolName !== undefined) {
    typeNames.add(symbolName);
  }
  for (const packageName of packageNames) {
    return { packageName, typeNames };
  }
  return undefined;
}

function packageNamesForExpressionSymbol(expression: ts.Expression, programContext: ProgramContext): Set<string> {
  const packageNames = new Set<string>();
  const symbol = expressionSymbol(expression, programContext);
  if (symbol === undefined) {
    return packageNames;
  }
  for (const declaration of symbol.declarations ?? []) {
    const packageName = packageNameForFile(declaration.getSourceFile().fileName);
    if (packageName !== undefined) {
      packageNames.add(packageName);
    }
  }
  return packageNames;
}

function expressionSymbolName(expression: ts.Expression, programContext: ProgramContext): string | undefined {
  return expressionSymbol(expression, programContext)?.getName();
}

function expressionSymbol(expression: ts.Expression, programContext: ProgramContext): ts.Symbol | undefined {
  const symbol = programContext.checker.getSymbolAtLocation(expression);
  if (symbol === undefined) {
    return undefined;
  }
  return (symbol.flags & ts.SymbolFlags.Alias) !== 0 ? programContext.checker.getAliasedSymbol(symbol) : symbol;
}

function declarationsForType(type: ts.Type, checker: ts.TypeChecker): ts.Declaration[] {
  const symbols = [
    type.symbol,
    type.aliasSymbol,
    checker.getApparentType(type).symbol,
    checker.getApparentType(type).aliasSymbol,
  ].filter(isDefined);
  return symbols.flatMap((symbol) => symbol.declarations ?? []);
}

function typeNamesForType(type: ts.Type, checker: ts.TypeChecker): Set<string> {
  const names = new Set<string>();
  for (const symbol of [
    type.symbol,
    type.aliasSymbol,
    checker.getApparentType(type).symbol,
    checker.getApparentType(type).aliasSymbol,
  ]) {
    if (symbol !== undefined) {
      names.add(symbol.getName());
    }
  }
  names.add(stripTypeArguments(checker.typeToString(type)));
  names.add(stripTypeArguments(checker.typeToString(checker.getApparentType(type))));
  return names;
}

function stripTypeArguments(value: string): string {
  return value.replace(/<.*$/u, "");
}

const packageNameByDirectory = new Map<string, string | undefined>();

function packageNameForFile(filePath: string): string | undefined {
  let current = path.dirname(filePath);
  while (current !== path.dirname(current)) {
    if (packageNameByDirectory.has(current)) {
      return packageNameByDirectory.get(current);
    }
    const packageJsonPath = path.join(current, "package.json");
    if (existsSync(packageJsonPath)) {
      const packageJson = JSON.parse(readFileSync(packageJsonPath, "utf8")) as { name?: unknown };
      const packageName = typeof packageJson.name === "string" ? packageJson.name : undefined;
      if (packageName !== undefined) {
        packageNameByDirectory.set(current, packageName);
        return packageName;
      }
    }
    current = path.dirname(current);
  }
  return undefined;
}

function enclosingIdentifier(node: ts.Node): string {
  let current: ts.Node | undefined = node;
  while (current !== undefined) {
    if (ts.isFunctionDeclaration(current) && current.name !== undefined) {
      return current.name.text;
    }
    if (ts.isMethodDeclaration(current) && current.name !== undefined) {
      return propertyName(current.name);
    }
    if (ts.isVariableDeclaration(current) && ts.isIdentifier(current.name) && isBoundaryVariableDeclaration(current)) {
      return current.name.text;
    }
    current = current.parent;
  }
  return "";
}

function isBoundaryVariableDeclaration(node: ts.VariableDeclaration): boolean {
  if (node.initializer !== undefined && isFunctionLikeExpression(node.initializer)) {
    return true;
  }
  return ts.isVariableDeclarationList(node.parent)
    && ts.isVariableStatement(node.parent.parent)
    && ts.isSourceFile(node.parent.parent.parent);
}

function addEffectfulReference(facts: Facts, fact: EffectfulReferenceFact): void {
  facts.effectfulReferences.set(effectfulReferenceKey(fact), {
    ...fact,
    evidence: sorted(fact.evidence),
  });
}

function effectfulReferenceKey(fact: EffectfulReferenceFact): string {
  return [
    fact.kind,
    fact.category,
    fact.reference,
    fact.origin,
    fact.enclosingIdentifier,
    fact.packageName,
    fact.summaryId,
    fact.receiverType,
    ...fact.evidence,
  ].join("\u0000");
}

function effectfulReferenceFacts(facts: Map<string, EffectfulReferenceFact>): EffectfulReferenceFact[] {
  return [...facts.values()].sort((left, right) => effectfulReferenceKey(left).localeCompare(effectfulReferenceKey(right)));
}

function effectfulReferenceFactsForIdentifier(facts: Facts, identifier: string): EffectfulReferenceFact[] {
  return effectfulReferenceFacts(facts.effectfulReferences).filter((fact) => fact.enclosingIdentifier === identifier);
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

function hasAnyString(left: Set<string>, right: string[]): boolean {
  for (const value of right) {
    if (left.has(value)) {
      return true;
    }
  }
  return false;
}

function receiverTypeMatches(typeNames: Set<string>, receiverTypeNames: string[]): boolean {
  return receiverTypeNames.length === 0 || hasAnyString(typeNames, receiverTypeNames);
}

function isDefined<T>(value: T | undefined): value is T {
  return value !== undefined;
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

function realNormalizePath(filePath: string): string {
  try {
    return path.resolve(realpathSync(filePath));
  } catch {
    return path.resolve(filePath);
  }
}

main();
