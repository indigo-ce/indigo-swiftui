# Template Project TODOs

## Architecture Sync

Ordered by priority; where an item depends on an earlier one it says so. Each is
scoped to one focused pull request. Validate Swift changes with
`mise exec -- tuist generate --no-open` followed by
`mise exec -- tuist build --platform ios` (the generated project has
multi-platform targets, so `tuist build` requires an explicit `--platform`);
do not rely on a simulator run.

- [ ] Ship an `AccountClient` that fetches the signed-in profile

  **Gap.** The template advertises JWT auth with automatic token refresh, but
  no shipped code calls `sendAuthenticated`. Every request in
  `Core/Sources/Clients/SessionClient.swift` deliberately uses `send`, and
  `NotesClient` is local-only. So the authenticated path (refresh when
  expired, attach the bearer, send once) is never exercised or tested. The
  only examples live in `docs/api-clients.md`, and one of them already points
  at `GET /api/v1/account/profile`. The backend serves that route behind its
  JWT middleware. It answers 200 with
  `{id, email, name, image, emailVerified, createdAt, updatedAt}`, where
  `image` is nullable and both dates are ISO-8601 with fractional seconds. It
  answers 401 `{error, code: "UNAUTHORIZED"}` for a bad token or a deleted
  user.

  **Scope.** Add `Core/Sources/Clients/AccountClient.swift` with a
  `@DependencyClient` `AccountClient` exposing
  `fetchProfile: () async throws -> AccountProfile`. Register it as
  `DependencyValues.accountClient` with `liveValue`, `previewValue` (a fixed
  sample profile), and `testValue` (unimplemented), following
  `SessionClient`'s shape. `AccountProfile` is a public
  `Decodable, Equatable, Sendable` struct in the same file that mirrors the
  seven response fields (`image: String?`, dates as `Date`). The live closure
  resolves `apiClient` and `networkSession` inside the closure and calls
  `apiClient.sendAuthenticated(decoder: .api, urlSession: networkSession)`
  with `Path("api", "v1", "account", "profile")`. Errors propagate untouched,
  with no retry and no session mutation on 401, matching the documented
  `sendAuthenticated` contract. No UI or feature wiring and no cache table.

  **Acceptance.**
  - The live closure is the first shipped `sendAuthenticated` call site.
  - A doc comment explains why it uses `sendAuthenticated` where every
    `SessionClient` route uses `send`.
  - `docs/api-clients.md` "Making Authenticated Requests" points at
    `AccountClient.swift` as the shipped example.
  - The README's file or feature list mentions it if it enumerates clients.

  **Validation.**
  - Add `Core/Tests/AccountClientTests.swift`, driving
    `AccountClient.liveValue` through a host-scoped `URLProtocol` stub in the
    style of `SessionClientTests`, under `@Suite(.serialized)`.
  - Seed a session the library treats as unexpired so no refresh fires. One
    way is an access token that is a JWT with a future `exp`; another is
    overriding `$0.apiClient.refresh` to fail the test if called.
  - Assert the request is `GET /api/v1/account/profile` carrying
    `Authorization: Bearer <seeded access token>`.
  - Assert that a full backend body (fractional-second dates, `image: null`)
    decodes into the expected `AccountProfile`.
  - Assert that a 401 body rethrows as `HTTPRequestClient.Error.badResponse`
    with status 401 and leaves `@Shared(.authSession)` unchanged.
  - Run `mise exec -- tuist generate --no-open` and
    `mise exec -- tuist build --platform ios`.

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
- [x] Move the cache database into Application Support and split it by configuration
- [x] Adopt Xcode's recommended build settings in the App xcconfigs
- [x] Put the sign-out gate in the documented refresh wiring
- [x] Give `SessionClient` sign-up and password-reset request operations
- [x] Drop the `xctest-dynamic-overlay` pin from `Package.swift`
- [x] Give `SessionClient` verification-email and password-reset operations
- [x] Add an `AuthFeature` module with sign-in and sign-up forms
- [x] Present `AuthFeature` from `RootFeature` and ship a sign-out control
- [x] Add a forgot-password sheet to `AuthFeature`
- [x] Cancel the in-flight notes fetch when the user cache is wiped
- [x] Offer a verification-email resend when sign-in is refused as unverified
