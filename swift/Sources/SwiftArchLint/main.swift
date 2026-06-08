import Foundation
import IndexStoreDB
import SwiftParser
import SwiftSyntax
import Yams

struct Violation: Comparable {
  let path: String
  let message: String

  static func < (left: Violation, right: Violation) -> Bool {
    if left.path == right.path {
      return left.message < right.message
    }
    return left.path < right.path
  }
}

struct SwiftFileInfo {
  let url: URL
  let source: String
  let moduleName: String
  let metadata: ModuleMetadata
  let imports: Set<String>
  let identifiers: Set<String>
  let apiReferences: Set<String>
  let qualifiedReferences: Set<String>
  let decisionReferences: Set<String>
  let decisionSurface: Set<String>
  let propertyTestSurface: Set<String>
  let decisionProducts: Set<String>
  let interfaceLogicEvidence: InterfaceLogicEvidence
  let sharedState: [SharedStateFact]
  let propertyChecks: [PropertyCheckFact]

  func withQualifiedReferences(_ references: Set<String>) -> SwiftFileInfo {
    SwiftFileInfo(
      url: url,
      source: source,
      moduleName: moduleName,
      metadata: metadata,
      imports: imports,
      identifiers: identifiers,
      apiReferences: apiReferences,
      qualifiedReferences: references,
      decisionReferences: decisionReferences,
      decisionSurface: decisionSurface,
      propertyTestSurface: propertyTestSurface,
      decisionProducts: decisionProducts,
      interfaceLogicEvidence: interfaceLogicEvidence,
      sharedState: sharedState,
      propertyChecks: propertyChecks
    )
  }
}

struct SwiftTarget {
  let name: String
  let sourceRoots: [URL]
  let isTestScope: Bool
}

struct XcodeGenProject: Decodable {
  let targets: [String: XcodeGenTarget]
}

struct XcodeGenTarget: Decodable {
  let type: String
  let sources: [XcodeGenSource]
  let dependencies: [XcodeGenDependency]

  enum CodingKeys: String, CodingKey {
    case type
    case sources
    case dependencies
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
    sources = try container.decodeIfPresent([XcodeGenSource].self, forKey: .sources) ?? []
    dependencies =
      try container.decodeIfPresent([XcodeGenDependency].self, forKey: .dependencies) ?? []
  }
}

struct XcodeGenSource: Decodable {
  let path: String

  init(from decoder: Decoder) throws {
    let singleValue = try decoder.singleValueContainer()
    if let path = try? singleValue.decode(String.self) {
      self.path = path
      return
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    path = try container.decode(String.self, forKey: .path)
  }

  private enum CodingKeys: String, CodingKey {
    case path
  }
}

struct XcodeGenDependency: Decodable {
  let target: String

  init(from decoder: Decoder) throws {
    let singleValue = try decoder.singleValueContainer()
    if let target = try? singleValue.decode(String.self) {
      self.target = target
      return
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    target = try container.decodeIfPresent(String.self, forKey: .target) ?? ""
  }

  private enum CodingKeys: String, CodingKey {
    case target
  }
}

struct ModuleMetadata {
  let moduleType: String
  let domain: String
  let exemptReason: String
}

struct ArchitectureFacts: Encodable {
  let files: [SourceFact]
}

struct SourceFact: Encodable {
  let path: String
  let testScope: String
  let metadata: MetadataFact
  let imports: [String]
  let identifiers: [String]
  let apiReferences: [String]
  let decisionSurface: [String]
  let propertyTestSurface: [String]
  let decisionProducts: [String]
  let decisionReferences: [String]
  let moduleName: String
  let qualifiedReferences: [String]
  let effectfulImports: [String]
  let effectfulIdentifiers: [String]
  let sharedState: [SharedStateFact]
  let propertyChecks: [PropertyCheckFact]
  let interfaceLogicEvidence: InterfaceLogicEvidence
}

struct SharedStateFact: Encodable {
  let kind: String
  let references: [String]
}

struct PropertyCheckFact: Encodable {
  let references: [String]
  let generatedInputs: [GeneratedInputFact]
  let operationSequences: [OperationSequenceFact]
}

struct GeneratedInputFact: Encodable {
  let name: String
  let uses: [String]
}

struct OperationSequenceFact: Encodable {
  let input: String
  let operations: [String]
  let assertions: [String]
}

struct MetadataFact: Encodable {
  let moduleType: String
  let domain: String
  let exemptReason: String
}

struct InterfaceLogicEvidence: Encodable {
  var functionBodies: [String] = []
  var constructorBodies: [String] = []
  var derivedValueBodies: [String] = []
  var controlFlow: [String] = []
  var imperativeDeclarations: [String] = []

  mutating func recordFunctionBody(_ reference: String) {
    appendUnique(reference, to: &functionBodies)
  }

  mutating func recordInitializerBody(_ reference: String) {
    appendUnique(reference, to: &constructorBodies)
  }

  mutating func recordComputedProperty(_ reference: String) {
    appendUnique(reference, to: &derivedValueBodies)
  }

  mutating func recordControlFlow(_ reference: String) {
    appendUnique(reference, to: &controlFlow)
  }

