# Template Project TODOs

## Architecture Sync

Ordered by priority; where an item depends on an earlier one it says so. Each is
scoped to one focused pull request. Validate Swift changes with
`mise exec -- tuist generate --no-open` followed by
`mise exec -- tuist build --platform ios` (the generated project has
multi-platform targets, so `tuist build` requires an explicit `--platform`);
do not rely on a simulator run.

### 1. Give `SessionClient` verification-email and password-reset operations

- [ ] **Gap.** The backend serves two more unauthenticated account-entry
      routes that `SessionClient` (`Core/Sources/Clients/SessionClient.swift`)
      does not cover:
      `POST /api/v1/auth/send-verification-email` (`{email, callbackURL?}` →
      `{status}`) and `POST /api/v1/auth/reset-password`
      (`{newPassword, token}` → `{status}`). When the backend requires email
      verification, sign-in answers 401 `Email not verified`, and a cloner
      has no shipped way to resend the link; likewise the reset token that
      `requestPasswordReset` emails out has no client operation to redeem it.
      Each cloner would hand-build these requests and has to rediscover that
      they must not touch the stored session.
- **Desired behavior.** `SessionClient` covers every unauthenticated auth
  route the backend serves, and the two new ones follow the same contract
  as `signUp` and `requestPasswordReset`: plain `apiClient.send` (not
  `sendAuthenticated`) on `networkSession` with the `.api` coders, no read
  or write of stored credentials or `@Shared(.authSession)`, and request
  errors rethrown untouched so callers read them with
  `APIErrorBody.from(error)`. Resetting a password does not sign in.
- **Scope.** In `SessionClient.swift`: add
  `sendVerificationEmail: @Sendable (_ email: String) async throws -> Void`
  and
  `resetPassword: @Sendable (_ token: String, _ newPassword: String) async throws -> Void`;
  implement both in `liveValue` with file-private request models
  (`{email}` and `{newPassword, token}`; no `callbackURL`, so the backend
  default applies) and empty file-private `Decodable` response structs, the
  way `ForgotPasswordResponse` is; add no-op closures to `previewValue`;
  extend the type's doc comment. In `Core/Tests/SessionClientTests.swift`,
  reuse the `unauthenticated(_:seedTokens:into:operation:)` helper. In
  `docs/api-clients.md`, extend the sign-up/password-reset bullet in the
  authentication section to name both operations, their routes, and that
  `resetPassword` does not create a session. No UI, no deep-link handling,
  no other file.
- **Dependencies.** None.
- **Acceptance.** Tests prove: each operation sends `POST` to its path with
  the expected JSON body (`sendVerificationEmail` sends only `email`;
  `resetPassword` sends exactly `newPassword` and `token`); a 200 stub with
  the backend's `{"status":true}` body succeeds; with a seeded session,
  neither operation records any keychain save, load, or delete and the
  published session is unchanged; a 400 stub on `resetPassword` throws an
  error that `APIErrorBody.from(error)` decodes. The existing suite still
  passes.
- **Validation.** `mise exec -- tuist generate --no-open`, then
  `mise exec -- tuist build --platform ios`. The tests run headlessly with
  `mise exec -- tuist test --platform macos` (no simulator); if that is not
  possible in the build environment, say in the PR that only the build was
  verified and CI's iOS test job is the proof.

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
