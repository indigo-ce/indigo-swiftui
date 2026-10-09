# Template Project TODOs

## Architecture Sync

Ordered by priority; where an item depends on an earlier one it says so. Each is
scoped to one focused pull request. Validate Swift changes with
`mise exec -- tuist generate --no-open` followed by `mise exec -- tuist build`;
do not rely on a simulator run.

### 1. Move the cache database out of Documents and split it by configuration

- [ ] **Gap.** `appDatabase()` in `Core/Sources/Database/Connection.swift`
      opens the live database at `URL.documentsDirectory/db.sqlite`. That
      database is a regenerable, user-scoped cache (see
      `docs/local-caching.md` and `UserCacheReset`). Documents is the
      user-facing folder: it is backed up to iCloud, and it becomes visible
      in Files as soon as a cloner enables file sharing. Debug and Release
      also share the one file. On a device that runs both the `Indigo` and
      `Indigo Release` schemes, the DEBUG-only
      `eraseDatabaseOnSchemaChange` can wipe the Release build's cache, and a
      Debug schema in progress can leak into Release runs.
- **Desired behavior.** The live cache lives under Application Support, out
  of the user's Documents, with a separate file per build configuration.
- **Scope.** In the `.live` branch of `appDatabase()`, resolve
  `URL.applicationSupportDirectory`, create it with
  `FileManager.default.createDirectory(at:withIntermediateDirectories: true)`
  (it does not exist on first launch), and open `cache-debug.sqlite` under
  `#if DEBUG` and `cache.sqlite` otherwise. Leave the preview (in-memory) and
  test (per-test temp file) branches, the migrator, and the trace setup
  untouched. Make it a clean cutover with no migration from the old
  Documents path; the template has no installed base. Update the `.live`
  path in the `appDatabase()` sample in `docs/local-caching.md` to match.
- **Dependencies.** None.
- **Acceptance.** `Connection.swift` and `docs/local-caching.md` have no
  `documentsDirectory` reference left. The live path is under Application
  Support, and the file name differs between Debug and Release. The
  directory is created before `DatabasePool` opens. Existing `CoreTests` and
  `RootFeatureTests` stay unchanged, because they run under the test
  context.
- **Validation.** `grep -rn documentsDirectory Core docs` returns nothing,
  then `mise exec -- tuist generate --no-open` and `mise exec -- tuist build`.

### 2. Adopt Xcode's recommended build settings in the App xcconfigs

- [ ] **Gap.** The framework projects get `ENABLE_MODULE_VERIFIER`,
      `MODULE_VERIFIER_SUPPORTED_LANGUAGE_STANDARDS` and
      `STRING_CATALOG_GENERATE_SYMBOLS` from
      `Tuist/ProjectDescriptionHelpers/Project+Templates.swift`. The `App`
      project takes its settings only from `Configs/Debug.xcconfig` and
      `Configs/Release.xcconfig`, and neither file sets those keys or
      `REGISTER_APP_GROUPS`. Xcode 26 therefore raises "Update to recommended
      settings" on the `App` project. Accepting the prompt in Xcode does not
      stick, because the next `tuist generate` throws the change away, so
      every clone keeps seeing the warning.
- **Desired behavior.** The `App` project carries the same recommended
  settings as the framework template, persisted in the xcconfigs so they
  survive regeneration.
- **Scope.** In the `// Xcode` section of both xcconfigs, add
  `ENABLE_MODULE_VERIFIER=YES`,
  `MODULE_VERIFIER_SUPPORTED_LANGUAGE_STANDARDS="gnu11 gnu++14"`,
  `REGISTER_APP_GROUPS=YES` and `STRING_CATALOG_GENERATE_SYMBOLS=YES`, in
  the file's existing `KEY=VALUE` style. Do not change `App/Project.swift`,
  the framework template, or any other key.
- **Dependencies.** None.
- **Acceptance.** Both xcconfigs set all four keys to the values above, and
  the two files still differ only in their existing Debug/Release-specific
  lines.
- **Validation.** `grep -cE '^(ENABLE_MODULE_VERIFIER|MODULE_VERIFIER_SUPPORTED_LANGUAGE_STANDARDS|REGISTER_APP_GROUPS|STRING_CATALOG_GENERATE_SYMBOLS)=' Configs/Debug.xcconfig Configs/Release.xcconfig`
  reports 4 for each file, then `mise exec -- tuist generate --no-open` and
  `mise exec -- tuist build`.

## Completed

Shipped and merged; kept as a short record so the work is not re-proposed.

- [x] Upgrade the Swift toolchain and dependency graph
- [x] Declare `DependenciesMacros` in `.indigoFoundation`
- [x] Align `JSONCoders.api` with the JSON the template actually exchanges
- [x] Build the token-refresh request with `HTTPRequestBuilder`
- [x] Add `APIErrorBody` for reading 4xx response bodies
- [x] Rewrite `docs/api-clients.md` against the shipped code
- [x] Standardize runnable commands on `mise exec -- tuist`
- [x] Make the `Sharing` → `SwiftSharing` module alias usable by `Core`
- [x] Wire the DEBUG network console to the existing shake modifier
- [x] Bootstrap the stored auth session at the app root
- [x] Give the `App` target the `Sharing` module alias
- [x] Put the shared network session behind a `Core` dependency
- [x] Correct the authentication section of `docs/api-clients.md`
- [x] Lift the launch gate before the background token refresh
- [x] Ship the `apiClient` dependency alias in `Core`
- [x] Extend `usesSharing` to the generated test targets
- [x] Wipe the user-scoped cache when the auth session changes
- [x] Ship a sign-out seam that revokes the refresh token before ending the session
- [x] Let the sandboxed macOS app open outgoing network connections
- [x] Give `SessionClient` a sign-in operation that stores the issued tokens
- [x] Map the version build settings into the app's `Info.plist`
- [x] Send an explicit JSON content type on the sign-in request
- [x] Keep Xcode Cloud output alive while `tuist generate` runs
- [x] Point DEBUG builds at the local backend dev server
- [x] Bump the Tuist pin to 4.208.0
- [x] Ship an app privacy manifest
