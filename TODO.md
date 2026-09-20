# Template Project TODOs

## Architecture Sync

Ordered by priority; where an item depends on an earlier one it says so. Each is
scoped to one focused pull request. Validate Swift changes with
`mise exec -- tuist generate --no-open` followed by `mise exec -- tuist build`;
do not rely on a simulator run.

### 1. Bootstrap the stored auth session at the app root

- [ ] **Gap.** The template ships a complete auth stack that nothing switches on.
      `Core/Sources/Clients/JWTAuthClient+Live.swift` implements the refresh
      contract, `.indigoFoundation` links `JWTAuth` and `SimpleKeychain`, and
      `AGENTS.md` sells "JWTAuth with automatic token refresh" — but
      `App/Sources/IndigoApp.swift` builds a `NotesListFeature` store directly
      and its only `prepareDependencies` work is the database. No code calls
      `jwtAuthClient.refreshExpiredTokens()` or `loadSession()`, so the tokens
      `JWTAuth` persists to the keychain are never read back into
      `@Shared(.authSession)` at launch and the live `refresh` closure has no
      production call site. A cloned project inherits an auth stack that is
      linked, documented, and inert.
- **Desired behavior.** On launch the app restores the keychain session into
  `@Shared(.authSession)`, refreshes an expired access token before any feature
  runs, and renders content only once that has settled. A failure to restore is
  never fatal: no tokens at all is the normal first-run state.
- **Scope.** Add a `RootFeature` framework project — the app's composition root
  — and make it the root of the scene.
  - `RootFeature/Project.swift`:
    ```swift
    let project = Project.framework(
      name: "RootFeature",
      dependencies: [
        .project(target: "Core", path: .relativeToRoot("Core")),
        .project(target: "NotesListFeature", path: .relativeToRoot("NotesListFeature"))
      ] + .indigoFoundation,
      testDependencies: .indigoFoundation,
      usesSharing: true
    )
    ```
  - `RootFeature/Sources/RootView.swift` holds the reducer *and* the view, the
    same single-file shape `NotesListFeature/Sources/NotesListView.swift` uses.
    `State` carries `@Shared(.authSession) public var authSession: AuthSession?`,
    `var isSessionLoaded = false`, and `var notesList = NotesListFeature.State()`.
    `Action` is `task`, `sessionLoaded`, `notesList(NotesListFeature.Action)`.
    `.task` returns
    `.run { send in try? await authClient.refreshExpiredTokens(); await send(.sessionLoaded) }`
    — the `try?` is deliberate and must carry a comment: with no stored tokens
    the call throws `AuthTokens.Error.missingToken`, which is the expected
    first-launch path, and a transient network failure must not block the app.
    `.sessionLoaded` sets `isSessionLoaded = true`. Scope `NotesListFeature`
    with `Scope(state: \.notesList, action: \.notesList)`. `RootView` renders
    `NotesListView` once `isSessionLoaded` is true and a `ProgressView`
    otherwise, and fires `store.send(.task)` from `.task`.
  - `Workspace.swift`: add `"RootFeature"` to `projects` and a
    `.testableTarget(target: .project(path: "RootFeature", target: "RootFeatureTests"))`
    entry to the `AllTests` scheme.
  - `App/Project.swift`: replace the `NotesListFeature` project dependency with
    `RootFeature` (it re-exports the feature through the graph).
  - `App/Sources/IndigoApp.swift`: build the store from `RootFeature` and render
    `RootView`. Keep the existing `#if DEBUG` shake-to-console wiring attached to
    the new root view, unchanged.

  Do not add sign-in/sign-out UI, an `isAuthenticated` gate, or any new model —
  those are product decisions a clone makes. This item wires the lifecycle only.
- **Acceptance.** `RootFeature` appears in `Workspace.swift`, `AllTests`, and
  `App/Project.swift`; `IndigoApp` no longer constructs a `NotesListFeature`
  store; `refreshExpiredTokens()` runs exactly once per launch from `.task`; a
  launch with an empty keychain reaches `isSessionLoaded == true` without
  surfacing an error.
