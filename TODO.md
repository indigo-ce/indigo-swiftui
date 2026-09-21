# Template Project TODOs

## Architecture Sync

Ordered by priority; where an item depends on an earlier one it says so. Each is
scoped to one focused pull request. Validate Swift changes with
`mise exec -- tuist generate --no-open` followed by `mise exec -- tuist build`;
do not rely on a simulator run.

### 1. Take the launch token refresh off the app's first frame

- [ ] **Gap.** `RootFeature`'s `.task` in `RootFeature/Sources/RootView.swift`
      awaits `authClient.refreshExpiredTokens()` and only afterwards sends
      `.sessionLoaded`, which flips `isSessionLoaded` and lets `RootView` swap
      its `ProgressView` for `NotesListView`. That one call does two very
      different things: `loadSession()`, a local keychain read, and — only when
      the stored access token has already expired — a network round trip to
      `api/v1/auth/refresh-access`. Gating the first frame on the second means a
      cold launch with stored-but-expired tokens on a slow or unreachable
      network holds the whole UI behind a spinner until that request times out,
      even though everything `RootView` shows comes from the local database
      (`NotesListFeature` → `notesClient` → `@Dependency(\.defaultDatabase)`)
      and needs no session at all. `docs/api-clients.md` presents this shape as
      "the shipped launch call site to copy", so every clone inherits it.
      Second half of the same gap: `RootFeature.State` declares
      `@Shared(.authSession) var authSession` and no code anywhere in the
      template reads it. The rule the guide states in prose — `.expired` still
      holds a usable refresh token, so it counts as signed in, and only
      `.missing`/`nil` mean "no session" — has no expression in code, so a clone
      writing its first auth-gated screen has nothing to copy and will reach for
      `case .valid` alone.
- **Desired behavior.** "Ready" means the persisted session has been restored
  from the keychain — a local operation that cannot stall. The network refresh
  settles afterwards in the background and republishes `@Shared(.authSession)`
  when it lands. The signed-in test lives in one named place that tests pin.
- **Scope.** `RootFeature/Sources/RootView.swift`,
  `RootFeature/Tests/RootFeatureTests.swift`, and the "Session Lifecycle"
  section of `docs/api-clients.md`. No other module changes; no new dependency,
  action-level API for features, or UI beyond what is listed here.
  - Split the `.task` effect into `try? await authClient.loadSession()`, then
    `await send(.sessionLoaded)`, then `try? await
    authClient.refreshExpiredTokens()`. Both `try?`s stay, for the reason the
    existing comment already gives: a first launch with no stored tokens throws
    `AuthTokens.Error.missingToken`, and a transient network failure must not
    block the app.
  - Keep `isSessionLoaded` and the `ProgressView` branch — the gate still stops
    a clone's login screen from flashing before the keychain restore lands — but
    rewrite the `RootFeature` doc comment and the `.task` comment to say the
    gate waits on the keychain read only and must never wait on the network.
  - Add `public var isAuthenticated: Bool` to `RootFeature.State`: `true` for
    `.valid` and `.expired`, `false` for `.missing` and `nil`, with a comment
    explaining that `.expired` still carries a usable refresh token and the next
    `sendAuthenticated` refreshes it silently, so treating it as signed out
    would bounce a user to a login screen for a merely stale access token.
  - Update the three existing tests: assertions about the post-refresh session
    (`access == "fresh"`, `authSession == nil`, `access == "stale"`) now belong
    after `await store.finish()`, because `.sessionLoaded` no longer implies the
    refresh has run. Assert `isAuthenticated` alongside each one — `true` after
    a successful refresh, `false` after a rejected one, `true` after a transient
    failure, which is the case that pins the `.expired` rule.
  - Add one test proving the gate no longer waits on the network: give `refresh`
    a closure that suspends on a continuation the test owns, assert
    `.sessionLoaded` arrives and `isSessionLoaded` is `true` while the refresh is
    still suspended, then resume the continuation before `await store.finish()`
    so the effect can complete.
  - In `docs/api-clients.md`, rewrite the `loadSession()` bullet to describe the
    two-step launch (restore, render, then refresh), change the readiness
    sentence so it says the gate waits on the keychain restore rather than on
    `refreshExpiredTokens()`, and point the `.expired` bullet at
    `RootFeature.State.isAuthenticated` as the shipped example of the rule.
- **Dependencies.** None. `isAuthenticated` reads the session through
  `RootFeature.State`, so `RootFeatureTests` needs no `import Sharing` and this
  item does not wait on item 2.
- **Acceptance.** `.sessionLoaded` is sent before `refreshExpiredTokens()` is
  awaited, and no code path gates rendering on the refresh; `isAuthenticated`
  returns `true` for `.expired`; the new suspended-refresh test fails if the two
  calls are put back in the old order; `docs/api-clients.md` no longer says
  `loadSession()` runs "together with `refreshExpiredTokens()`".
- **Validation.** `mise exec -- tuist generate --no-open`,
  `mise exec -- tuist build`, then `mise exec -- tuist test AllTests`.

### 2. Extend `usesSharing` to the generated test targets

- [ ] **Gap.** `Project.framework(usesSharing:)` in
      `Tuist/ProjectDescriptionHelpers/Project+Templates.swift:36-86` builds
      `baseSettings` at `:43-49` and applies
      `-module-alias Sharing=SwiftSharing` to the framework target only. The
      `\(name)Tests` target it generates alongside (`:75-83`) is declared with
      no `settings:` at all, so `import Sharing` in
      `Core/Tests/…` or `RootFeature/Tests/…` fails with an unresolved module
      even though the project passed `usesSharing: true`. The app target already
      had this fixed by hand (`App/Project.swift:38` and `:54` set the flag on
      both the app and its test target), so the helper is now the only place
      where the rule does not hold. This bites first on auth work: a clone
      testing session state has to construct `@Shared(.authSession)` in the test
      target, which needs the alias.
- **Desired behavior.** `usesSharing: true` covers a project's framework target
  and its test target, so a target that can use `Sharing` can also be tested
  against it.
- **Scope.** In `Project.framework`, build a second settings dictionary that
  carries only `"OTHER_SWIFT_FLAGS": "$(inherited) -module-alias Sharing=SwiftSharing"`
  when `usesSharing` is `true` (empty otherwise), and pass it as the
  `\(name)Tests` target's `settings:`. Do not copy `DEFINES_MODULE` or
  `SWIFT_VERSION` onto the test target — the flag is the whole change. Update
  the `AGENTS.md` "Dependencies" paragraph so the rule reads that
  `usesSharing: true` aliases the framework **and** its test bundle. Touch no
  per-project `Project.swift`, `Package.swift`, or `App/Project.swift`.
- **Acceptance.** After generation, `CoreTests` and `RootFeatureTests` carry
  `-module-alias Sharing=SwiftSharing` in `OTHER_SWIFT_FLAGS`, while
  `ComponentsTests`, `NotesListFeatureTests`, and `NoteEditorFeatureTests`
  (projects that do not pass `usesSharing`) do not.
- **Validation.** `mise exec -- tuist generate --no-open`, then
  `rg -n 'module-alias' Core/Core.xcodeproj/project.pbxproj` to confirm the test
  target picked it up. Temporarily add `import Sharing` to
  `Core/Tests/CoreTests.swift`, run `mise exec -- tuist test AllTests`, and
  revert the import before committing.

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
