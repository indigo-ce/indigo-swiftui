# Template Project TODOs

## Architecture Sync

Ordered by priority; where an item depends on an earlier one it says so. Each is
scoped to one focused pull request. Validate Swift changes with
`mise exec -- tuist generate --no-open` followed by
`mise exec -- tuist build --platform ios` (the generated project has
multi-platform targets, so `tuist build` requires an explicit `--platform`);
do not rely on a simulator run.

### 1. Offer a verification-email resend when sign-in is refused as unverified

- [ ] **Gap.** When the backend requires email verification, `POST
      /api/v1/auth/sign-in` answers 401 with `{"error":"Email not verified"}`.
      `AuthFeature` shows that text as a plain error, and nothing in the app
      calls `SessionClient.sendVerificationEmail`, although its doc comment
      names it as the recovery path. A user whose link expired or never
      arrived has no way to get a new one in the app.
- **Desired behavior.** A sign-in refused as unverified keeps the server's
  message and also offers "Resend verification email" for the refused
  address. A successful resend replaces the button with a "check your email"
  notice. A failed resend surfaces the server's message the way other
  failures do. Other sign-in failures behave as they do today.
- **Scope.** `AuthFeature/Sources/AuthView.swift`, its tests, and one
  sentence in `docs/api-clients.md`.
  - Add `static func isEmailNotVerified(_ error: any Error) -> Bool`. It
    returns `true` only for `HTTPRequestClient.Error.badResponse` with
    status 401 whose `APIErrorBody.from(error)?.error` is
    `"Email not verified"`. The backend sends no `code` for this case, so
    the message is the only discriminator. Say so in a comment.
  - State: `unverifiedEmail: String?` (the address sign-in refused) and
    `verificationEmailSent: Bool`. Actions: `emailNotVerified(email:message:)`,
    `resendVerificationEmailButtonTapped`, `verificationEmailSent`.
  - The sign-in catch sends `.emailNotVerified` when `isEmailNotVerified`
    matches, otherwise `.failed` as today. `.emailNotVerified` clears
    `isLoading`, sets `errorMessage` to the server message, and records
    `unverifiedEmail`.
  - The resend is guarded by `!isLoading` and a non-nil `unverifiedEmail`.
    It sets `isLoading`, clears `errorMessage`, and calls
    `sessionClient.sendVerificationEmail(unverifiedEmail)`. Success sets
    `verificationEmailSent`; failure goes through `.failed` with
    `AuthFeature.errorMessage(from:)` and keeps `unverifiedEmail`, so the
    user can retry.
  - Clear `unverifiedEmail` and `verificationEmailSent` on a mode switch,
    on an email edit (`.binding(\.email)`), and when a new sign-in is
    submitted, so the button never targets an address the form no longer
    shows.
  - View: in sign-in mode, when `unverifiedEmail` is set and
    `verificationEmailSent` is false, show a "Resend verification email"
    button disabled while loading. When `verificationEmailSent` is true, show
    `InlineNotice("Verification email sent. Check your inbox, then sign in.")`.
  - `docs/api-clients.md`: where the account-entry bullet calls
    `.sendVerificationEmail(email)` "the operation to offer when `signIn`
    answers 401 `Email not verified`", name `AuthFeature`'s resend button
    as the shipped call site, the way the same section names `RootFeature`
    for `signOut`.
- **Dependencies.** None.
- **Acceptance.** New `AuthFeatureTests` cases:
  - A 401 `Email not verified` sign-in sets `errorMessage` and
    `unverifiedEmail`.
  - A 401 `Invalid email or password` still produces `.failed` with
    `unverifiedEmail == nil`.
  - The resend calls `sendVerificationEmail` exactly once with the refused
    address and sets `verificationEmailSent`.
  - A resend `badResponse` surfaces the server message and keeps
    `unverifiedEmail`.
  - Editing the email or switching modes clears both fields.
  - The resend is a no-op while loading.

  The existing `AuthFeatureTests`, including
  `signInBadResponseSurfacesServerMessage`, pass unchanged.
- **Validation.** `mise exec -- tuist generate --no-open`, then
  `mise exec -- tuist build --platform ios` and
  `mise exec -- tuist build --platform macos`; tests via
  `mise exec -- tuist test --platform macos` where possible, otherwise CI.

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