- **Validation.** `mise exec -- tuist generate --no-open` then
  `mise exec -- tuist build`. Add `RootFeatureTests` with three `TestStore`
  cases, all driving `.task` and receiving `.sessionLoaded`. Stub
  `keychainClient.load = { _ in "stale" }`, `keychainClient.save = { _, _ in }`,
  `keychainClient.delete = { _ in }`, and `authTokensClient = .liveValue` so the
  real persistence path runs against the stub keychain. The non-JWT strings make
  `AuthTokens.toSession()` report `.expired`, which is what drives the refresh —
  no signed fixture token is needed.
  1. `jwtAuthClient.refresh = { _ in AuthTokens(access: "fresh", refresh: "fresh") }`
     → `authSession?.tokens?.access == "fresh"`.
  2. `jwtAuthClient.refresh = { _ in throw AuthTokens.Error.refreshRejected }`
     → `authSession == nil` (credentials destroyed).
  3. `jwtAuthClient.refresh = { _ in throw URLError(.timedOut) }`
     → `authSession?.tokens?.access == "stale"` (tokens preserved).

  All three must still reach `isSessionLoaded == true`. Run with
  `mise exec -- tuist test AllTests`.

### 2. Share one immutable network session across `Core` clients

- [ ] **Gap.** `Core/Sources/Clients/JWTAuthClient+Live.swift:9-12` declares
      `nonisolated(unsafe) var indigoSession: URLSessionProtocol` at module
      scope. It is a **mutable** global that opts out of concurrency checking,
      and it does not need to be either: `URLSessionProtocol` is declared
      `Sendable` by `Pulse`, so `any URLSessionProtocol` is a `Sendable` type and
      a plain `let` is concurrency-safe without the annotation. Every cloned
      project copies an unsafe mutable global as the template's example of how to
      hold a session. It also lives inside the auth file, so the next client
      added to `Core/Sources/Clients` has no obvious shared session to reuse and
      will declare a second one — defeating the DEBUG capture that item 9 wired
      up, since only proxied sessions reach the console.
- **Desired behavior.** One session value, immutable, declared somewhere a new
  client will find it.
- **Scope.** Move the declaration to a new
  `Core/Sources/Clients/NetworkSession.swift`, change it to
  `let indigoSession: URLSessionProtocol = …` and drop `nonisolated(unsafe)`.
  Keep the `#if DEBUG` `URLSessionProxy` / `#else` `URLSession` split and the
  `indigoSession` name exactly as they are. Add a doc comment stating that every
  client in `Core` should pass this as `urlSession:` so DEBUG builds capture all
  traffic in one console. Remove the now-unused `import Pulse` from
  `JWTAuthClient+Live.swift` only if nothing else in that file needs it.
- **Acceptance.** `rg 'nonisolated\(unsafe\)' Core/` returns nothing;
  `indigoSession` is declared exactly once, as a `let`, in `NetworkSession.swift`;
  the refresh call still passes `urlSession: indigoSession`.
- **Validation.** `mise exec -- tuist generate --no-open`, then
  `mise exec -- tuist build Indigo --configuration Debug` and
  `mise exec -- tuist build "Indigo Release" --configuration Release` to prove
  both `#if` branches still compile. `mise exec -- tuist test AllTests` stays
  green, and `mise exec -- tuist inspect implicit-imports` reports nothing new.

### 3. Correct the authentication section of `docs/api-clients.md`

- [ ] **Gap.** The guide misstates the library contract it documents. Lines
      309–314 claim `sendAuthenticated` "retrieves the current access token",
      "if the request fails with 401, automatically refreshes the token", and
      "retries the original request with the new token". `JWTAuthClient`
      does none of that: `sendAuthenticated` calls `refreshExpiredTokens()`
      *before* sending, based on locally decoding the access token's expiry, and
      there is **no** 401 retry — a 401 from a business endpoint propagates to
      the caller untouched. A reader who trusts the doc writes no 401 handling
      and gets silent failures. The section is also silent on the session
      lifecycle a clone has to implement (where tokens live, who persists them,
      what happens after a rejected refresh), and its `JWTAuthClient+Live`
      snippet omits the `urlSession:` argument the shipped file passes. Do this
      after items 1 and 2 so it can point at the real launch call site and the
      final session declaration.
