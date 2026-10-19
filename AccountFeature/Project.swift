import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.framework(
  name: "AccountFeature",
  dependencies: [
    .project(target: "Core", path: .relativeToRoot("Core")),
    .project(target: "Components", path: .relativeToRoot("Components"))
  ] + .indigoFoundation,
  testDependencies: [
    .project(target: "Core", path: .relativeToRoot("Core"))
  ] + .indigoFoundation
)
