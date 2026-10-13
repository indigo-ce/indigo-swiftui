# Template Project TODOs

## Architecture Sync

Ordered by priority; where an item depends on an earlier one it says so. Each is
scoped to one focused pull request. Validate Swift changes with
`mise exec -- tuist generate --no-open` followed by
`mise exec -- tuist build --platform ios` (the generated project has
multi-platform targets, so `tuist build` requires an explicit `--platform`);
do not rely on a simulator run.

### 1. Present `AuthFeature` from `RootFeature` and ship a sign-out control

- [ ] **Gap.** The `AuthFeature` module (`AuthFeature/Sources/AuthView.swift`)
      ships the sign-in / sign-up form, but nothing links or presents it, so
      it has no entry point in the running app. `SessionClient.signOut()` —
      which the docs insist must replace a bare `authTokensClient.destroy()`
      — has no shipped call site either. A cloner gets the full session
      lifecycle in `Core` with nothing in the app that starts or ends a
      session.
- **Desired behavior.** The notes app stays usable without a backend (DEBUG
  builds point at a local dev server a cloner may not be running), so
  authentication is offered, not forced: an account button in the notes
  list opens the sign-in sheet when signed out and a sign-out confirmation
  when signed in. `RootFeature` owns both presentations, because it already
  observes `@Shared(.authSession)`; `NotesListFeature` stays unaware of
  auth and only reports the tap. A successful sign-in dismisses the sheet
  through the existing session observer — `AuthFeature` never dismisses
  itself on success. Sign-out goes through `sessionClient.signOut()`, and
  the existing observer performs the cache wipe with no extra wiring.
- **Scope.**
  - `NotesListFeature/Sources/NotesListView.swift`: add
    `case delegate(Delegate)` with `Delegate.accountButtonTapped`, and a
    toolbar button (`person.crop.circle`, a placement valid on iOS and
    macOS such as `.navigation`) that sends it. The reducer returns
    `.none` for it.
  - `RootFeature/Sources/RootView.swift`: `@Presents var auth:
    AuthFeature.State?` and `@Presents var confirmationDialog:
    ConfirmationDialogState<Action.ConfirmationDialog>?`; on
    `.notesList(.delegate(.accountButtonTapped))` present the dialog when
    `isAuthenticated`, otherwise the auth sheet. Confirming sign-out runs
    `@Dependency(\.sessionClient).signOut()`. `signOut` only throws when
    the local credential destroy fails — the user is then still signed in
    on this device — so a thrown error is logged with the existing
    `logger` **and** surfaced through a `@Presents var alert:
    AlertState<Never>?` ("Couldn't sign out. Please try again."); a
    silently swallowed failure would leave the user believing they had
    signed out. The revoke step's own failures are already swallowed
    inside `signOut` and need no handling here.
    In `.sessionChanged(.valid)`, set `auth = nil` **before** the
    same-`sub` early return, so a sign-in is dismissed even when it does
    not switch accounts. `RootView` attaches `.sheet(item:)` (wrapping
    `AuthView` in a `NavigationStack` with a Cancel button that dismisses),
    `.confirmationDialog`, and `.alert` to the content it already renders.
  - `RootFeature/Project.swift`: depend on `AuthFeature`.
  - `docs/api-clients.md` Session Lifecycle: name `AuthFeature` and the
    `RootFeature` account flow as the shipped `signIn` / `signOut` call
    sites.
- **Dependencies.** None (`AuthFeature` has shipped).
- **Acceptance.** New `RootFeatureTests` cases (reusing `makeStore` and
  `tokens(sub:)`; override `store.dependencies.sessionClient` per test, since
  `makeStore` does not set it) prove: the account button with no session
  presents `auth`; with a `.valid` session it presents the confirmation
  dialog and not `auth`; confirming calls `sessionClient.signOut` exactly
  once and presents no alert on success; a throwing `signOut` presents the
  alert; `.sessionChanged(.valid(tokens(sub:)))` clears a presented `auth`
  both for a new account and for the same `sub`. The existing cache-wipe
  tests still pass unchanged.
- **Validation.** `mise exec -- tuist generate --no-open`, then
  `mise exec -- tuist build --platform ios` and
  `mise exec -- tuist build --platform macos`. Tests run headlessly with
  `mise exec -- tuist test --platform macos`; otherwise state in the PR
  that CI's iOS test job is the proof.

### 2. Add a forgot-password sheet to `AuthFeature`

- [ ] **Gap.** `SessionClient.requestPasswordReset(email)` ships, but the
      shipped sign-in form (`AuthView`) offers no way to reach it, so a user who
      forgot their password is stuck and a cloner builds the flow from
      scratch.
- **Desired behavior.** The sign-in mode offers "Forgot password?", which
  presents a small child feature prefilled with the email already typed.
  Submitting calls `requestPasswordReset`; success replaces the form with a
  "Check your email for a reset link." notice and a Done button; failure
  shows the server's message through the same mapping `AuthFeature` uses.
  The child never touches the session. Redeeming the reset token stays out
  of scope: the emailed link opens the backend's web page, and there is no
  in-app deep-link destination.
- **Scope.** In the `AuthFeature` module only: a
  `ForgotPasswordFeature` reducer + `ForgotPasswordView` in
  `AuthFeature/Sources/ForgotPasswordView.swift` (state: `email`,
  `isLoading`, `errorMessage`, `emailSent`; Cancel/Done dismiss via
  `@Dependency(\.dismiss)`); in `AuthFeature`, `@Presents var
  forgotPassword`, a `forgotPasswordButtonTapped` action (sign-in mode
  only, a no-op while `isLoading`) that seeds the email, `.ifLet`, and the
  `.sheet(item:)` in `AuthView` (the button is disabled while loading,
  like the other controls there). Map failures with the existing
  `AuthFeature.errorMessage(from:)` and log them with the file's
  `Logger(subsystem: "Indigo", category: "AuthFeature")`. Same
  `#if os(iOS)` rule for iOS-only modifiers as `AuthView.swift`.
- **Dependencies.** None. Independent of item 1.
- **Acceptance.** New cases in `AuthFeature/Tests/AuthFeatureTests.swift`
  prove: tapping "Forgot password?" presents the child with the sign-in
  email; submit calls `requestPasswordReset` with that email and sets
  `emailSent`; a `badResponse` `{"error": …}` failure sets `errorMessage`
  to the server text; submit with an empty email or while loading sends
  nothing; Done/Cancel invoke `dismiss`. The existing `AuthFeatureTests`
  still pass.
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
