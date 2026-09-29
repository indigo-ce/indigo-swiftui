# Template Project TODOs

## Architecture Sync

Ordered by priority; where an item depends on an earlier one it says so. Each is
scoped to one focused pull request. Validate Swift changes with
`mise exec -- tuist generate --no-open` followed by `mise exec -- tuist build`;
do not rely on a simulator run.

### 1. Let the sandboxed macOS app open outgoing network connections

- [x] **Gap.** The app builds for the Mac: `Destinations.destinations` is
      `[.iPad, .iPhone, .mac]`
      (`Tuist/ProjectDescriptionHelpers/Project+Templates.swift:107-111`), and
      `App/Project.swift:35` signs the `macosx` SDK with `mac.entitlements`.
      That file enables `com.apple.security.app-sandbox` and nothing else. A
      sandboxed macOS app without `com.apple.security.network.client` cannot
      open outgoing connections, so on the Mac every request the template
      ships fails at the transport layer: the launch-time
      `refreshExpiredTokens()` in `RootFeature/Sources/RootView.swift:86`, the
      best-effort revoke in `SessionClient.signOut`, and any `apiClient.send`
      a clone adds. Because the refresh treats transport errors as transient,
      the failure is silent: the Mac build never refreshes a session and never
      reports why.
- **Desired behavior.** The macOS build can reach the API the template is wired
  to, with the sandbox still on.
- **Scope.** Add `<key>com.apple.security.network.client</key>` followed by
  `<true />` to the top-level dict in `App/mac.entitlements`, indented like the
  existing key. Do not remove the sandbox. Do not add app groups, associated
  domains, file-access entitlements, or any other capability, and do not touch
  `App/ios.entitlements`, since iOS needs no entitlement for outgoing traffic.
- **Dependencies.** None. Land it before item 2 so the sign-in seam works on
  every destination the template builds.
- **Acceptance.** `App/mac.entitlements` holds exactly two keys, both `true`:
  `com.apple.security.app-sandbox` and `com.apple.security.network.client`.
- **Validation.**
  - `plutil -lint App/mac.entitlements`
  - `plutil -extract com.apple.security.network.client raw App/mac.entitlements`
    prints `true`
  - `mise exec -- tuist generate --no-open`, then `mise exec -- tuist build`.
    If the build produces a signed macOS `Indigo.app`, run
    `codesign -d --entitlements - --xml` on it and confirm the key is listed.

### 2. Give `SessionClient` a sign-in operation that stores the issued tokens

- [ ] **Gap.** `Core` can restore, refresh, and end a session, but nothing
      starts one. `SessionClient` (`Core/Sources/Clients/SessionClient.swift:26-29`)
      has only `signOut`, and no call site in `Core/`, `RootFeature/`, or `App/`
      exchanges credentials for tokens or calls `authTokensClient.save`.
      `AuthSessionGate` already expects this writer: an unstaged save "is a
      fresh sign-in: it writes through and re-arms publication"
      (`Core/Sources/Clients/AuthSessionGate.swift:32-33`, `:91-94`). The docs
      point clones the wrong way:
      - The *Unauthenticated Requests* sign-in snippet
        (`docs/api-clients.md:420-424`) omits `method(.post)`, so it sends a
        `GET` to a `POST`-only route.
      - The three `signIn` fields in the client examples (`:82`, `:109`,
        `:607`, with the live body at `:627-631`) return the token response to
        the caller and never persist it. `@Shared(.authSession)` stays `nil`,
        and the observer in `RootView.swift:119-148` never learns that anyone
        signed in.

      The backend the template targets exposes `POST /api/v1/auth/sign-in`. It
      takes `Authorization: Basic base64(email:password)` with no body and no
      content type. It returns 200 with
      `{"user": {…}, "accessToken": "…", "refreshToken": "…", "tokenType": "Bearer"}`,
      or a 4xx with `{"error": "…"}` for bad credentials (`401`,
      `"Invalid email or password"`), an unverified email (`401`,
      `"Email not verified"`), and a missing header (`400`).
- **Desired behavior.** One sign-in path exchanges credentials for tokens and
  persists them through the gated credential client. Persisting publishes
  `.valid` on `@Shared(.authSession)`. From there, the existing observer compares
  the token's `sub` with `lastSignedInUserId` and wipes the user cache on an
  account switch, with no extra wiring. A failed exchange stores nothing and
  surfaces the server's message through `APIErrorBody`.
