// swift-tools-version: 6.0
@preconcurrency import PackageDescription

#if TUIST
  import ProjectDescription

  // Use the value returned by this function to set the product type of your targets.
  func productType() -> ProjectDescription.Product {
    if case .string(let linking) = Environment.linking {
      return linking == "static" ? .staticFramework : .framework
    } else {
      return .framework
    }
  }

  func frameworkProductTypes(
    _ products: [String]
  ) -> [String: ProjectDescription.Product] {
    products.reduce(into: [:]) { result, product in
      result[product] = .framework
    }
  }

  func sharingTargetSettings(
    _ targets: [String]
  ) -> [String: ProjectDescription.Settings] {
    var settings: [String: ProjectDescription.Settings] = [:]

    // Always add Sharing with its special settings
    settings["Sharing"] = .settings(
      base: [
        "PRODUCT_NAME": "SwiftSharing",
        "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
      ]
    )

    // Add other targets with just the module-alias flag
    for target in targets where target != "Sharing" {
      settings[target] = .settings(
        base: [
          "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ]
      )
    }

    return settings
  }

  let packageSettings = PackageSettings(
    productTypes: frameworkProductTypes([
      "Algorithms",
      "BitCollections",
      "CasePaths",
      "CasePathsCore",
      "Clocks",
      "Collections",
      "CombineSchedulers",
      "ComposableArchitecture",
      "ComposableToasts",
      "ConcurrencyExtras",
      "CustomDump",
      "Dependencies",
      "DependenciesMacros",
      "DequeModule",
      "FileLogger",
      "GRDB",
      "GRDBSQLite",
      "HTTPRequestBuilder",
      "HTTPRequestClient",
      "HeapModule",
      "IdentifiedCollections",
      "InternalCollectionsUtilities",
      "IssueReporting",
      "IssueReportingPackageSupport",
      "JWTAuth",
      "JWTDecode",
      "Logging",
      "LoggingClient",
      "OrderedCollections",
      "Perception",
      "PerceptionCore",
      "Pulse",
      "PulseUI",
      "RealModule",
      "Sharing",
      "SimpleKeychain",
      "SQLiteData",
      "SwiftNavigation",
      "SwiftUINavigation",
      "UIKitNavigation",
      "UIKitNavigationShim",
      "XCTestDynamicOverlay"
    ]),
    targetSettings: sharingTargetSettings([
      "ComposableArchitecture",
      "JWTAuth",
      "SQLiteData"
    ])
  )
#endif

let package = Package(
  name: "Indigo",
  dependencies: [
    .package(url: "https://github.com/apple/swift-algorithms", from: "1.2.1"),
    .package(url: "https://github.com/apple/swift-collections", from: "1.4.1"),
    .package(url: "https://github.com/apple/swift-log", from: "1.12.0"),
    .package(url: "https://github.com/auth0/JWTDecode.swift", from: "4.0.0"),
    .package(url: "https://github.com/auth0/SimpleKeychain", from: "1.3.0"),
    .package(url: "https://github.com/indigo-ce/composable-toasts", from: "1.1.0"),
    .package(url: "https://github.com/indigo-ce/http-request-builder", from: "1.0.3"),
    .package(url: "https://github.com/indigo-ce/http-request-client", from: "1.6.0"),
    .package(url: "https://github.com/indigo-ce/jwt-auth-client", from: "1.4.0"),
    .package(url: "https://github.com/indigo-ce/logging-client", from: "2.0.0"),
    .package(url: "https://github.com/indigo-ce/swift-file-logger", from: "0.9.1"),
    .package(url: "https://github.com/kean/Pulse", from: "5.2.1"),
    .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.6.1"),
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.25.5"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.12.0"),
    .package(url: "https://github.com/pointfreeco/swift-navigation", from: "2.8.0"),
    .package(url: "https://github.com/pointfreeco/swift-perception", from: "2.0.10"),
    .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.8.0"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.9.0")
  ]
)
