# AGENTS.md

Guidance for coding agents working in this repository (Claude Code, Codex, Cursor, or any tool that reads `AGENTS.md`).

## What this is

Indigo is a SwiftUI app **template** for iOS 26+ / macOS 26+. It ships a working note-taking app demonstrating TCA (state), SQLiteData/GRDB (persistence), SwiftSharing (reactive state), and Tuist (project generation). Everything here is inherited by every project cloned from the template — keep changes exemplary and generic.

## Build & test

Uses **Tuist** (pinned via `mise`). This is a generated project — never hand-edit the `.xcworkspace`/`.xcodeproj`; change the manifests and regenerate.

```bash
mise install                 # toolchain (Tuist)
tuist install                # SPM dependencies
tuist generate --no-open
tuist test --platform ios    # or: --platform macos
```

- Regenerate after any change to `Package.swift`, `Workspace.swift`, or a `Project.swift`.
- `AllTests` is the workspace scheme that runs every module's test bundle (`tuist test AllTests`, or ⌘U in Xcode).
- Check import hygiene with `tuist inspect implicit-imports` / `tuist inspect redundant-imports`.

## Layout

- **App/** — app entry point and screens.
- **Core/** — models, database + migrations, and clients (`Core/Sources/Clients`).
- **Components/** — dependency-free reusable SwiftUI components.
- **NotesListFeature/**, **NoteEditorFeature/** — example TCA features, each its **own framework target** (not folders under `App`).
- **Tuist/ProjectDescriptionHelpers/** — `Config.swift` (`teamReverseDomain`, `appTarget`) and `Project+Templates.swift` (`.indigoFoundation`, `Project.framework()`).

## Dependencies

External packages flow through the `.indigoFoundation` helper (prevents double-linking). To add one:

1. Add the package to `Package.swift`.
2. Add its product to `frameworkProductTypes` in `Package.swift`.
3. Add `.external(name:)` to `.indigoFoundation` in `Project+Templates.swift`.
4. Run `tuist install && tuist generate`.

## Conventions

- **Features:** `XFeature` for the `@Reducer`, `XView` for the SwiftUI view.
- **Persistence:** SQLiteData `@Table` models; read reactively with `@FetchAll` (wrap it in `@ObservationStateIgnored` inside `@ObservableState`); write with the structured query API (`insert` / `upsert` / `where { … }.delete()`).
- **Clients:** TCA `@DependencyClient` structs — see `Core/Sources/Clients`.
- **Networking / auth:** `JWTAuthClient+Live` demonstrates the token-refresh contract — map a **401** from `/auth/refresh` to `AuthTokens.Error.refreshRejected` (the only error that wipes credentials); let every other failure propagate so a transient outage doesn't log the user out.
- Swift 6 strict concurrency; 2-space indentation (see `.swift-format`).

## Multi-platform

iOS and macOS share one codebase; per-platform entitlements live in `App/ios.entitlements` and `App/mac.entitlements`.