  private func appendUnique(_ reference: String, to references: inout [String]) {
    if !reference.isEmpty && !references.contains(reference) {
      references.append(reference)
    }
  }
}

@main
enum SwiftArchLint {
  static func main() throws {
    let repoRoot: URL =
      try argumentValue(named: "--repo-root")
      .map(URL.init(fileURLWithPath:))
      .map { path in
        URL(
          fileURLWithPath: path.path,
          relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        )
        .standardizedFileURL
      }
      ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    guard let xcodegenPath: String = try argumentValue(named: "--xcodegen") else {
      throw ArchLintError.missingRequiredArgument("--xcodegen")
    }
    let xcodegenURL: URL =
      xcodegenPath.hasPrefix("/")
      ? URL(fileURLWithPath: xcodegenPath).standardizedFileURL
      : repoRoot.appending(path: xcodegenPath).standardizedFileURL
    let facts: ArchitectureFacts = try architectureFacts(xcodegenURL: xcodegenURL)
    let encoder: JSONEncoder = JSONEncoder()
    let output: Data = try encoder.encode(facts)
    FileHandle.standardOutput.write(output)
    FileHandle.standardOutput.write(Data("\n".utf8))
  }

  private static func argumentValue(named name: String) throws -> String? {
    var arguments: ArraySlice<String> = ArraySlice(CommandLine.arguments.dropFirst())
    while let argument: String = arguments.popFirst() {
      if argument == name {
        guard let value: String = arguments.popFirst() else {
          throw ArchLintError.missingArgumentValue(name)
        }
        return value
      }
    }
    return nil
  }

  private static func architectureFacts(xcodegenURL: URL) throws -> ArchitectureFacts {
    let targets: [SwiftTarget] = try swiftTargets(xcodegenURL: xcodegenURL)
    let fileInfosWithScopes: [(SwiftFileInfo, String)] = try targets.flatMap { target in
      try target.sourceRoots.flatMap { root in
        try swiftFileInfos(root: root).map {
          ($0, target.isTestScope ? target.name : "")
        }
      }
    }
    let qualifiedReferencesByPath: [String: Set<String>] = try semanticQualifiedReferences(
      for: fileInfosWithScopes.map(\.0),
      indexableRoots: targets.filter { !$0.isTestScope }.flatMap(\.sourceRoots)
    )
    let files: [SourceFact] = fileInfosWithScopes.map { fileInfo, testScope in
      let semanticReferences: Set<String> = qualifiedReferencesByPath[fileInfo.url.path] ?? []
      return sourceFact(
        fileInfo.withQualifiedReferences(semanticReferences),
        testScope: testScope
      )
    }
    return ArchitectureFacts(files: files)
  }

  private static func swiftTargets(xcodegenURL: URL) throws -> [SwiftTarget] {
    let manifest: String = try String(contentsOf: xcodegenURL, encoding: .utf8)
    let project: XcodeGenProject = try YAMLDecoder().decode(XcodeGenProject.self, from: manifest)
    let manifestDirectory: URL = xcodegenURL.deletingLastPathComponent()
    return project.targets.keys.sorted().compactMap { targetName in
      guard let target: XcodeGenTarget = project.targets[targetName] else {
        return nil
      }
      let sourceRoots: [URL] = target.sources.map { source in
        URL(fileURLWithPath: source.path, relativeTo: manifestDirectory).standardizedFileURL
      }
      return SwiftTarget(
        name: targetName,
        sourceRoots: sourceRoots,
        isTestScope: isTestScope(target)
      )
    }
  }

  private static func isTestScope(_ target: XcodeGenTarget) -> Bool {
    if target.type.lowercased().contains("test") {
      return true
    }
    return target.dependencies.contains { dependency in
      dependency.target.lowercased().contains("test")
    }
  }

  private static func swiftFileInfos(root: URL) throws -> [SwiftFileInfo] {
    guard
      let enumerator: FileManager.DirectoryEnumerator =
        FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
    else {
      return []
    }
    return try enumerator.compactMap { item in
      guard let fileURL: URL = item as? URL, fileURL.pathExtension == "swift" else {
        return nil
      }
      return try swiftFileInfo(fileURL)
    }
  }

  private static func swiftFileInfo(_ fileURL: URL) throws -> SwiftFileInfo {
    let canonicalFileURL: URL = fileURL.standardizedFileURL.resolvingSymlinksInPath()
    let source: String = try String(contentsOf: canonicalFileURL, encoding: .utf8)
    let tree: SourceFileSyntax = Parser.parse(source: source)
    let metadata: ModuleMetadata = parseModuleMetadata(source)
    let functionBodyVisitor: FunctionBodyVisitor = FunctionBodyVisitor(viewMode: .sourceAccurate)
    functionBodyVisitor.walk(tree)
    let visitor: ArchitectureVisitor = ArchitectureVisitor(
      functionBodiesByName: functionBodyVisitor.functionBodiesByName,
      viewMode: .sourceAccurate
    )
    visitor.walk(tree)

    return SwiftFileInfo(
      url: canonicalFileURL,
      source: source,
      moduleName: capitalizedModuleName(for: canonicalFileURL),
      metadata: metadata,
      imports: Set(visitor.importedModules),
      identifiers: Set(visitor.identifiers),
      apiReferences: Set(visitor.apiReferences),
      qualifiedReferences: [],
      decisionReferences: Set(visitor.decisionReferences),
      decisionSurface: Set(visitor.decisionSurface),
      propertyTestSurface: Set(visitor.propertyTestSurface),
      decisionProducts: Set(visitor.decisionProducts),
      interfaceLogicEvidence: visitor.interfaceLogicEvidence,
      sharedState: visitor.sharedStateFacts,
      propertyChecks: metadata.moduleType == "stateTest"
        ? visitor.propertyChecks
        : visitor.propertyChecks.map { check in
          PropertyCheckFact(
            references: check.references,
            generatedInputs: check.generatedInputs,
            operationSequences: []
          )
        }
    )
  }

