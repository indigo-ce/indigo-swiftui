# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Indigo Stack CE is a template for building SwiftUI applications targeting Apple platforms (iOS 18.0+, macOS 15.0+). It provides a modular architecture with The Composable Architecture (TCA) for state management, demonstrating best practices for organizing multi-module Swift projects.

## Build System & Development Commands

This project uses **Tuist** for project generation and workspace management:

```bash
# Install dependencies (via mise)
mise install

# Install Swift Package Manager dependencies
tuist install

# Generate Xcode workspace and projects
tuist generate

# Open the workspace
open App.xcworkspace
```

The project requires Tuist 4.54.3+ and targets iOS 18.0+/macOS 15.0+.

## Architecture Overview

### Modular Structure

- **App/** - Main application with SwiftUI views and app entry point
- **Core/** - Business logic, data models, and shared utilities
- **Components/** - Reusable SwiftUI components with no external dependencies
- **FeatureA/** and **FeatureB/** - Example TCA-based feature modules

### Dependency Graph

```
App
├── Core (business logic)
├── Components (reusable UI components, no dependencies)
├── FeatureA (TCA-based feature)
├── FeatureB (TCA-based feature)
└── External packages (via .indigoFoundation helper)

Core → External packages (via .indigoFoundation helper)
FeatureA/FeatureB → External packages (via .indigoFoundation helper)
Components → (no dependencies)
```

### Key Architectural Patterns

- **TCA (The Composable Architecture)** - Complete state management via reducers and dependencies
- **Modular Design** - Clean separation of concerns across framework targets
- **Feature Modules** - Consistent naming convention (XFeature for reducers, XView for SwiftUI views)

### Key Dependencies

- **ComposableArchitecture** - State management and dependency injection
- **GRDB** - SQLite database layer
- **JWTAuth** - Authentication with automatic token refresh
- **LoggingClient** - Structured logging
- **ComposableToasts** - Toast notification system
- **Algorithms** - Swift standard library algorithms
- **Pulse/PulseUI** - Network debugging and logging
- **NetworkImage** - Async image loading

## Code Organization

### TCA State Management

- Feature-specific reducers handle individual screens
- Dependencies injected via TCA's dependency system
- External dependencies accessed via `.indigoFoundation` helper

### Module Philosophy

- **Components**: Intentionally kept dependency-free for maximum reusability across projects
- **Core**: Contains all business logic, models, and utilities
- **Feature Modules**: Follow consistent naming patterns (XFeature for reducers, XView for SwiftUI views)
- **Dependency Management**: External packages (TCA, GRDB, etc.) are managed via the `.indigoFoundation` helper in Project+Templates.swift

### Project Settings

- `OTHER_LDFLAGS` is set to `-ObjC` to support Objective-C dependencies
- Separate entitlements for iOS and macOS platforms
- Asset symbol generation enabled

## Development Workflow

### Current Branch Structure

- **main** - Production branch

### Updating Dependencies

If you make changes to `Package.swift` to add/update dependencies:

```bash
tuist install
tuist generate
```

### Editing Project Models

If you make changes to Tuist project models (e.g., adding a new target), regenerate the Xcode project:

```bash
tuist generate
```

### Module Testing

- Unit tests available for App target (AppTests)
- Use `tuist test` for running test suites
- Test plans available in `App/All.xctestplan`

## Multi-Platform Support

The app targets iOS and macOS with shared codebase and platform-specific optimizations. Separate entitlements are configured for each platform.

## Dependency Management

### External Dependencies

- External dependencies (TCA, GRDB, Pulse, etc.) are declared using the `.indigoFoundation` helper array in `Tuist/ProjectDescriptionHelpers/Project+Templates.swift`
- To prevent double-linking issues, ensure all external packages used by multiple targets are marked as `.framework` in `Package.swift`
- Run the following commands after making dependency changes:

  ```bash
  tuist install
  tuist generate
  tuist inspect implicit-imports
  tuist inspect redundant-imports
  ```
