import ProjectDescription

extension Array where Element == TargetDependency {
  public static var indigoFoundation: [TargetDependency] {
    [
      .external(name: "Algorithms"),
      .external(name: "ComposableArchitecture"),
      .external(name: "ComposableToasts"),
      .external(name: "Dependencies"),
      .external(name: "DependenciesMacros"),
      .external(name: "GRDB"),
      .external(name: "NetworkImage"),
      .external(name: "Pulse"),
      .external(name: "PulseUI"),
      .external(name: "SwiftNavigation")
    ]
  }
}

extension Project {
  public static func framework(
    name: String,
    reverseDomain: String = teamReverseDomain,
    dependencies: [TargetDependency] = [],
    testDependencies: [TargetDependency] = []
  ) -> Project {
    .init(
      name: name,
      settings: .settings(
        base: [
          "ENABLE_MODULE_VERIFIER": "YES",
          "MODULE_VERIFIER_SUPPORTED_LANGUAGE_STANDARDS": "gnu11 gnu++14",
          "STRING_CATALOG_GENERATE_SYMBOLS": "YES"
        ]
      ),
      targets: [
        .target(
          name: name,
          destinations: .destinations,
          product: .framework,
          bundleId: "\(reverseDomain).\(name)",
          deploymentTargets: .platforms,
          sources: ["Sources/**"],
          resources: ["Resources/**"],
          dependencies: dependencies
        ),
        .target(
          name: "\(name)Tests",
          destinations: .destinations,
          product: .unitTests,
          bundleId: "\(reverseDomain).\(name)Tests",
          sources: ["Tests/**"],
          resources: ["Tests/Resources/**"],
          dependencies: [.target(name: name)] + testDependencies,
        )
      ]
    )
  }
}

extension ProjectDescription.DeploymentTargets {
  public static var platforms: DeploymentTargets {
    .multiplatform(
      iOS: "26.0",
      macOS: "26.0",
      watchOS: nil,
      tvOS: nil,
      visionOS: nil
    )
  }
}

extension ProjectDescription.Destinations {
  public static var destinations: Destinations {
    [.iPad, .iPhone, .mac]
  }
}
