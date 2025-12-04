import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.framework(
  name: "IndigoFoundation",
  dependencies: [
    .external(name: "Algorithms"),
    .external(name: "ComposableArchitecture"),
    .external(name: "ComposableToasts"),
    .external(name: "Dependencies"),
    .external(name: "DependenciesMacros"),
    .external(name: "GRDB"),
    .external(name: "IssueReporting"),
    .external(name: "JWTAuth"),
    .external(name: "LoggingClient")
  ]
)
