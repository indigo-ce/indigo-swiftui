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
- **IndigoFoundation/** - Core TCA infrastructure and shared utilities
- **FeatureA/** and **FeatureB/** - Example TCA-based feature modules

### Dependency Graph

```
App
├── Core (business logic)
├── Components (reusable UI components, no dependencies)
├── FeatureA (TCA-based feature → IndigoFoundation)
└── FeatureB (TCA-based feature → IndigoFoundation)

IndigoFoundation (TCA shared utilities + external dependencies)
```

### Key Architectural Patterns

- **TCA (The Composable Architecture)** - Complete state management via reducers and dependencies
- **Modular Design** - Clean separation of concerns across framework targets
- **Feature Modules** - Consistent naming convention (XFeature for reducers, XView for SwiftUI views)

### Key Dependencies

- **ComposableArchitecture** - State management and dependency injection
- **GRDB** - SQLite database layer (available via IndigoFoundation)
- **JWTAuth** - Authentication with automatic token refresh
- **LoggingClient** - Structured logging
- **ComposableToasts** - Toast notification system
- **Algorithms** - Swift standard library algorithms

## Code Organization

### TCA State Management

- Feature-specific reducers handle individual screens
- Dependencies injected via TCA's dependency system
- IndigoFoundation provides shared TCA infrastructure

### Module Philosophy

- **Components**: Intentionally kept dependency-free for maximum reusability across projects
- **IndigoFoundation**: Consolidates all external dependencies and TCA infrastructure
- **Feature Modules**: Depend only on IndigoFoundation, follow consistent naming patterns

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
