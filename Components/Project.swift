import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.framework(
  name: "Components",
  dependencies: [
    .project(
      target: "IndigoFoundation",
      path: .relativeToRoot("IndigoFoundation")
    )
  ]
)