  private static func semanticQualifiedReferences(
    for fileInfos: [SwiftFileInfo],
    indexableRoots: [URL]
  ) throws -> [String: Set<String>] {
    let indexedFiles: [URL] = try indexableSwiftFiles(in: indexableRoots)
    if indexedFiles.isEmpty {
      return [:]
    }

    let temporaryRoot: URL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "archlint-swift-index-\(UUID().uuidString)",
      isDirectory: true
    )
    let sourceCopies: URL = temporaryRoot.appending(path: "sources", directoryHint: .isDirectory)
    let indexStore: URL = temporaryRoot.appending(path: "index-store", directoryHint: .isDirectory)
    let indexDatabase: URL = temporaryRoot.appending(path: "index-db", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: temporaryRoot,
      withIntermediateDirectories: true
    )
    defer {
      try? FileManager.default.removeItem(at: temporaryRoot)
    }

    try buildIndexStore(for: indexedFiles, sourceCopies: sourceCopies, indexStore: indexStore)

    let library: IndexStoreLibrary = try IndexStoreLibrary(dylibPath: try indexStoreLibraryPath())
    let index: IndexStoreDB = try IndexStoreDB(
      storePath: indexStore.path,
      databasePath: indexDatabase.path,
      library: library,
      waitUntilDoneInitializing: true,
      prefixMappings: [
        PathMapping(original: sourceCopies.path + "/", replacement: "/")
      ]
    )
    index.pollForUnitChangesAndWait(isInitialScan: true)
    var analyzedFileByPath: [String: SwiftFileInfo] = [:]
    for fileInfo: SwiftFileInfo in fileInfos {
      analyzedFileByPath[fileInfo.url.path] = fileInfo
      analyzedFileByPath[privateVarAlias(fileInfo.url.path)] = fileInfo
      analyzedFileByPath[varAlias(fileInfo.url.path)] = fileInfo
    }
    var qualifiedReferencesByPath: [String: Set<String>] = [:]
    for fileURL: URL in indexedFiles {
      let filePath: String = fileURL.path
      guard let sourceFile: SwiftFileInfo = analyzedFileByPath[filePath] else {
        continue
      }
      let occurrences: [SymbolOccurrence] = uniqueOccurrences(
        [filePath, privateVarAlias(filePath), varAlias(filePath)].flatMap {
          index.symbolOccurrences(inFilePath: $0)
        }
      )
      for occurrence: SymbolOccurrence in occurrences {
        guard (occurrence.roles.contains(.reference) || occurrence.roles.contains(.call)),
          occurrence.symbol.language == .swift,
          !occurrence.location.isSystem
        else {
          continue
        }
        for definition: SymbolOccurrence in index.occurrences(
          ofUSR: occurrence.symbol.usr,
          roles: [.definition, .declaration]
        ) {
          let ownerPath: String = definition.location.path
          guard analyzedFileByPath[ownerPath]?.url.path != sourceFile.url.path,
            let ownerFile: SwiftFileInfo = analyzedFileByPath[ownerPath]
          else {
            continue
          }
          let symbolName: String = referenceSymbolName(occurrence.symbol.name)
          if !symbolName.isEmpty {
            qualifiedReferencesByPath[sourceFile.url.path, default: []].insert(
              "\(ownerFile.moduleName).\(symbolName)"
            )
          }
        }
      }
    }
    return qualifiedReferencesByPath
  }

  private static func indexableSwiftFiles(in roots: [URL]) throws -> [URL] {
    var files: Set<URL> = []
    for root: URL in roots {
      guard
        let enumerator: FileManager.DirectoryEnumerator =
          FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
      else {
        continue
      }
      for item in enumerator {
        guard let fileURL: URL = item as? URL, fileURL.pathExtension == "swift" else {
          continue
        }
        files.insert(fileURL.standardizedFileURL.resolvingSymlinksInPath())
      }
    }
    return files.sorted { $0.path < $1.path }
  }

