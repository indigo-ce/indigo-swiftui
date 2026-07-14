# 🪻 Indigo Stack CE — Apple Platforms

A modular SwiftUI template using [Tuist](https://tuist.dev/) and [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture) for building iOS and macOS applications.

## Getting Started

### Setup

1. **Configure project settings** in `Tuist/ProjectDescriptionHelpers/Config.swift`:

   ```swift
   public let teamReverseDomain = "com.yourcompany"
   public let appTarget: TargetReference = "YourApp"
   ```

2. **Install Tuist**:

   ```sh
   curl https://mise.jdx.dev/install.sh | sh
   mise install
   ```

3. **Install dependencies and generate project**:

   ```sh
   tuist install
   tuist generate
   ```

4. **Open and build**:

   ```sh
   open Indigo.xcworkspace
   ```

## Skills (Optional)

Install xbridge for Xcode integration:

```sh
npx skills add https://github.com/4rays/xbridge
```

## Project Architecture

This project is organized into multiple modules:

- **App**: The main iOS/macOS application targets that depend on Core, Components, and feature modules
- **Core**: Business logic, data models, and shared utilities
- **Components**: Reusable SwiftUI components with no external dependencies for maximum portability
- **NotesListFeature** and **NoteEditorFeature**: Example TCA-based feature modules with their respective reducers and views

### Dependency Graph

```
App
├── Core (business logic)
├── Components (reusable UI components, no dependencies)
├── NotesListFeature (TCA-based feature)
├── NoteEditorFeature (TCA-based feature)
└── External packages (via .indigoFoundation helper)

Core → External packages (via .indigoFoundation helper)
NotesListFeature/NoteEditorFeature → External packages (via .indigoFoundation helper)
Components → (no dependencies)
```

**Key architectural benefits:**

- Clean separation of concerns with clear module boundaries
- Reusable UI components with no external dependencies
- Centralized dependency management preventing double-linking issues
- Consistent naming conventions (XFeature reducers, XView views)

## Working with Dependencies

### The `.indigoFoundation` Helper

External dependencies are managed through a centralized helper in `Tuist/ProjectDescriptionHelpers/Project+Templates.swift`. This prevents double-linking and makes dependency management easier.

**Usage:**

```swift
// Single target
let project = Project.framework(
  name: "Core",
  dependencies: .indigoFoundation
)

// Combined with local dependencies
dependencies: [
  .project(target: "Core", path: .relativeToRoot("Core"))
] + .indigoFoundation
```

### Adding New Dependencies

1. Add package to `Package.swift` dependencies
2. Mark as `.framework` in `productTypes` if shared across targets
3. Add to `.indigoFoundation` helper in `Project+Templates.swift`
4. Install and validate:

   ```sh
   tuist install
   tuist generate
   tuist inspect implicit-imports
   tuist inspect redundant-imports
   ```

### Making Project Changes

After modifying Tuist project files (e.g., adding targets):

```sh
tuist generate
```

To update Tuist itself:

```sh
mise up --bump
```

## Included Modules

All targets support iOS 26.0+ and macOS 26.0+.

- **App** - Main application with an example notes screen
- **Core** - Business logic, database, models, and shared clients
- **Components** - Dependency-free reusable UI components
- **NotesListFeature/NoteEditorFeature** - Example TCA feature modules (a note-taking flow)

Schemes: **Indigo** (Debug) and **Indigo Release** run the app; **AllTests** runs every module's test suite.
