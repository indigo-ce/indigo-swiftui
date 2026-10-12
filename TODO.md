# Template Project TODOs

## Architecture Sync

Ordered by priority; where an item depends on an earlier one it says so. Each is
scoped to one focused pull request. Validate Swift changes with
`mise exec -- tuist generate --no-open` followed by
`mise exec -- tuist build --platform ios` (the generated project has
multi-platform targets, so `tuist build` requires an explicit `--platform`);
do not rely on a simulator run.

### 1. Add an `AuthFeature` module with sign-in and sign-up forms

- [ ] **Gap.** `SessionClient` (`Core/Sources/Clients/SessionClient.swift`)
      now covers sign-in, sign-up, sign-out, and the account-entry routes,
      but nothing in the template calls `signIn` or `signUp`: there is no
      screen a user can sign in from, so the shipped session lifecycle
      (gated token save → `@Shared(.authSession)` → the `RootFeature`
      observer and cache wipe) is unreachable in the running app, and every
      cloner hand-builds the same form and rediscovers how to turn a failed
      request into a message.
- **Desired behavior.** A self-contained TCA feature owns the sign-in /
  sign-up form. It talks only to `@Dependency(\.sessionClient)` — never to
  `authTokensClient`, the keychain, or `@Shared(.authSession)` directly —
  so a successful sign-in is published by `SessionClient.signIn`'s gated
  save and the feature itself does not decide what happens next (its
  presenter reacts to the session change). Failures show the server's
  message, read through `APIErrorBody.from(error)`, and fall back to a
  generic message for transport failures or unreadable bodies.
