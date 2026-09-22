# Template Project TODOs

## Architecture Sync

Ordered by priority; where an item depends on an earlier one it says so. Each is
scoped to one focused pull request. Validate Swift changes with
`mise exec -- tuist generate --no-open` followed by `mise exec -- tuist build`;
do not rely on a simulator run.

### 1. Extend `usesSharing` to the generated test targets

- [x] **Gap.** `Project.framework(usesSharing:)` in
      `Tuist/ProjectDescriptionHelpers/Project+Templates.swift:36-86` builds
      `baseSettings` at `:43-49` and applies
      `-module-alias Sharing=SwiftSharing` to the framework target only. The
      `\(name)Tests` target it generates alongside (`:75-83`) is declared with
      no `settings:` at all, so `import Sharing` in
      `Core/Tests/…` or `RootFeature/Tests/…` fails with an unresolved module
      even though the project passed `usesSharing: true`. The app target already
      had this fixed by hand (`App/Project.swift:38` and `:54` set the flag on
      both the app and its test target), so the helper is now the only place
      where the rule does not hold. `Core/Project.swift:8` and
      `RootFeature/Project.swift:11` both pass `usesSharing: true`, so both have
      a test bundle that cannot name the module its own sources depend on. This
      bites first on auth work: a clone testing session state has to construct
      `@Shared(.authSession)` in the test target, which needs the alias.
- **Desired behavior.** `usesSharing: true` covers a project's framework target
  and its test target, so a target that can use `Sharing` can also be tested
  against it.
- **Scope.** In `Project.framework`, build a second settings dictionary that
  carries only `"OTHER_SWIFT_FLAGS": "$(inherited) -module-alias Sharing=SwiftSharing"`
  when `usesSharing` is `true` (empty otherwise), and pass it as the
  `\(name)Tests` target's `settings:`. Do not copy `DEFINES_MODULE` or
  `SWIFT_VERSION` onto the test target — the flag is the whole change. Update
  the `AGENTS.md` "Dependencies" paragraph (`:43`) so the rule reads that
  `usesSharing: true` aliases the framework **and** its test bundle. Touch no
  per-project `Project.swift`, `Package.swift`, or `App/Project.swift`.
- **Dependencies.** None.
- **Acceptance.** After generation, `CoreTests` and `RootFeatureTests` carry
  `-module-alias Sharing=SwiftSharing` in `OTHER_SWIFT_FLAGS`, while
  `ComponentsTests`, `NotesListFeatureTests`, and `NoteEditorFeatureTests`
  (projects that do not pass `usesSharing`) do not.
- **Validation.** `mise exec -- tuist generate --no-open`, then
  `rg -n 'module-alias' Core/Core.xcodeproj/project.pbxproj` to confirm the test
  target picked it up. Temporarily add `import Sharing` to
  `Core/Tests/JSONCodersTests.swift`, run `mise exec -- tuist test AllTests`, and
  revert the import before committing.

### 2. Wipe the user-scoped cache when the auth session changes

- [ ] **Gap.** The template persists an auth session and a local SQLite cache and
      never connects them. `RootFeature` (`RootFeature/Sources/RootView.swift:18`)
      holds `@Shared(.authSession)` and reads it exactly once per launch: `.task`
      calls `loadSession()` / `refreshExpiredTokens()` (`:58-68`) and nothing ever
      observes the value again. Meanwhile `notes` — the only table
      `Core/Sources/Database/Migrations.swift:3-16` creates — is per-user data
      that outlives the session: the sole row deletion in the codebase is
      `NotesClient.delete` for a single id (`Core/Sources/Clients/NotesClient.swift:45-49`),
      so `rg -n 'clearUserCache|wipe' Core/ RootFeature/` returns nothing. A clone
      that adds sign-in/sign-out therefore leaks one account's cached rows into
      the next account's session, and `state.notesList.notes` keeps rendering rows
      for a session that has already ended. There is also no single place to
      register teardown for the next user-scoped table a clone adds.
- **Desired behavior.** Core owns one documented function that clears every
  user-scoped table, and the composition root calls it whenever the signed-in
  identity changes or the session ends — with the feature state that was showing
  those rows reset in the same transition.