  private static func buildIndexStore(
    for files: [URL],
    sourceCopies: URL?,
    indexStore: URL
  ) throws {
    let swiftcPath: String = try developerToolPath("swiftc")
    let compileFiles: [URL]
    if let sourceCopies {
      compileFiles = try files.map { fileURL in
        let relativePath: String = fileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let copiedURL: URL = sourceCopies.appending(path: relativePath)
        try FileManager.default.createDirectory(
          at: copiedURL.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        let source: String = try String(contentsOf: fileURL, encoding: .utf8)
        try "import Foundation\n\(source)".write(to: copiedURL, atomically: true, encoding: .utf8)
        return copiedURL
      }
    } else {
      compileFiles = files
    }
    var buildOutput: String = ""
    for (index, indexedFile) in compileFiles.enumerated() {
      var arguments: [String] = [
        "-typecheck",
        "-parse-as-library",
        "-continue-building-after-errors",
        "-module-name",
        "ArchLintIndexedSources",
        "-index-store-path",
        indexStore.path,
        "-index-file",
        "-index-file-path",
        indexedFile.path,
        "-index-unit-output-path",
        "archlint-index-\(index).o",
      ]
      arguments.append(indexedFile.path)
      arguments.append(contentsOf: compileFiles.filter { $0 != indexedFile }.map(\.path))
      let output: String = try runProcess(
        executable: swiftcPath,
        arguments: arguments,
        failureMessage: "swift index build failed",
        allowNonZeroExit: true
      )
      if !output.isEmpty {
        buildOutput.append(output)
        buildOutput.append("\n")
      }
    }
    guard containsIndexRecords(at: indexStore) else {
      throw ArchLintError.semanticIndexUnavailable("swift index build failed: \(buildOutput)")
    }
  }

  private static func indexStoreLibraryPath() throws -> String {
    let toolchainRoot: URL = URL(fileURLWithPath: try developerToolPath("swiftc"))
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let libraryPath: String = toolchainRoot.appending(path: "lib/libIndexStore.dylib").path
    guard FileManager.default.fileExists(atPath: libraryPath) else {
      throw ArchLintError.semanticIndexUnavailable("missing libIndexStore.dylib at \(libraryPath)")
    }
    return libraryPath
  }

  private static func developerToolPath(_ toolName: String) throws -> String {
    let output: String = try runProcess(
      executable: "/usr/bin/xcrun",
      arguments: ["--find", toolName],
      failureMessage: "unable to locate \(toolName)"
    )
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  @discardableResult
  private static func runProcess(
    executable: String,
    arguments: [String],
    failureMessage: String,
    allowNonZeroExit: Bool = false
  ) throws -> String {
    let process: Process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let outputPipe: Pipe = Pipe()
    let errorPipe: Pipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      throw ArchLintError.semanticIndexUnavailable("\(failureMessage): \(error)")
    }
    let output: String = String(
      data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
      encoding: .utf8
    ) ?? ""
    let errorOutput: String = String(
      data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
      encoding: .utf8
    ) ?? ""
    let combinedOutput: String = [output, errorOutput]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
    guard process.terminationStatus == 0 || allowNonZeroExit else {
      throw ArchLintError.semanticIndexUnavailable(
        "\(failureMessage): \(combinedOutput)"
      )
    }
    return combinedOutput
  }

  private static func containsIndexRecords(at indexStore: URL) -> Bool {
    guard
      let enumerator: FileManager.DirectoryEnumerator =
        FileManager.default.enumerator(at: indexStore, includingPropertiesForKeys: [.isRegularFileKey])
    else {
      return false
    }
    for item in enumerator {
      guard let fileURL: URL = item as? URL else {
        continue
      }
      let parentName: String = fileURL.deletingLastPathComponent().lastPathComponent
      let grandparentName: String = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .lastPathComponent
      if parentName == "units" || grandparentName == "records" {
        return true
      }
    }
    return false
  }

  private static func referenceSymbolName(_ name: String) -> String {
    if let parenIndex: String.Index = name.firstIndex(of: "(") {
      return String(name[..<parenIndex])
    }
    return name
  }

  private static func uniqueOccurrences(_ occurrences: [SymbolOccurrence]) -> [SymbolOccurrence] {
    var seen: Set<String> = []
    var result: [SymbolOccurrence] = []
    for occurrence: SymbolOccurrence in occurrences {
      let key: String = [
        occurrence.location.path,
        String(occurrence.location.line),
        String(occurrence.location.utf8Column),
        occurrence.symbol.usr,
        String(occurrence.roles.rawValue),
      ].joined(separator: "|")
      if seen.insert(key).inserted {
        result.append(occurrence)
      }
    }
    return result
  }

  private static func privateVarAlias(_ path: String) -> String {
    if path.hasPrefix("/var/") {
      return "/private\(path)"
    }
    return path
  }

  private static func varAlias(_ path: String) -> String {
    if path.hasPrefix("/private/var/") {
      return String(path.dropFirst("/private".count))
    }
    return path
  }

  private static func parseModuleMetadata(_ source: String) -> ModuleMetadata {
    var moduleType: String = ""
    var domain: String = ""
    var exemptReason: String = ""
    var seenModuleType: Bool = false
    var seenDomain: Bool = false
    var seenExemptReason: Bool = false
    var duplicateModuleType: Bool = false
    var duplicateDomain: Bool = false
    var duplicateExemptReason: Bool = false
    for line: Substring in source.split(separator: "\n", omittingEmptySubsequences: false) {
      let trimmedLine: String = line.trimmingCharacters(in: .whitespaces)
      if trimmedLine.isEmpty {
        continue
      }
      guard trimmedLine.hasPrefix("//") else {
        break
      }
      let trimmed: String = String(trimmedLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
      let fields: [Substring] = trimmed.split(separator: " ")
      guard fields.count == 2 else {
        continue
      }
      switch fields[0] {
      case "@archlint.module":
        if seenModuleType {
          duplicateModuleType = true
        }
        seenModuleType = true
        moduleType = String(fields[1])
      case "@archlint.domain":
        if seenDomain {
          duplicateDomain = true
        }
        seenDomain = true
        domain = String(fields[1])
      case "@archlint.exempt-reason":
        if seenExemptReason {
          duplicateExemptReason = true
        }
        seenExemptReason = true
        exemptReason = String(fields[1])
      default:
        continue
      }
    }
    if duplicateModuleType {
      moduleType = ""
    }
    if duplicateDomain {
      domain = ""
    }
    if duplicateExemptReason {
      exemptReason = ""
    }
    return ModuleMetadata(moduleType: moduleType, domain: domain, exemptReason: exemptReason)
  }

  private static func capitalizedModuleName(for fileURL: URL) -> String {
    let basename: String = fileURL.deletingPathExtension().lastPathComponent
    guard let firstCharacter: Character = basename.first else {
      return basename
    }
    return String(firstCharacter).uppercased() + basename.dropFirst()
  }

  private static func sourceFact(_ fileInfo: SwiftFileInfo, testScope: String)
    -> SourceFact
  {
    return SourceFact(
      path: fileInfo.url.path,
      testScope: testScope,
      metadata: MetadataFact(
        moduleType: fileInfo.metadata.moduleType,
        domain: fileInfo.metadata.domain,
        exemptReason: fileInfo.metadata.exemptReason
      ),
      imports: fileInfo.imports.sorted(),
      identifiers: fileInfo.identifiers.sorted(),
      apiReferences: fileInfo.apiReferences.sorted(),
      decisionSurface: fileInfo.decisionSurface.sorted(),
      propertyTestSurface: fileInfo.propertyTestSurface.sorted(),
      decisionProducts: fileInfo.decisionProducts.sorted(),
      decisionReferences: fileInfo.decisionReferences.sorted(),
      moduleName: fileInfo.moduleName,
      qualifiedReferences: fileInfo.qualifiedReferences.sorted(),
      effectfulImports: fileInfo.imports.intersection(effectfulModules).sorted(),
      effectfulIdentifiers: fileInfo.identifiers.intersection(effectfulTypes).sorted(),
      sharedState: fileInfo.sharedState,
      propertyChecks: fileInfo.propertyChecks,
      interfaceLogicEvidence: fileInfo.interfaceLogicEvidence
    )
  }

  private static let effectfulModules: Set<String> = [
    "Combine",
    "CryptoKit",
    "GRDB",
    "Network",
    "Security",
    "SwiftUI",
    "UIKit",
  ]

  private static let effectfulTypes: Set<String> = [
    "HTTPURLResponse",
    "URLRequest",
    "URLSession",
    "UserDefaults",
  ]
}

final class ArchitectureVisitor: SyntaxVisitor {
  private(set) var importedModules: [String] = []
  private(set) var identifiers: [String] = []
  private(set) var apiReferences: [String] = []
  private(set) var qualifiedReferences: [String] = []
  private(set) var decisionReferences: [String] = []
  private(set) var decisionSurface: [String] = []
  private(set) var propertyTestSurface: [String] = []
  private(set) var decisionProducts: [String] = []
  private(set) var interfaceLogicEvidence: InterfaceLogicEvidence = InterfaceLogicEvidence()
  private var sharedStateByKind: [String: Set<String>] = [:]
  private(set) var propertyChecks: [PropertyCheckFact] = []
  private let functionBodiesByName: [String: CodeBlockSyntax]

  init(functionBodiesByName: [String: CodeBlockSyntax], viewMode: SyntaxTreeViewMode) {
    self.functionBodiesByName = functionBodiesByName
    super.init(viewMode: viewMode)
  }

  override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
    if let importedModule: String = node.path.first?.name.text {
      importedModules.append(importedModule)
    }
    return .skipChildren
  }

  override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
    let name: String = node.name.text
    recordIdentifier(name)
    if name == "DatabaseQueue" {
      recordSharedState(kind: "swift-database-queue", reference: "DatabaseQueue")
    }
    return .visitChildren
  }

