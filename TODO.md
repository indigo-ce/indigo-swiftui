# Template Project TODOs

## Architecture Sync

Ordered by priority; where an item depends on an earlier one it says so. Each is
scoped to one focused pull request. Validate Swift changes with
`mise exec -- tuist generate --no-open` followed by
`mise exec -- tuist build --platform ios` (the generated project has
multi-platform targets, so `tuist build` requires an explicit `--platform`);
do not rely on a simulator run.

- [ ] **Add an `AccountFeature` module that shows the signed-in profile**
  - *Gap:* `AccountClient.fetchProfile` (`Core/Sources/Clients/AccountClient.swift`)
    ships with tests but no feature calls it, so the template's one
    `sendAuthenticated` example has no consumer. Signed in, the user sees
    nothing about the account: the account button only offers a sign-out
    confirmation.
  - *Scope:* a new `AccountFeature/` framework built with `Project.framework`,
    the way `AuthFeature/Project.swift` is: depends on `Core`, `Components`,
    and `.indigoFoundation`; tests depend on `Core` and `.indigoFoundation`.
    Register it in `Workspace.swift` (`projects` and the `AllTests` scheme)
    and add it to the example-feature list in `AGENTS.md`. Do **not** present
    it from `RootFeature` yet; that is the next item.
  - *Reducer:* `@Reducer public struct AccountFeature` with
    `@Dependency(\.accountClient)`. State holds `profile: AccountProfile?`,
    `isLoading`, `errorMessage: String?`, and a `@Presents`
    `confirmationDialog`. Actions: `task` (fetches the profile; ignored while
    a fetch is running), `profileResponse`, `failed(String)`,
    `retryButtonTapped`, `signOutButtonTapped`, the dialog action, and
    `delegate(.signOutConfirmed)`. `task` keeps any profile already loaded
    while it refetches. A failure keeps that profile and sets `errorMessage`.
    Map failures with a `static func errorMessage(from:)` that matches
    `AuthFeature.errorMessage(from:)`: the server's `APIErrorBody` message,
    otherwise a generic fallback. A 401 shows its message and does **not**
    sign out or touch the session; this matches the documented
    `sendAuthenticated` contract.
  - *Sign-out:* `signOutButtonTapped` presents a confirmation dialog with the
    same title, message, and buttons as `ConfirmationDialogState.signOut` in
    `RootView.swift`. Confirming it sends only `.delegate(.signOutConfirmed)`.
    The feature never calls `sessionClient` itself, so the revoking sign-out
    effect, its in-flight guard, and its failure alert stay in `RootFeature`.
  - *View:* `AccountView` runs `.task { await store.send(.task).finish() }`.
    It shows a `ProgressView` until the first profile arrives, then the name,
    email, verified status, and member-since date
    (`createdAt.formatted(date: .long, time: .omitted)`). On error it shows
    `InlineNotice.error(verbatim:)` and a Retry button, and it ends with a
    destructive "Sign Out" button.
  - *Acceptance:* the profile is fetched once per `task`. A failed fetch
    surfaces the server message and keeps any earlier profile. Retry fetches
    again. Confirming sign-out emits only the delegate action. The feature has
    no `sessionClient` dependency.
  - *Validation:* `AccountFeatureTests` with a `TestStore` overriding
    `accountClient.fetchProfile` should cover success, an `APIErrorBody` 401
    failure, a transport failure falling back to the generic message, retry,
    and the confirm-to-delegate path. Then run
    `mise exec -- tuist generate --no-open` and
    `mise exec -- tuist build --platform ios`.

- [ ] **Present `AccountFeature` from `RootFeature` for signed-in users**
  - *Depends on:* the `AccountFeature` item above.
  - *Gap:* signed in, the notes-list account button opens only the sign-out
    dialog (`RootView.swift`, `.notesList(.delegate(.accountButtonTapped))`).
  - *Scope:* add `AccountFeature` as a dependency of `RootFeature` in
    `RootFeature/Project.swift` (sources and tests), and give root state a
    `@Presents var account: AccountFeature.State?` with `.ifLet`. When
    `isAuthenticated`, the account button presents `account` instead of the
    dialog. The `isSigningOut` guard still makes it present nothing. Show the
    sheet in a `NavigationStack` with a Done button that sends
    `.account(.dismiss)`, like the auth sheet does.
  - *Sign-out handoff:* `.account(.presented(.delegate(.signOutConfirmed)))`
    sets `account = nil` and starts the existing `sessionClient.signOut()`
    effect with the existing `isSigningOut`, `signOutResponse`, and failure
    `alert` handling, unchanged. Remove root's own `confirmationDialog` state
    and action, the `ConfirmationDialog` enum, and the
    `ConfirmationDialogState.signOut` extension, because the dialog now lives
    in `AccountFeature`.
  - *Session changes:* `.sessionChanged(.missing)` and `.sessionChanged(nil)`
    also set `account = nil`, so a session that ends while the sheet is open
    (for example, a refresh rejected by the server) closes the sheet. A
    `.valid` rotation for the same `sub` leaves the sheet open.
  - *Docs:* in `docs/api-clients.md`, where it names `AccountClient` as the
    shipped `sendAuthenticated` call site, name `AccountFeature` as its
    consumer.
  - *Acceptance:* when signed in, the account button presents the account
    sheet; when signed out, it still presents sign-in. Confirming sign-out in
    the sheet dismisses it and calls `signOut` exactly once. A failed
    sign-out still raises root's alert. The account button stays inert while
    sign-out is in flight. An ended session dismisses the sheet.
  - *Validation:* in `RootFeatureTests`, rewrite the four dialog-driven
    sign-out tests (`accountButtonWithSessionPresentsTheSignOutDialog`,
    `confirmingSignOutCallsSignOutOnceAndShowsNoAlert`,
    `failedSignOutPresentsTheAlert`,
    `accountButtonWhileSigningOutPresentsNothing`) to drive
    `.account(.presented(.delegate(.signOutConfirmed)))`. Add tests for the
    sheet closing on `.missing` and staying open on a same-`sub` `.valid`.
    Then run `mise exec -- tuist generate --no-open` and
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
- [x] Ship an `AccountClient` that fetches the signed-in profile
