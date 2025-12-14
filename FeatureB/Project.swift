import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.framework(
  name: "FeatureB",
  dependencies: .indigoFoundation,
  testDependencies: .indigoFoundation
)