  override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
    let name: String = node.baseName.text
    recordIdentifier(name)
    return .visitChildren
  }

  override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
    if let baseReference: DeclReferenceExprSyntax = node.base?.as(DeclReferenceExprSyntax.self) {
      recordAPIReference(baseReference.baseName.text)
      recordAPIReference(node.declName.baseName.text)
      // A type-qualified member access (e.g. HTTPClient.send) is recorded in
      // Base.member form so the dependency-direction rule matches a genuine
      // cross-type reach. Bare references within the single Swift module cannot
      // be attributed and are intentionally not recorded here.
      qualifiedReferences.append("\(baseReference.baseName.text).\(node.declName.baseName.text)")
    }
    if node.declName.baseName.text == "standard",
      let baseReference: DeclReferenceExprSyntax = node.base?.as(DeclReferenceExprSyntax.self),
      baseReference.baseName.text == "UserDefaults"
    {
      recordSharedState(kind: "swift-user-defaults", reference: "UserDefaults.standard")
    }
    return .visitChildren
  }

  override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
    recordTypeName(node.name.text)
    if node.memberBlock.members.contains(where: { member in
      guard let variable: VariableDeclSyntax = member.decl.as(VariableDeclSyntax.self) else {
        return false
      }
      return variable.bindingSpecifier.text == "var"
    }) {
      recordSharedState(kind: "swift-actor-var", reference: node.name.text)
    }
    return .visitChildren
  }

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    recordCallableReference(node.calledExpression)
    guard isPropertyCheckCall(node) else {
      return .visitChildren
    }
    let referenceVisitor: APIReferenceVisitor = propertyConstructionReferenceVisitor(for: node)
    let expandedReferences: [String] = expandedAPIReferences(
      from: referenceVisitor.apiReferences,
      visited: []
    )
    let hasOperationSequenceGenerator: Bool = node.arguments.contains(where: {
      expressionContainsMemberAccess($0.expression, named: "array")
    })
    let generatedInputs: [GeneratedInputFact] = generatedInputFacts(for: node)
    propertyChecks.append(
      PropertyCheckFact(
        references: Array(Set(expandedReferences)).sorted(),
        generatedInputs: generatedInputs,
        operationSequences: hasOperationSequenceGenerator
          ? operationSequences(for: node, from: generatedInputs, assertions: expandedReferences)
          : []
      )
    )
    return .visitChildren
  }

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    let name: String = node.name.text
    recordIdentifier(name)
    if node.body != nil {
      interfaceLogicEvidence.recordFunctionBody(name)
    }
    if !isPrivate(node.modifiers) {
      decisionSurface.append(name)
      propertyTestSurface.append(name)
      decisionReferences.append(name)
      recordDecisionProducts(node.signature.returnClause?.type)
    }
    return .visitChildren
  }

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    recordTypeName(node.name.text)
    return .visitChildren
  }

  override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
    recordTypeName(node.name.text)
    return .visitChildren
  }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    recordTypeName(node.name.text)
    return .visitChildren
  }

  override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
    if node.body != nil {
      recordIdentifier("init")
      interfaceLogicEvidence.recordInitializerBody("init")
    }
    return .visitChildren
  }

  override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
    interfaceLogicEvidence.recordControlFlow("if")
    return .visitChildren
  }

  override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
    interfaceLogicEvidence.recordControlFlow("switch")
    return .visitChildren
  }

  override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
    interfaceLogicEvidence.recordControlFlow("for")
    return .visitChildren
  }

  override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
    interfaceLogicEvidence.recordControlFlow("while")
    return .visitChildren
  }

  override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
    interfaceLogicEvidence.recordControlFlow("repeat")
    return .visitChildren
  }

  override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
    interfaceLogicEvidence.recordControlFlow("guard")
    return .visitChildren
  }

  override func visit(_ node: DoStmtSyntax) -> SyntaxVisitorContinueKind {
    interfaceLogicEvidence.recordControlFlow("do")
    return .visitChildren
  }

  override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
    if node.bindingSpecifier.text == "var" {
      if hasAttribute(node.attributes, named: "Published") {
        recordSharedState(kind: "swift-published", reference: "@Published")
      }
    }
    for binding: PatternBindingSyntax in node.bindings where binding.accessorBlock != nil {
      if let identifierPattern: IdentifierPatternSyntax = binding.pattern.as(
        IdentifierPatternSyntax.self)
      {
        let name: String = identifierPattern.identifier.text
        recordIdentifier(name)
        interfaceLogicEvidence.recordComputedProperty(name)
      } else {
        interfaceLogicEvidence.recordComputedProperty("computed-property")
      }
    }
    if !isPrivate(node.modifiers) && hasStaticModifier(node.modifiers) {
      for binding: PatternBindingSyntax in node.bindings {
        if let identifierPattern: IdentifierPatternSyntax = binding.pattern.as(
          IdentifierPatternSyntax.self)
        {
          let name: String = identifierPattern.identifier.text
          recordIdentifier(name)
          decisionSurface.append(name)
        }
        recordDecisionProducts(binding.typeAnnotation?.type)
      }
    }
    return .visitChildren
  }

  private func recordTypeName(_ name: String) {
    recordIdentifier(name)
    decisionReferences.append(name)
  }

  private func recordDecisionProducts(_ type: TypeSyntax?) {
    guard let type else {
      return
    }
    let visitor: TypeIdentifierVisitor = TypeIdentifierVisitor(viewMode: .sourceAccurate)
    visitor.walk(type)
    decisionProducts.append(contentsOf: visitor.identifiers)
  }

  private func recordCallableReference(_ expression: ExprSyntax) {
    if let reference: DeclReferenceExprSyntax = expression.as(DeclReferenceExprSyntax.self) {
      recordAPIReference(reference.baseName.text)
      return
    }
    if let memberAccess: MemberAccessExprSyntax = expression.as(MemberAccessExprSyntax.self) {
      if let baseReference: DeclReferenceExprSyntax = memberAccess.base?.as(
        DeclReferenceExprSyntax.self)
      {
        recordAPIReference(baseReference.baseName.text)
        recordAPIReference(memberAccess.declName.baseName.text)
      }
    }
  }

  private func recordAPIReference(_ name: String) {
    if !name.isEmpty {
      apiReferences.append(name)
    }
  }

  private func propertyConstructionReferenceVisitor(
    for node: FunctionCallExprSyntax
  ) -> APIReferenceVisitor {
    let referenceVisitor: APIReferenceVisitor = APIReferenceVisitor(viewMode: .sourceAccurate)
    referenceVisitor.walk(node)
    return referenceVisitor
  }

  private func generatedInputFacts(for node: FunctionCallExprSyntax) -> [GeneratedInputFact] {
    propertyClosureParameters(for: node).map { name in
      let visitor: GeneratedInputUseVisitor = GeneratedInputUseVisitor(
        inputName: name,
        viewMode: .sourceAccurate
      )
      if let trailingClosure: ClosureExprSyntax = node.trailingClosure {
        visitor.walk(trailingClosure)
      }
      for argument: LabeledExprSyntax in node.arguments {
        if let closure: ClosureExprSyntax = argument.expression.as(ClosureExprSyntax.self) {
          visitor.walk(closure)
        }
      }
      return GeneratedInputFact(
        name: name,
        uses: visitor.found ? [name] : []
      )
    }
  }

  private func operationSequences(
    for node: FunctionCallExprSyntax,
    from generatedInputs: [GeneratedInputFact],
    assertions: [String]
  ) -> [OperationSequenceFact] {
    generatedInputs.compactMap { input in
      if input.uses.isEmpty {
        return nil
      }
      let visitor: GeneratedInputAPIUseVisitor = GeneratedInputAPIUseVisitor(
        inputName: input.name,
        viewMode: .sourceAccurate
      )
      if let trailingClosure: ClosureExprSyntax = node.trailingClosure {
        visitor.walk(trailingClosure)
      }
      for argument: LabeledExprSyntax in node.arguments {
        if let closure: ClosureExprSyntax = argument.expression.as(ClosureExprSyntax.self) {
          visitor.walk(closure)
        }
      }
      let operations = Array(Set(expandedAPIReferences(from: visitor.uses, visited: []))).sorted()
      if operations.isEmpty {
        return nil
      }
      return OperationSequenceFact(
        input: input.name,
        operations: operations,
        assertions: Array(Set(assertions)).sorted()
      )
    }
  }

  private func propertyClosureParameters(for node: FunctionCallExprSyntax) -> [String] {
    var names: [String] = []
    if let trailingClosure: ClosureExprSyntax = node.trailingClosure {
      names.append(contentsOf: closureParameterNames(trailingClosure))
    }
    for argument: LabeledExprSyntax in node.arguments {
      if let closure: ClosureExprSyntax = argument.expression.as(ClosureExprSyntax.self) {
        names.append(contentsOf: closureParameterNames(closure))
      }
    }
    return names.filter { !$0.isEmpty && $0 != "_" }
  }

  private func closureParameterNames(_ closure: ClosureExprSyntax) -> [String] {
    guard let parameterClause: ClosureSignatureSyntax.ParameterClause = closure.signature?.parameterClause else {
      return []
    }
    switch parameterClause {
    case .simpleInput(let parameters):
      return parameters.map { $0.name.text }
    case .parameterClause(let parameterClause):
      return parameterClause.parameters.map { parameter in
        (parameter.secondName ?? parameter.firstName).text
      }
    }
  }

  private func recordIdentifier(_ name: String) {
    if !name.isEmpty {
      identifiers.append(name)
    }
  }

  private func recordSharedState(kind: String, reference: String) {
    var references: Set<String> = sharedStateByKind[kind] ?? []
    references.insert(reference)
    sharedStateByKind[kind] = references
  }

  var sharedStateFacts: [SharedStateFact] {
    sharedStateByKind.keys.sorted().map { kind in
      SharedStateFact(
        kind: kind,
        references: Array(sharedStateByKind[kind] ?? []).sorted()
      )
    }
  }

  private func expandedAPIReferences(from references: [String], visited: Set<String>) -> [String] {
    var expandedReferences: [String] = references
    var visitedReferences: Set<String> = visited
    for reference: String in references {
      guard !visitedReferences.contains(reference),
        let body: CodeBlockSyntax = functionBodiesByName[reference]
      else {
        continue
      }
      visitedReferences.insert(reference)
      let visitor: APIReferenceVisitor = APIReferenceVisitor(viewMode: .sourceAccurate)
      visitor.walk(body)
      expandedReferences.append(
        contentsOf: expandedAPIReferences(
          from: visitor.apiReferences,
          visited: visitedReferences
        )
      )
    }
    return expandedReferences
  }
}

