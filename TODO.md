# Template Project TODOs

## Architecture Sync

Ordered by priority; where an item depends on an earlier one it says so. Each is
scoped to one focused pull request. Validate Swift changes with
`mise exec -- tuist generate --no-open` followed by `mise exec -- tuist build`;
do not rely on a simulator run.

### 1. Ship a sign-out seam that revokes the refresh token before ending the session

- [x] **Gap.** The template can restore, refresh, and react to a session ending
      (`RootFeature/Sources/RootView.swift:126-148` wipes the user cache when
      `@Shared(.authSession)` goes `nil`), but nothing in the codebase ends one on
      purpose: `rg -n 'destroy\(|revoke|signOut' Core/ RootFeature/` finds no call
      site, and `docs/api-clients.md:83,110` only shows `signOut` as a
      hypothetical client field. A clone that adds a sign-out button has to work
      out for itself that calling `authTokensClient.destroy()` alone leaves the
      refresh token alive on the server — anyone who copied it off the device can
      keep minting access tokens until it expires. The backend the
      template targets exposes `POST /api/v1/auth/revoke-access` with body
      `{"refreshToken": "…"}`. It returns `{"success": true}` with status 200,
      including for an unknown or already-revoked token, so a retry is always
      safe.
- **Desired behavior.** Core ships one sign-out operation with a fixed order:
  revoke the refresh token on the server **on a best-effort basis**, then destroy
  local credentials. A revoke failure (offline, 5xx, timeout) is logged and must
  never keep the user signed in. A local `destroy()` failure is the only thing
  that throws, because only a successful destroy actually ends the session on
  this device. The existing session observer in `RootFeature` then wipes the
  user cache with no extra wiring.
- **Scope.** The sign-out client, the `AuthSessionGate` that keeps its destroy
  serialized against token refresh, their test files, a
  `prepareDependencies` line in `App`, and one doc update.
  - New `Core/Sources/Clients/SessionClient.swift`: a `@DependencyClient public
    struct SessionClient: Sendable` with a single
    `public var signOut: @Sendable () async throws -> Void`, a `DependencyKey`
    conformance, and a `DependencyValues.sessionClient` get/set accessor, laid
    out like `Core/Sources/Clients/NotesClient.swift`. `testValue` is `Self()`,
    so an un-overridden test call reports an issue. `previewValue` is a no-op.
  - `liveValue.signOut` resolves `\.apiClient`, `\.authTokensClient`, and
    `\.networkSession` inside the closure (the same way
    `JWTAuthClient+Live.swift:23-24` does), so `withDependencies` overrides
    apply at call time. It reads `@Shared(.authSession)`. When
    `session?.tokens?.refresh` is present, it sends
    `apiClient.send(decoder: .api, urlSession: networkSession)` with
    `Path("api", "v1", "auth", "revoke-access")` and
    `post(RevokeRequest(refreshToken: refresh), encoder: .api)`, decoding a
    private `struct RevokeResponse: Decodable { let success: Bool }`.
    - Use `send`, not `sendAuthenticated`. The route authenticates with the
      refresh token in the body, and `sendAuthenticated` would first try to
      refresh an expired access token. That rotates the very token about to be
      revoked and fails outright when offline.
    - Wrap the request in `do/catch` and log any error with
      `Logger(subsystem: "Indigo", category: "SessionClient")`, as
      `RootView.swift:9` does. Then call `try await authTokensClient.destroy()`
      unconditionally, including when there was no session.
    - Keep `RevokeRequest` and `RevokeResponse` private to the file, as the
      refresh models are in `JWTAuthClient+Live.swift:78-85`.
  - `docs/api-clients.md`, section *Session Lifecycle*:
    - Add a bullet saying sign-out goes through
      `@Dependency(\.sessionClient).signOut()`, never a bare
      `authTokensClient.destroy()`, and why: server revocation comes first and
      is best effort, and local destroy must succeed.
    - Replace the placeholder `signOut` field in the two client-organization
      snippets (`:83`, `:110`) with a field that does not suggest a second
      sign-out path, e.g. `getProfile`.
  - Do not add a sign-in or sign-out screen, a sign-in endpoint, or any
    `RootFeature` change. The existing `.sessionChanged` path already handles
    the resulting `nil` session.
- **Dependencies.** None. `Core` already declares `usesSharing: true`
  (`Core/Project.swift:8`), so `@Shared(.authSession)` compiles in both the
  target and its tests.
- **Acceptance.**
  - `sessionClient` is a public dependency in `Core`.
  - With a stored session, `signOut()` issues exactly one `POST` to
    `/api/v1/auth/revoke-access` whose JSON body carries the stored refresh
    token, then leaves `@Shared(.authSession)` `nil` and the keychain entries
    deleted.
  - A 500 or a transport error from the revoke still ends with the session
    destroyed and `signOut()` not throwing.
  - With no stored session, no request is sent and `destroy()` still runs.
  - When `keychainClient.delete` throws, `signOut()` rethrows.
  - A token refresh that completes while `signOut()` is in flight cannot
    republish credentials: `IndigoApp` installs
    `$0.authTokensClient = .gated`, whose writes serialize through
    `AuthSessionGate`; a staged refresh publish is dropped once sign-out has
    begun or its source refresh token is no longer the stored one.
- **Validation.** Run `mise exec -- tuist generate --no-open`, then
  `mise exec -- tuist build`, then `mise exec -- tuist test AllTests`.
  - Add a `@Suite(.serialized)` `Core/Tests/SessionClientTests.swift`. Give it
    its own private `URLProtocol` stub scoped to `JWTAuthClient.host`, modeled
    on `Core/Tests/JWTAuthClientLiveTests.swift:14-49`. The existing stub is
    `private`. The new one must also record each request's path and body (read
    `httpBodyStream` when `httpBody` is `nil`).
  - Drive the real `SessionClient.liveValue.signOut` inside
    `withDependencies`:
    - `$0.httpRequestClient = .liveValue`
    - `$0.jwtAuthClient = .liveValue`, which supplies `baseURL`
    - `$0.authTokensClient = .liveValue`
    - `$0.networkSession` set to an ephemeral session with the stub installed
    - `$0.keychainClient` stubbed to record deletes, as
      `RootFeature/Tests/RootFeatureTests.swift:27-29` does
  - Seed the session with `authTokensClient.save(AuthTokens(access: "a",
    refresh: "r"))` inside the same block, not by assigning `@Shared`.

### 2. Map the version build settings into the app's `Info.plist`

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
- [x] Extend `usesSharing` to the generated test targets
- [x] Wipe the user-scoped cache when the auth session changes
