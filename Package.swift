// swift-tools-version: 6.0
@preconcurrency import PackageDescription

#if TUIST
  import ProjectDescription

  let packageSettings = PackageSettings(
    // Customize the product types for specific package product
    // Default is .staticFramework
    // productTypes: ["Alamofire": .framework,]
    productTypes: [
      "ComposableArchitecture": .framework,
      "Clocks": .framework,
      "CombineSchedulers": .framework,
      "ConcurrencyExtras": .framework,
      "CustomDump": .framework,
      "Dependencies": .framework,
      "IdentifiedCollections": .framework,
      "InternalCollectionsUtilities": .framework,
      "IssueReporting": .framework,
      "IssueReportingPackageSupport": .framework,
      "OrderedCollections": .framework,
      "PerceptionCore": .framework,
      "Sharing": .framework,
      "Sharing1": .framework,
      "Sharing2": .framework,
      "XCTestDynamicOverlay": .framework
    ]
  )
#endif

let package = Package(
  name: "Indigo",
  dependencies: [
    .package(url: "https://github.com/4rays/jwt-auth-client", from: "1.1.3"),
    .package(url: "https://github.com/4rays/logging-client", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-algorithms", from: "1.2.0"),
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.6.0"),
    .package(url: "https://github.com/indigo-ce/composable-toasts", from: "1.0.1"),
    .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.3.0"),
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.17.0"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.3.9"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.3.0")
  ]
)
