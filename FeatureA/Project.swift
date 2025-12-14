import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.framework(
  name: "FeatureA",
  dependencies: .indigoFoundation,
  testDependencies: .indigoFoundation
)