- **Scope.**
  - New framework module `AuthFeature/` declared with
    `Project.framework(name: "AuthFeature", …)`, depending on `Core`,
    `Components`, and `.indigoFoundation` (test dependencies: `Core` +
    `.indigoFoundation`). Pass `usesSharing: true` only if a source or test
    file imports `Sharing`.
  - Register the project in `Workspace.swift` (`projects` and the
    `AllTests` scheme's `AuthFeatureTests`). Do not link it into `App` or
    `RootFeature` yet — item 2 does that.
  - `AuthFeature/Sources/AuthView.swift` (one file, like
    `NotesListView.swift`): `AuthFeature` reducer + `AuthView`.
    State: `mode` (`.signIn` / `.signUp`), `name`, `email`, `password`,
    `isLoading`, `errorMessage: String?`, and a sign-up confirmation flag.
    Bindable form fields. `submitButtonTapped` is a no-op while loading or
    when a required field is empty; in `.signIn` it calls
    `sessionClient.signIn(email, password)`, in `.signUp`
    `sessionClient.signUp(name, email, password)`. A successful sign-up
    switches `mode` to `.signIn`, keeps `email`, clears `password`, and
    sets the confirmation flag (signing up does not sign in — the
    `SessionClient` doc comment explains why). Changing mode clears
    `errorMessage` and the confirmation flag. Log failures with `OSLog`
    (`Logger(subsystem: "Indigo", category: "AuthFeature")`), the way
    `SessionClient.swift` and `RootView.swift` do.
  - Put the error-to-message mapping in one internal static function on
    `AuthFeature` (item 3 reuses it).
  - View: segmented mode picker, name field (sign-up only), email and
    password fields with the right `textContentType` (`.password` vs
    `.newPassword`), a submit button that shows a `ProgressView` while
    loading, `InlineNotice.error` for `errorMessage`, and `InlineNotice`
    for the sign-up confirmation ("Account created. Check your email to
    verify it, then sign in."). iOS-only modifiers
    (`keyboardType`, `textInputAutocapitalization`) go behind
    `#if os(iOS)` — the module also builds for macOS. Previews for both
    modes with `$0.sessionClient = .previewValue`.
  - `AGENTS.md` Layout: list `AuthFeature/` with the other feature modules.
  - No root wiring, no forgot-password flow, no verification-email resend,
    no new `Core` API.
- **Dependencies.** None.
- **Acceptance.** `AuthFeature/Tests/AuthFeatureTests.swift` (Swift
  Testing + `TestStore`, like `RootFeatureTests`) proves: sign-in submit
  calls `signIn` with the entered email and password and clears
  `isLoading` on success without touching any other dependency; a
  `HTTPRequestClient.Error.badResponse(UUID(), 401, #"{"error":"Invalid email or password"}"#)`
  failure sets `errorMessage` to `"Invalid email or password"`; a
  non-`badResponse` error sets the generic message; sign-up submit calls
  `signUp` with name, email, password and lands in `.signIn` with the
  password cleared and the confirmation flag set; submitting while loading
  or with an empty required field sends no request; switching mode clears
  the error. The existing suites still pass.
- **Validation.** `mise exec -- tuist generate --no-open`, then
  `mise exec -- tuist build --platform ios` and
  `mise exec -- tuist build --platform macos` (the `#if os(iOS)` guards are
  only proven by the macOS build). Tests run headlessly with
  `mise exec -- tuist test --platform macos`; if that is not possible in
  the build environment, say in the PR that only the builds were verified
  and CI's iOS test job is the proof.

### 2. Present `AuthFeature` from `RootFeature` and ship a sign-out control

- [ ] **Gap.** Once item 1 lands, the sign-in form still has no entry point,
      and `SessionClient.signOut()` — which the docs insist must replace a
      bare `authTokensClient.destroy()` — has no shipped call site either.
      A cloner gets the full session lifecycle in `Core` with nothing in the
      app that starts or ends a session.
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
    `sessionClient.signOut()` and logs (does not surface) a thrown error.
    In `.sessionChanged(.valid)`, set `auth = nil` **before** the
    same-`sub` early return, so a sign-in is dismissed even when it does
    not switch accounts. `RootView` attaches `.sheet(item:)` (wrapping
    `AuthView` in a `NavigationStack` with a Cancel button that dismisses)
    and `.confirmationDialog` to the content it already renders.
  - `RootFeature/Project.swift`: depend on `AuthFeature`.
  - `docs/api-clients.md` Session Lifecycle: name `AuthFeature` and the
    `RootFeature` account flow as the shipped `signIn` / `signOut` call
    sites.
- **Dependencies.** Item 1.
- **Acceptance.** New `RootFeatureTests` cases (reusing `makeStore` and
  `tokens(sub:)`) prove: the account button with no session presents
  `auth`; with a `.valid` session it presents the confirmation dialog and
  not `auth`; confirming calls `sessionClient.signOut` exactly once;
  `.sessionChanged(.valid(tokens(sub:)))` clears a presented `auth` both for
  a new account and for the same `sub`. The existing cache-wipe tests still
  pass unchanged.
- **Validation.** `mise exec -- tuist generate --no-open`, then
  `mise exec -- tuist build --platform ios` and
  `mise exec -- tuist build --platform macos`. Tests run headlessly with
  `mise exec -- tuist test --platform macos`; otherwise state in the PR
  that CI's iOS test job is the proof.

### 3. Add a forgot-password sheet to `AuthFeature`

- [ ] **Gap.** `SessionClient.requestPasswordReset(email)` ships, but the
      sign-in form from item 1 offers no way to reach it, so a user who
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
  only) that seeds the email, `.ifLet`, and the `.sheet(item:)` in
  `AuthView`. Reuse the error-mapping function from item 1. Same
  `#if os(iOS)` rule for iOS-only modifiers.
- **Dependencies.** Item 1. Independent of item 2.
- **Acceptance.** Tests prove: tapping "Forgot password?" presents the
  child with the sign-in email; submit calls `requestPasswordReset` with
  that email and sets `emailSent`; a `badResponse` `{"error": …}` failure
  sets `errorMessage` to the server text; submit with an empty email or
  while loading sends nothing; Done/Cancel invoke `dismiss`. Item 1's tests
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
