import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.framework(
  name: "NoteEditorFeature",
  dependencies: [
    .project(target: "Core", path: .relativeToRoot("Core"))
  ] + .indigoFoundation
)
