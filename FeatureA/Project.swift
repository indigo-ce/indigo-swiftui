import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.framework(
  name: "FeatureA",
  dependencies: [
    .project(
      target: "IndigoFoundation",
      path: .relativeToRoot("IndigoFoundation")
    ),
    .external(name: "ComposableArchitecture")
  ],
  testDependencies: [
    .external(name: "ComposableArchitecture")
  ]
)
