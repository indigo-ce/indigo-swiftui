# Template Project TODOs

## Architecture Sync

Ordered by priority; where an item depends on an earlier one it says so. Each is
scoped to one focused pull request. Validate Swift changes with
`mise exec -- tuist generate --no-open` followed by `mise exec -- tuist build`;
do not rely on a simulator run.

### 1. Give `SessionClient` sign-up and password-reset request operations

- [ ] **Gap.** `Core/Sources/Clients/SessionClient.swift` covers only
      `signIn` and `signOut`. The paired backend also serves the two other
      unauthenticated account-entry routes an app needs before it holds a
      session: `POST /api/v1/auth/sign-up` (JSON body
      `{"email", "password", "name"}`, answers 200 with `{user, token}`,
      400 with `{"error": …}`) and `POST /api/v1/auth/forgot-password` (JSON
      body `{"email"}`, answers 200 with `{status, message}`). A cloner
      building an auth screen today has to hand-roll both requests outside
      the session seam, with no shared answer to "does sign-up sign me in?".
      It does not: the sign-up `token` is a server-side web session token,
      not the JWT pair `authTokensClient` stores, so the account still has to
      go through `signIn`.
- **Desired behavior.** Both operations live on `SessionClient` next to
  `signIn`, use the shared transport and coders, never touch stored
  credentials, and propagate request errors untouched so callers can read
  the server's message with `APIErrorBody.from(error)`.
- **Scope.** In `SessionClient.swift`, add
  `signUp: @Sendable (_ name: String, _ email: String, _ password: String) async throws -> Void`
  and `requestPasswordReset: @Sendable (_ email: String) async throws -> Void`.
  Each resolves `apiClient` and `networkSession` inside the closure, as
  `signIn` does, and calls `apiClient.send(decoder: .api, urlSession: networkSession)`
  with `Path("api", "v1", "auth", "sign-up")` /
  `Path("api", "v1", "auth", "forgot-password")` and `post(…, encoder: .api)`.
  Request and response models are `private` to the file, beside the
  existing sign-in and revoke models; the response models decode no fields
  the operation does not use (an empty `Decodable` struct is fine), and no
  `callbackURL` or `redirectTo` is sent so the backend defaults apply. Add
  both to `previewValue` as no-ops. Update the type's doc comment and add one
  "Session Lifecycle" bullet in `docs/api-clients.md` stating that `signUp`
  does not create a session and must be followed by `signIn`. In
  `Core/Tests/SessionClientTests.swift`, using the existing stubbed
  `URLSession`, cover: sign-up sends the expected method, path and JSON body
  and leaves `@Shared(.authSession)` unchanged; a 400 sign-up rethrows a
  `badResponse` that `APIErrorBody.from` decodes; password reset sends the
  expected method, path and body. No UI, no reset-password or
  verification-email operation, no other file.
- **Dependencies.** None.
- **Acceptance.** `SessionClient` exposes `signIn`, `signOut`, `signUp` and
  `requestPasswordReset`; neither new operation calls `authTokensClient`;
  the three new tests exist; `docs/api-clients.md` documents the sign-up →
  sign-in sequence.
- **Validation.** `grep -n 'authTokensClient' Core/Sources/Clients/SessionClient.swift`
  shows no new uses inside the new closures, then
  `mise exec -- tuist generate --no-open` and `mise exec -- tuist build`.

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