final class FunctionBodyVisitor: SyntaxVisitor {
  private(set) var functionBodiesByName: [String: CodeBlockSyntax] = [:]

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    if let body: CodeBlockSyntax = node.body {
      functionBodiesByName[node.name.text] = body
    }
    return .visitChildren
  }
}

private func isPropertyCheckCall(_ node: FunctionCallExprSyntax) -> Bool {
  guard
    let calledExpression: DeclReferenceExprSyntax = node.calledExpression.as(
      DeclReferenceExprSyntax.self
    )
  else {
    return false
  }
  return calledExpression.baseName.text == "propertyCheck"
}

private func expressionContainsMemberAccess(_ expression: ExprSyntax, named name: String) -> Bool {
  let visitor: MemberAccessVisitor = MemberAccessVisitor(
    memberName: name, viewMode: .sourceAccurate)
  visitor.walk(expression)
  return visitor.found
}

final class MemberAccessVisitor: SyntaxVisitor {
  let memberName: String
  private(set) var found: Bool = false

  init(memberName: String, viewMode: SyntaxTreeViewMode) {
    self.memberName = memberName
    super.init(viewMode: viewMode)
  }

  override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
    if node.declName.baseName.text == memberName {
      found = true
      return .skipChildren
    }
    return .visitChildren
  }
}

