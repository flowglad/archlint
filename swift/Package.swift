// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "SwiftArchLint",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "SwiftArchLint", targets: ["SwiftArchLint"])
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/indexstore-db.git", revision: "cf29ef4e5e5243a3b6f518d72c6e527b5290375a"),
    .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "603.0.1")
  ],
  targets: [
    .executableTarget(
      name: "SwiftArchLint",
      dependencies: [
        .product(name: "IndexStoreDB", package: "indexstore-db"),
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "Yams", package: "Yams"),
      ]
    )
  ]
)
