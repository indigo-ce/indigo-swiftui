import ProjectDescription

extension Project {
  public static func framework(
    name: String,
    reverseDomain: String = teamReverseDomain,
    tca: Bool = false,
    dependencies: [TargetDependency] = []
  ) -> Project {
    .init(
      name: name,
      settings: .settings(
        base: [
          "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
          "ENABLE_MODULE_VERIFIER": "YES",
          "MODULE_VERIFIER_SUPPORTED_LANGUAGE_STANDARDS": "gnu11 gnu++14",
          "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
          "REGISTER_APP_GROUPS": "YES"
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
          dependencies: (tca
            ? [.project(target: "IndigoFoundation", path: .relativeToRoot("IndigoFoundation"))]
            : [])
            + dependencies,
          settings: .settings(
            base: [
              "DEFINES_MODULE": "NO"
            ]
          )
        ),
        .target(
          name: "\(name)Tests",
          destinations: .destinations,
          product: .unitTests,
          bundleId: "\(reverseDomain).\(name)Tests",
          sources: ["Tests/**"],
          dependencies: [
            .target(name: name)
          ]
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
