import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.framework(
  name: "RootFeature",
  dependencies: [
    .project(target: "Core", path: .relativeToRoot("Core")),
    .project(target: "NotesListFeature", path: .relativeToRoot("NotesListFeature"))
  ] + .indigoFoundation,
  testDependencies: [
    .project(target: "Core", path: .relativeToRoot("Core"))
  ] + .indigoFoundation,
  usesSharing: true
)
