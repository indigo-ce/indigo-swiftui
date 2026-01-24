# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Indigo is a SwiftUI app template for building iOS/macOS applications using modern architecture patterns. It provides a functional note-taking app that demonstrates:

- **TCA (The Composable Architecture)** for state management
- **SQLiteData** (GRDB-based) for persistence
- **SwiftSharing** for reactive state
- **Tuist** for project generation

The template targets iOS 26.0+ and macOS 26.0+.

## Build System & Development Commands

This project uses **Tuist** for project generation and workspace management:

```bash
# Install dependencies (via mise)
mise install

# Install Swift Package Manager dependencies
tuist install

# Generate Xcode workspace and projects
tuist generate --no-open

# Open the workspace
open Indigo.xcworkspace

# Run tests
tuist test
```

## Architecture Overview

### Modular Structure

```
indigo/
├── App/                    # Main application
│   └── Sources/
│       ├── Features/       # TCA-based features
│       │   ├── NotesListFeature.swift
│       │   ├── NotesListView.swift
│       │   ├── NoteEditorFeature.swift
│       │   └── NoteEditorView.swift
│       └── IndigoApp.swift # App entry point
├── Core/                   # Business logic and data layer
│   └── Sources/
│       ├── Models/         # Data models (Note.swift)
│       ├── Database/       # SQLite setup and migrations
│       ├── Clients/        # TCA dependencies (NotesClient.swift)
│       └── Extensions/     # Utility extensions
├── Components/             # Reusable UI components (no dependencies)
├── Tuist/                  # Project configuration
│   └── ProjectDescriptionHelpers/
│       ├── Config.swift           # App name, bundle ID
│       └── Project+Templates.swift # Framework template, dependencies
└── Package.swift           # External dependencies
```

### Dependency Graph

```
App
├── Core (business logic, database, models)
├── Components (reusable UI, no dependencies)
└── External packages (via .indigoFoundation helper)

Core → External packages (via .indigoFoundation helper)
Components → (no dependencies)
```

### Key Architectural Patterns

- **TCA (The Composable Architecture)** - State management via reducers and dependencies
- **SQLiteData** - Type-safe SQLite queries with `@Table` macro and reactive `@FetchAll`
- **SwiftSharing** - Shared state management with `SharedKey` pattern
- **Feature Modules** - Consistent naming: `XFeature` for reducers, `XView` for SwiftUI views

### Key Dependencies

- **ComposableArchitecture** - State management and dependency injection
- **SQLiteData** - Type-safe SQLite layer (replaces raw GRDB)
- **SwiftSharing** - Reactive shared state
- **JWTAuth** - Authentication with automatic token refresh
- **HTTPRequestBuilder/Client** - Type-safe HTTP networking
- **LoggingClient** - Structured logging
- **ComposableToasts** - Toast notification system
- **PulseUI** - Network debugging and logging

## Code Patterns

### Database Models

Models use the `@Table` macro for SQLite integration:

```swift
@Table
public struct Note: Identifiable, Codable, Hashable, Sendable {
  public let id: UUID
  public var title: String
  public var body: String
  public let createdAt: Date
  public var updatedAt: Date?
}
```

### TCA Features with SQLiteData

Features use `@FetchAll` for reactive database queries:

```swift
@Reducer
struct NotesListFeature {
  @ObservableState
  struct State {
    @ObservationStateIgnored
    @FetchAll var notes: [Note] = []
  }
}
```

### Database Operations

Use SQLiteData's structured query API:

```swift
// Fetch
try Note.fetchAll(db)
try Note.where { $0.id.eq(id) }.fetchOne(db)

// Insert
try Note.insert { Note.Draft(note) }.execute(db)

// Update
try Note.upsert { Note.Draft(note) }.execute(db)

// Delete
try Note.where { $0.id.eq(id) }.delete().execute(db)
```

### TCA Dependencies

Use `@DependencyClient` for TCA dependency injection:

```swift
@DependencyClient
public struct NotesClient: Sendable {
  public var fetchAll: @Sendable () async throws -> [Note]
  public var create: @Sendable (_ title: String, _ body: String) async throws -> Note
  public var update: @Sendable (_ note: Note) async throws -> Void
  public var delete: @Sendable (_ id: UUID) async throws -> Void
}
```

## Configuration

### Project Settings

Configuration is split between two files in `Tuist/ProjectDescriptionHelpers/`:

- **Config.swift** - App-specific settings:
  - `teamReverseDomain` - Bundle ID prefix (e.g., "com.example")
  - `appTarget` - App target reference

- **Project+Templates.swift** - Shared framework template and dependencies:
  - `.indigoFoundation` - Array of external dependencies
  - `Project.framework()` - Template for framework targets
  - Platform deployment targets and destinations

### Adding Dependencies

1. Add the package to `Package.swift`
2. Add to `frameworkProductTypes` list in Package.swift
3. Add to `.indigoFoundation` array in Project+Templates.swift
4. Run `tuist install && tuist generate`

## Multi-Platform Support

The app targets iOS and macOS with shared codebase. Separate entitlements are configured for each platform in `App/ios.entitlements` and `App/mac.entitlements`.

## Development Workflow

### After Dependency Changes

```bash
tuist install
tuist generate --no-open
```

### After Tuist Model Changes

```bash
tuist generate --no-open
```

### Checking for Import Issues

```bash
tuist inspect implicit-imports
tuist inspect redundant-imports
```
