import Foundation
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
  let metadata: ModuleMetadata
  let imports: Set<String>
  let identifiers: Set<String>
  let apiReferences: Set<String>
  let decisionReferences: Set<String>
  let decisionSurface: Set<String>
  let propertyTestSurface: Set<String>
  let decisionProducts: Set<String>
  let interfaceLogicEvidence: InterfaceLogicEvidence
  let sharedState: [SharedStateFact]
  let propertyChecks: [PropertyCheckFact]
}

struct SwiftTarget {
  let name: String
  let sourceRoots: [URL]
  let isTestTarget: Bool
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
  let language: String
  let package: String
  let testTarget: String
  let metadata: MetadataFact
  let imports: [String]
  let identifiers: [String]
  let apiReferences: [String]
  let decisionSurface: [String]
  let propertyTestSurface: [String]
  let decisionProducts: [String]
  let decisionReferences: [String]
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
  let interleaving: Bool
}

struct MetadataFact: Encodable {
  let moduleType: String
  let domain: String
  let exemptReason: String
}

struct InterfaceLogicEvidence: Encodable {
  var functionBodies: [String] = []
  var initializerBodies: [String] = []
  var computedProperties: [String] = []
  var controlFlow: [String] = []
  var classDeclarations: [String] = []
  var imperativeDeclarations: [String] = []

  mutating func recordFunctionBody(_ reference: String) {
    appendUnique(reference, to: &functionBodies)
  }

  mutating func recordInitializerBody(_ reference: String) {
    appendUnique(reference, to: &initializerBodies)
  }

  mutating func recordComputedProperty(_ reference: String) {
    appendUnique(reference, to: &computedProperties)
  }

  mutating func recordControlFlow(_ reference: String) {
    appendUnique(reference, to: &controlFlow)
  }

  mutating func recordClassDeclaration(_ reference: String) {
    appendUnique(reference, to: &classDeclarations)
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
    let files: [SourceFact] = try targets.flatMap { target in
      try target.sourceRoots.flatMap { root in
        try swiftFileInfos(root: root).map {
          sourceFact($0, package: target.name, testTarget: target.isTestTarget ? target.name : "")
        }
      }
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
        isTestTarget: isTestTarget(target)
      )
    }
  }

  private static func isTestTarget(_ target: XcodeGenTarget) -> Bool {
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
    let source: String = try String(contentsOf: fileURL, encoding: .utf8)
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
      url: fileURL,
      source: source,
      metadata: metadata,
      imports: Set(visitor.importedModules),
      identifiers: Set(visitor.identifiers),
      apiReferences: Set(visitor.apiReferences),
      decisionReferences: Set(visitor.decisionReferences),
      decisionSurface: Set(visitor.decisionSurface),
      propertyTestSurface: Set(visitor.propertyTestSurface),
      decisionProducts: Set(visitor.decisionProducts),
      interfaceLogicEvidence: visitor.interfaceLogicEvidence,
      sharedState: visitor.sharedStateFacts,
      propertyChecks: metadata.moduleType == "stateTest"
        ? visitor.propertyChecks
        : visitor.propertyChecks.map { check in
          PropertyCheckFact(references: check.references, interleaving: false)
        }
    )
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

  private static func sourceFact(_ fileInfo: SwiftFileInfo, package: String, testTarget: String)
    -> SourceFact
  {
    return SourceFact(
      path: fileInfo.url.path,
      language: "swift",
      package: package,
      testTarget: testTarget,
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
    let referenceVisitor: APIReferenceVisitor = propertyClosureReferenceVisitor(for: node)
    let expandedReferences: [String] = expandedAPIReferences(
      from: referenceVisitor.apiReferences,
      visited: []
    )
    let isInterleaving: Bool = node.arguments.contains(where: {
      expressionContainsMemberAccess($0.expression, named: "array")
    })
    propertyChecks.append(
      PropertyCheckFact(
        references: Array(Set(expandedReferences)).sorted(),
        interleaving: isInterleaving
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
    interfaceLogicEvidence.recordClassDeclaration(node.name.text)
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

  private func propertyClosureReferenceVisitor(
    for node: FunctionCallExprSyntax
  ) -> APIReferenceVisitor {
    let referenceVisitor: APIReferenceVisitor = APIReferenceVisitor(viewMode: .sourceAccurate)
    if let trailingClosure: ClosureExprSyntax = node.trailingClosure {
      referenceVisitor.walk(trailingClosure)
    }
    for argument: LabeledExprSyntax in node.arguments {
      if let closure: ClosureExprSyntax = argument.expression.as(ClosureExprSyntax.self) {
        referenceVisitor.walk(closure)
      }
    }
    return referenceVisitor
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

  var description: String {
    switch self {
    case .missingArgumentValue(let argument):
      return "missing value for \(argument)"
    case .missingRequiredArgument(let argument):
      return "\(argument) is required"
    case .missingDirectory(let path):
      return "missing directory \(path)"
    }
  }
}