final class APIReferenceVisitor: SyntaxVisitor {
  private(set) var apiReferences: [String] = []

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    recordCallableReference(node.calledExpression)
    return .visitChildren
  }

  override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
    if let baseReference: DeclReferenceExprSyntax = node.base?.as(DeclReferenceExprSyntax.self) {
      recordAPIReference(baseReference.baseName.text)
      recordAPIReference(node.declName.baseName.text)
    }
    return .visitChildren
  }

  private func recordCallableReference(_ expression: ExprSyntax) {
    if let reference: DeclReferenceExprSyntax = expression.as(DeclReferenceExprSyntax.self) {
      recordAPIReference(reference.baseName.text)
      return
    }
    if let memberAccess: MemberAccessExprSyntax = expression.as(MemberAccessExprSyntax.self),
      let baseReference: DeclReferenceExprSyntax = memberAccess.base?.as(
        DeclReferenceExprSyntax.self)
    {
      recordAPIReference(baseReference.baseName.text)
      recordAPIReference(memberAccess.declName.baseName.text)
    }
  }

  private func recordAPIReference(_ name: String) {
    if !name.isEmpty {
      apiReferences.append(name)
    }
  }
}

final class GeneratedInputUseVisitor: SyntaxVisitor {
  let inputName: String
  private(set) var found: Bool = false

