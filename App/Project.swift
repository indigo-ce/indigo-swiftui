import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
  name: "App",
  settings: .settings(
    configurations: [
      .debug(name: "Debug", xcconfig: .relativeToRoot("Configs/Debug.xcconfig")),
      .release(name: "Release", xcconfig: .relativeToRoot("Configs/Release.xcconfig"))
    ]
  ),
  targets: [
    .target(
      name: appTarget.targetName,
      destinations: .destinations,
      product: .app,
      bundleId: "\(teamReverseDomain).\(appTarget.targetName)",
      deploymentTargets: .platforms,
      infoPlist: .extendingDefault(
        with: [
          "UILaunchScreen": [
            "UIColorName": "",
            "UIImageName": ""
          ]
        ]
      ),
      sources: ["Sources/**"],
      resources: ["Resources/**"],
      dependencies: [
        .project(target: "Core", path: .relativeToRoot("Core")),
        .project(target: "Components", path: .relativeToRoot("Components")),
        .project(target: "FeatureA", path: .relativeToRoot("FeatureA")),
        .project(target: "FeatureB", path: .relativeToRoot("FeatureB"))
      ],
      settings: .settings(
        base: [
          "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]": .string("mac.entitlements"),
          "CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]": .string("ios.entitlements"),
          "CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]": .string("ios.entitlements")
        ]
      )
    ),
    .target(
      name: "\(appTarget.targetName)Tests",
      destinations: .destinations,
      product: .unitTests,
      bundleId: "\(teamReverseDomain).\(appTarget.targetName)Tests",
      sources: ["Tests/**"],
      dependencies: [
        .target(name: appTarget.targetName)
      ]
    )
  ],
  schemes: [
    .scheme(
      name: appTarget.targetName,
      shared: true,
      buildAction: .buildAction(targets: [appTarget]),
      testAction: .testPlans([.relativeToManifest("All.xctestplan")]),
      runAction: .runAction(
        configuration: "Debug",
        executable: appTarget
      ),
      archiveAction: .archiveAction(configuration: "Debug"),
      profileAction: .profileAction(
        configuration: "Debug",
        executable: appTarget
      ),
      analyzeAction: .analyzeAction(configuration: "Debug")
    ),
    .scheme(
      name: "\(appTarget.targetName) Release",
      shared: true,
      buildAction: .buildAction(targets: [appTarget]),
      runAction: .runAction(
        configuration: "Release",
        executable: appTarget
      ),
      archiveAction: .archiveAction(configuration: "Release"),
      profileAction: .profileAction(
        configuration: "Release",
        executable: appTarget
      ),
      analyzeAction: .analyzeAction(configuration: "Release")
    )
  ]
)