- **Scope.** Three files plus tests.
  - New `Core/Sources/Database/UserCacheReset.swift`:

    ```swift
    import Foundation
    import SQLiteData

    /// Clears every user-scoped cached table. Call when the signed-in user
    /// changes or the session ends.
    ///
    /// When you add a user-scoped table, add its delete here — this is the one
    /// place the app tears down per-account data.
    public func clearUserCache(_ writer: any DatabaseWriter) async throws {
      try await writer.write { db in
        try Note.delete().execute(db)
      }
    }
    ```

    `SQLiteData` re-exports `DatabaseWriter`, which is how
    `Core/Sources/Database/Connection.swift:9` already spells its return type —
    do not add a `GRDB` import.
  - In `RootFeature/Sources/RootView.swift`, add to `State` a
    `@Shared(.appStorage("lastSignedInUserId")) public var lastSignedInUserId: String?`,
    add `case sessionChanged(AuthSession?)` and `case userCacheWiped` to `Action`,
    and add `@Dependency(\.defaultDatabase) var database`.
  - In the `.sessionLoaded` case, alongside setting `isSessionLoaded = true`:
    record the current identity if it is not yet known
    (`if state.lastSignedInUserId == nil, case .valid(let tokens) = state.authSession`
    then `state.$lastSignedInUserId.withLock { $0 = tokens[string: "sub"] }`), and
    return a long-running effect that forwards later session values:

    ```swift
    .run { [authSession = state.$authSession] send in
      for await session in authSession.publisher.values.dropFirst() {
        await send(.sessionChanged(session))
      }
    }
    ```

    `.dropFirst()` is load-bearing: the publisher replays the current value, and
    without it every launch would wipe the cache before the user has done
    anything.
  - `.sessionChanged(session)`: on `.valid(let tokens)`, compare
    `tokens[string: "sub"]` against `state.lastSignedInUserId`, return `.none`
    when they match (an ordinary token rotation must not wipe anything), and
    otherwise store the new id and wipe. On `.missing` / `nil` / `.expired`,
    wipe unconditionally — a session that has gone away or is no longer valid
    must not leave cached rows behind. The wipe is an effect that calls
    `clearUserCache(database)` and sends `.userCacheWiped`; log and swallow a
    throw rather than crashing, matching how `.task` already tolerates failure.
  - `.userCacheWiped`: `state.notesList = NotesListFeature.State()`, then
    `return .send(.notesList(.onAppear))` so the list reloads from the now-empty
    table instead of showing stale rows. Resetting the state *after* the delete
    completes is the point — a refetch issued before the wipe would have its rows
    deleted out from under it.
  - Do not add a sign-in or sign-out screen, do not add an API endpoint, and do
    not touch `NotesClient`, `NotesListFeature`, or `JWTAuthClient+Live.swift`.
    This item wires the seam; producing a session change is the clone's job.
- **Dependencies.** Item 1. `RootFeatureTests` needs the `Sharing` module alias
  to construct session values directly in the test bundle.
- **Acceptance.** `clearUserCache` is public in `Core` and empties `notes`.
  Driving `RootFeature` from `.valid(tokens(sub: "a"))` to
  `.valid(tokens(sub: "b"))` deletes the rows, resets `notesList`, and refetches;
  driving it to `.missing` does the same; a second `.valid` carrying the same
  `sub` deletes nothing. A plain launch — `.task` through `.sessionLoaded` with no
  subsequent change — leaves existing rows intact.
- **Validation.** `mise exec -- tuist generate --no-open`,
  `mise exec -- tuist build`, then `mise exec -- tuist test AllTests`. Add a
  `Core/Tests/UserCacheResetTests.swift` suite that builds a database with
  `withDependencies { $0.context = .test }` + `appDatabase()` (which already
  gives each test its own temp file), inserts two notes, calls `clearUserCache`,
  and asserts the table is empty. Add the `RootFeature` transitions above to
  `RootFeatureTests`, reusing its `makeStore` keychain stubs. While you are in
  `Core/Tests`, delete the `testTwoPlusTwoIsFour` placeholder suite in
  `Core/Tests/CoreTests.swift` — the new suite replaces it and the four other
  suites keep the target populated.

### 3. Map the version build settings into the app's `Info.plist`

- [ ] **Gap.** `Configs/Debug.xcconfig` and `Configs/Release.xcconfig` set
      `MARKETING_VERSION=0.0.1` and `CURRENT_PROJECT_VERSION=1`, and
      `Core/Sources/Bundle+Extension.swift` ships `releaseVersionNumber`,
      `buildVersionNumber`, and `fullVersionString`, which read
      `CFBundleShortVersionString` and `CFBundleVersion` out of the Info.plist.
      Nothing connects the two: `App/Project.swift` passes
      `infoPlist: .extendingDefault(with:)` with only `UILaunchScreen`, so the
      bundle gets Tuist's defaults and the xcconfig values never reach it.
      Bumping the version in the xcconfig — the one place a clone would look —
      changes nothing the app can report.
- **Desired behavior.** The xcconfig is the single place a version is set, and
  the bundle reflects it.
- **Scope.** Add `"CFBundleShortVersionString": "$(MARKETING_VERSION)"` and
  `"CFBundleVersion": "$(CURRENT_PROJECT_VERSION)"` to the `.extendingDefault`
  dictionary in `App/Project.swift`. Do not change the values in either
  xcconfig, do not touch `Bundle+Extension.swift`, and do not add a plist to any
  framework target — only the app bundle carries a user-facing version.
- **Dependencies.** None.
- **Acceptance.** The generated app Info.plist under `App/Derived/InfoPlists/`
  (filename follows `appTarget`) contains both keys with the `$(…)` references,
  and a Debug build resolves `CFBundleShortVersionString` to `0.0.1`.
- **Validation.** `mise exec -- tuist generate --no-open`, then
  `rg 'MARKETING_VERSION|CURRENT_PROJECT_VERSION' App/Derived/InfoPlists/`.
  Build with `mise exec -- tuist build` and read
  `CFBundleShortVersionString` back out of the built `Info.plist` with
  `plutil -p`.

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