- **Desired behavior.** The section describes what the linked packages actually
  do and gives a clone the whole session lifecycle in one place.
- **Scope.** Documentation only.
  - Rewrite the numbered `sendAuthenticated` list: it refreshes first when the
    stored access token has already expired, attaches
    `Authorization: Bearer <token>`, and sends once. Say explicitly that a 401
    from a business endpoint is **not** retried and is the caller's to handle —
    cross-reference the `APIErrorBody` section for reading the body.
  - Add a "Session lifecycle" subsection covering: `@Shared(.authSession)` as
    the single in-memory source of truth (`.missing` / `.expired` / `.valid`);
    `authTokensClient.save`/`destroy`/`set` as the only writers, which update
    memory *and* the keychain together; `loadSession()` restoring the keychain
    into memory on launch; and the fact that `refreshExpiredTokens()` returns
    **without throwing** when the server rejects the refresh token — it destroys
    the credentials, and the next `sendAuthenticated` is what throws
    `AuthTokens.Error.missingToken`. Point at the root feature added in item 1 as
    the launch call site.
  - Note that `.expired` still holds a usable refresh token, so UI should treat
    it as signed in rather than falling back to a login screen; only `.missing`
    and `nil` mean "no session".
  - Add `urlSession: indigoSession` to the refresh snippet so it matches
    `Core/Sources/Clients/JWTAuthClient+Live.swift`.
- **Acceptance.** No sentence in the guide claims a 401 retry or an automatic
  post-failure refresh; the session-lifecycle subsection exists and names
  `@Shared(.authSession)`, `authTokensClient`, and `loadSession()`; the refresh
  snippet is a character-for-character match with the shipped closure body.
- **Validation.** Cross-read each snippet against
  `Core/Sources/Clients/JWTAuthClient+Live.swift`,
  `Core/Sources/Clients/NetworkSession.swift`, and the `RootFeature` source. No
  build required.

### 4. Give the `App` target the `Sharing` module alias

- [ ] **Gap.** `AGENTS.md` states the rule "any target that imports `Sharing`
      must be declared with `usesSharing: true`", but that rule is
      unsatisfiable for the one target it matters most for. `App/Project.swift`
      declares its target with a raw `.target(…)` call, not
      `Project.framework(…)`, so there is no `usesSharing` switch and no
      `-module-alias Sharing=SwiftSharing` in its `OTHER_SWIFT_FLAGS`. Adding
      `import Sharing` to `App/Sources/IndigoApp.swift` fails with an unresolved
      module and the documented fix does not apply. The app target is where a
      clone adds scene-level shared state, so this is a trap with no signpost.
- **Desired behavior.** The app target obeys the same alias rule as every
  framework target, and `AGENTS.md` says how.
- **Scope.** Add
  `"OTHER_SWIFT_FLAGS": "$(inherited) -module-alias Sharing=SwiftSharing"` to the
  app target's base settings in `App/Project.swift`, and the same to the
  `\(appTarget.targetName)Tests` target so a test can import `Sharing` too (that
  target currently passes no `settings:` at all — add one). Extend the
  `AGENTS.md` "Dependencies" rule with a sentence covering the app target: it is
  declared directly rather than through `Project.framework`, so it sets the flag
  by hand. Change nothing in `Package.swift` or `Project+Templates.swift`.
- **Acceptance.** The generated app and test targets both carry
  `-module-alias Sharing=SwiftSharing` in `OTHER_SWIFT_FLAGS`; `AGENTS.md`
  documents the manual form.
- **Validation.** `mise exec -- tuist generate --no-open`, then
  `mise exec -- tuist build`. Temporarily add `import Sharing` to
  `App/Sources/IndigoApp.swift` and to `App/Tests/AppTests.swift`; both must
  compile. Revert both before committing.

### 5. Map the version build settings into the app's `Info.plist`

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