  init(inputName: String, viewMode: SyntaxTreeViewMode) {
    self.inputName = inputName
    super.init(viewMode: viewMode)
  }

  override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
    if node.baseName.text == inputName {
      found = true
      return .skipChildren
    }
    return .visitChildren
  }
}

final class GeneratedInputAPIUseVisitor: SyntaxVisitor {
  let inputName: String
  private(set) var uses: [String] = []

  init(inputName: String, viewMode: SyntaxTreeViewMode) {
    self.inputName = inputName
    super.init(viewMode: viewMode)
  }

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    let inputVisitor: IdentifierUseVisitor = IdentifierUseVisitor(
      name: inputName,
      viewMode: .sourceAccurate
    )
    inputVisitor.walk(node)
    if inputVisitor.found {
      let referenceVisitor: APIReferenceVisitor = APIReferenceVisitor(viewMode: .sourceAccurate)
      referenceVisitor.walk(node)
      uses.append(contentsOf: referenceVisitor.apiReferences)
    }
    return .visitChildren
  }

  override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
    let inputVisitor: IdentifierUseVisitor = IdentifierUseVisitor(
      name: inputName,
      viewMode: .sourceAccurate
    )
    inputVisitor.walk(node.sequence)
    if inputVisitor.found {
      let referenceVisitor: APIReferenceVisitor = APIReferenceVisitor(viewMode: .sourceAccurate)
      referenceVisitor.walk(node.body)
      uses.append(contentsOf: referenceVisitor.apiReferences)
    }
    return .visitChildren
  }
}

final class IdentifierUseVisitor: SyntaxVisitor {
  let name: String
  private(set) var found: Bool = false

  init(name: String, viewMode: SyntaxTreeViewMode) {
    self.name = name
    super.init(viewMode: viewMode)
  }

  override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
    if node.baseName.text == name {
      found = true
      return .skipChildren
    }
    return .visitChildren
  }
}

final class TypeIdentifierVisitor: SyntaxVisitor {
  private(set) var identifiers: [String] = []

  override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
    identifiers.append(node.name.text)
    return .visitChildren
  }
}

private func isPrivate(_ modifiers: DeclModifierListSyntax) -> Bool {
  modifiers.contains { modifier in
    modifier.name.text == "private" || modifier.name.text == "fileprivate"
  }
}

private func hasStaticModifier(_ modifiers: DeclModifierListSyntax) -> Bool {
  modifiers.contains { modifier in
    modifier.name.text == "static"
  }
}

private func hasAttribute(_ attributes: AttributeListSyntax, named expectedName: String) -> Bool {
  attributes.contains { attribute in
    guard let attributeSyntax: AttributeSyntax = attribute.as(AttributeSyntax.self) else {
      return false
    }
    return attributeSyntax.attributeName.trimmedDescription == expectedName
  }
}

enum ArchLintError: Error, CustomStringConvertible {
  case missingArgumentValue(String)
  case missingRequiredArgument(String)
  case missingDirectory(String)
  case semanticIndexUnavailable(String)

  var description: String {
    switch self {
    case .missingArgumentValue(let argument):
      return "missing value for \(argument)"
    case .missingRequiredArgument(let argument):
      return "\(argument) is required"
    case .missingDirectory(let path):
      return "missing directory \(path)"
    case .semanticIndexUnavailable(let message):
      return "swift semantic reference resolution unavailable: \(message)"
    }
  }
}
