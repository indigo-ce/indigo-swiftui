// swift-tools-version: 6.0
@preconcurrency import PackageDescription

#if TUIST
  import ProjectDescription

  let packageSettings = PackageSettings(
    // Customize the product types for specific package product
    // Default is .staticFramework
    // productTypes: ["Alamofire": .framework,]
    productTypes: [
      "Algorithms": .framework,
      "BitCollections": .framework,
      "CasePaths": .framework,
      "CasePathsCore": .framework,
      "Clocks": .framework,
      "Collections": .framework,
      "CombineSchedulers": .framework,
      "ComposableArchitecture": .framework,
      "ComposableToasts": .framework,
      "ConcurrencyExtras": .framework,
      "CustomDump": .framework,
      "Dependencies": .framework,
      "DependenciesMacros": .framework,
      "DequeModule": .framework,
      "FileLogger": .framework,
      "GRDB": .framework,
      "GRDBSQLite": .framework,
      "HTTPRequestBuilder": .framework,
      "HTTPRequestClient": .framework,
      "HeapModule": .framework,
      "IdentifiedCollections": .framework,
      "InternalCollectionsUtilities": .framework,
      "IssueReporting": .framework,
      "IssueReportingPackageSupport": .framework,
      "JWTAuth": .framework,
      "JWTDecode": .framework,
      "Logging": .framework,
      "LoggingClient": .framework,
      "NetworkImage": .framework,
      "OrderedCollections": .framework,
      "Perception": .framework,
      "PerceptionCore": .framework,
      "Pulse": .framework,
      "PulseUI": .framework,
      "RealModule": .framework,
      "Sharing": .framework,
      "SimpleKeychain": .framework,
      "SQLiteData": .framework,
      "SwiftNavigation": .framework,
      "SwiftUINavigation": .framework,
      "UIKitNavigation": .framework,
      "UIKitNavigationShim": .framework,
      "XCTestDynamicOverlay": .framework
    ],
    // To avoid collision with Apple's own Sharing framework when linked dynamically
    targetSettings: [
      "ComposableArchitecture": .settings(
        base: [
          "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ]
      ),
      "Sharing": .settings(
        base: [
          "PRODUCT_NAME": "SwiftSharing",
          "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ]
      )
    ]
  )
#endif

let package = Package(
  name: "Indigo",
  dependencies: [
    .package(url: "https://github.com/apple/swift-algorithms", from: "1.2.1"),
    .package(url: "https://github.com/apple/swift-collections", from: "1.3.0"),
    .package(url: "https://github.com/apple/swift-log", from: "1.6.3"),
    .package(url: "https://github.com/auth0/JWTDecode.swift", from: "3.3.0"),
    .package(url: "https://github.com/auth0/SimpleKeychain", from: "1.3.0"),
    .package(url: "https://github.com/gonzalezreal/NetworkImage", from: "6.0.1"),
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.6.0"),
    .package(url: "https://github.com/indigo-ce/composable-toasts", from: "1.1.0"),
    .package(url: "https://github.com/indigo-ce/http-request-builder", from: "1.0.3"),
    .package(url: "https://github.com/indigo-ce/http-request-client", from: "1.4.0"),
    .package(url: "https://github.com/indigo-ce/jwt-auth-client", from: "1.3.1"),
    .package(url: "https://github.com/indigo-ce/logging-client", from: "2.0.0"),
    .package(url: "https://github.com/indigo-ce/swift-file-logger", from: "0.9.1"),
    .package(url: "https://github.com/kean/Pulse", from: "5.1.4"),
    .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.4.0"),
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.23.1"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.9.2"),
    .package(url: "https://github.com/pointfreeco/swift-navigation", from: "2.6.0"),
    .package(url: "https://github.com/pointfreeco/swift-perception", from: "2.0.9"),
    .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.5.2"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.3.0")
  ]
)