- **Scope.** One new client endpoint and its tests, plus doc updates. No
  sign-in screen, no `RootFeature` change, and no public user model.
  - In `SessionClient.swift`, add
    `public var signIn: @Sendable (_ email: String, _ password: String) async throws -> Void`.
    Update the type's doc comment to cover both operations. Make
    `previewValue.signIn` a no-op. `testValue` stays `SessionClient()`.
  - `liveValue.signIn` resolves `\.apiClient`, `\.networkSession`, and
    `\.authTokensClient` inside the closure, as `signOut` and
    `revokeRefreshToken` do. It sends
    `apiClient.send(decoder: .api, urlSession: networkSession)` with
    `Path("api", "v1", "auth", "sign-in")`, `method(.post)`, and
    `basicAuth(username: email, password: password)`. It decodes a private
    `SignInResponse: Decodable { let accessToken: String; let refreshToken: String }`
    and then calls
    `try await authTokensClient.save(AuthTokens(access:refresh:))`.
    - Use `send`, not `sendAuthenticated`: there is no session yet.
    - Let every request error propagate untouched. Do not log-and-swallow as
      the revoke does, and do not save on any failure.
    - Ignore the `user` and `tokenType` fields: identity is read from the
      token's `sub` claim, as `RootFeature` already does.
    - Put `SignInResponse` under a new `// MARK: - Sign-in endpoint models`
      next to the revoke models.
  - Update `docs/api-clients.md`:
    - In *Session Lifecycle*, add a bullet before the sign-out bullet: sign-in
      goes through `@Dependency(\.sessionClient).signIn(email, password)`,
      which persists the tokens via the gated `authTokensClient.save`. Callers
      read a failure with `APIErrorBody.from(error)`.
    - In *Unauthenticated Requests*, replace the basic-auth snippet with a
      one-line pointer to `sessionClient.signIn`.
    - Replace the `signIn` field in both client-organization snippets and in
      the *Complete Example* (field and live body) with non-auth endpoints, so
      the docs show a single sign-in path. Leave no dangling
      `SignInPayload`/`Token` references behind.
- **Dependencies.** Item 1 for the Mac destination. No code dependency.
- **Acceptance.**
  - `signIn("user@example.com", "secret")` issues exactly one `POST` to
    `/api/v1/auth/sign-in`, carrying
    `Authorization: Basic dXNlckBleGFtcGxlLmNvbTpzZWNyZXQ=` and no body.
  - On a 200 response, `@Shared(.authSession)?.tokens` holds the returned
    access and refresh tokens, and both keychain entries were saved.
  - On a 401 with `{"error":"Invalid email or password"}`, `signIn` throws.
    `APIErrorBody.from(error)?.error` reads back that message, no keychain
    save happens, and the session stays `nil`.
  - On a transport error, `signIn` throws and nothing is saved.
  - When `keychainClient.save` throws, `signIn` rethrows.
  - `rg -n 'signIn' docs/api-clients.md` matches only `sessionClient.signIn`
    references.
- **Validation.** Run `mise exec -- tuist generate --no-open`, then
  `mise exec -- tuist build`, then `mise exec -- tuist test AllTests`.
  - Extend `Core/Tests/SessionClientTests.swift` rather than adding a suite. The
    file's private `RevokeStubProtocol` already records path and body. Also
    record `httpMethod` and the `Authorization` header, and rename the stub
    (e.g. `AuthStubProtocol`) now that it serves both routes.
  - Add a `signIn(...)` helper mirroring `signOut(...)`
    (`SessionClientTests.swift:102-131`), with the same `withDependencies`
    block (`.gated`, fresh `AuthSessionGate()`, stubbed `networkSession`). It
    records keychain saves instead of deletes and starts with no seeded
    session.
  - Stub a 200 body carrying all four fields the backend sends, so decoding
    tolerates the ignored `user`/`tokenType` keys.

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
- [x] Extend `usesSharing` to the generated test targets
- [x] Wipe the user-scoped cache when the auth session changes
- [x] Ship a sign-out seam that revokes the refresh token before ending the session
