# Template Project TODOs

## Architecture Sync

Ordered by priority; where an item depends on an earlier one it says so. Each is
scoped to one focused pull request. Validate Swift changes with
`mise exec -- tuist generate --no-open` followed by `mise exec -- tuist build`;
do not rely on a simulator run.

### 1. Put the shared network session behind a `Core` dependency

- [x] **Gap.** `Core/Sources/Clients/JWTAuthClient+Live.swift:8-12` declares
      `nonisolated(unsafe) var indigoSession: URLSessionProtocol` at module
      scope — a **mutable** global that opts out of concurrency checking. It is
      mutable only because `Core/Tests/JWTAuthClientLiveTests.swift:56-60`
      assigns to it to install a `URLProtocol` stub, so the one shipped example
      of injecting a session is "reach into another module's global and put it
      back in a `defer`", which forces the suite to stay `.serialized`. The
      declaration also lives inside the auth file, so the next client added under
      `Core/Sources/Clients` has no obvious session to reuse and will declare a
      second one — defeating the shipped DEBUG network console, since only
      traffic on a `URLSessionProxy` session reaches it.
- **Desired behavior.** One session value, immutable in the app, overridable per
  test through the dependency system the rest of the codebase already uses, and
  declared where a new client will find it.
- **Scope.**
  - Add `Core/Sources/Clients/NetworkSession.swift` with a dependency key —
    `public enum NetworkSessionKey: DependencyKey` whose `liveValue` keeps the
    existing `#if DEBUG` `URLSessionProxy(configuration: .default)` / `#else`
    `URLSession(configuration: .default)` split, typed as
    `any URLSessionProtocol` — plus a `networkSession` accessor on
    `DependencyValues`. `URLSessionProtocol` is `Sendable`, so `liveValue` is a
    plain `static let` with no `nonisolated(unsafe)`. Do **not** implement
    `testValue`: the library default reports an issue when a test reaches the
    session without overriding it, which is the behavior we want. Document on
    the key that every client in `Core` should pass
    `urlSession: networkSession` so DEBUG builds capture all traffic in one
    console.
  - Delete the `indigoSession` global. In the `refresh` closure add
    `@Dependency(\.networkSession) var networkSession` beside the existing
    `@Dependency(\.httpRequestClient)` and pass `urlSession: networkSession`.
    Drop `import Pulse` from `JWTAuthClient+Live.swift` once nothing in the file
    needs it.
  - Rework `JWTAuthClientLiveTests.refresh(tokens:statusCode:body:)`: delete the
    read/assign/`defer`-restore of the global and instead set
    `$0.networkSession = URLSession(configuration: configuration)` in the
    existing `withDependencies` block next to `$0.httpRequestClient`. Keep the
    `.serialized` trait — `RefreshStubProtocol.stub` is still shared mutable
    state.
- **Acceptance.** `rg 'nonisolated\(unsafe\)' Core/Sources` returns nothing; the
  session is declared exactly once, in `NetworkSession.swift`; the refresh call
  passes `urlSession: networkSession`; both refresh tests pass with the
  transport stubbed only through `withDependencies`.
- **Validation.** `mise exec -- tuist generate --no-open`, then
  `mise exec -- tuist build Indigo --configuration Debug` and
  `mise exec -- tuist build "Indigo Release" --configuration Release` to prove
  both `#if` branches still compile. `mise exec -- tuist test AllTests` stays
  green, and `mise exec -- tuist inspect implicit-imports` reports nothing new.

### 2. Correct the authentication section of `docs/api-clients.md`

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
      snippet omits the `urlSession:` argument the shipped file passes.
      `AGENTS.md` has a smaller version of the same problem: its
      "Networking / auth" bullet names the refresh endpoint `/auth/refresh`,
      while the shipped path is `api/v1/auth/refresh-access`. Do this after item
      1 so the snippet can name the final session declaration.
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
    `AuthTokens.Error.missingToken`. Point at `RootFeature`'s `.task` in
    `RootFeature/Sources/RootView.swift` as the shipped launch call site.
  - Note that `.expired` still holds a usable refresh token, so UI should treat
    it as signed in rather than falling back to a login screen; only `.missing`
    and `nil` mean "no session".
  - Bring the refresh snippet back in line with
    `Core/Sources/Clients/JWTAuthClient+Live.swift`: the
    `@Dependency(\.networkSession)` line and the `urlSession: networkSession`
    argument, and a pointer to `Core/Sources/Clients/NetworkSession.swift` as
    the session every client shares.
  - Fix the refresh endpoint path in the `AGENTS.md` "Networking / auth" bullet
    to `api/v1/auth/refresh-access`.
- **Acceptance.** No sentence in the guide claims a 401 retry or an automatic
  post-failure refresh; the session-lifecycle subsection exists and names
  `@Shared(.authSession)`, `authTokensClient`, and `loadSession()`; the refresh
  snippet is a character-for-character match with the shipped closure body; no
  file under `docs/` or `AGENTS.md` still names `/auth/refresh`.
- **Validation.** Cross-read each snippet against
  `Core/Sources/Clients/JWTAuthClient+Live.swift`,
  `Core/Sources/Clients/NetworkSession.swift`, and
  `RootFeature/Sources/RootView.swift`. No build required.

### 3. Extend `usesSharing` to the generated test targets

- [ ] **Gap.** `Project.framework(usesSharing:)` in
      `Tuist/ProjectDescriptionHelpers/Project+Templates.swift:43-74` applies
      `-module-alias Sharing=SwiftSharing` to the framework target only. The
      `\(name)Tests` target it generates alongside is declared with no
      `settings:` at all, so `import Sharing` in
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

### 4. Map the version build settings into the app's `Info.plist`

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
