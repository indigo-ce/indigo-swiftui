# Template Project TODOs

## Architecture Sync

Ordered by priority; where an item depends on an earlier one it says so. Each is
scoped to one focused pull request. Validate Swift changes with
`mise exec -- tuist generate --no-open` followed by
`mise exec -- tuist build --platform ios` (the generated project has
multi-platform targets, so `tuist build` requires an explicit `--platform`);
do not rely on a simulator run.

### 1. Cancel the in-flight notes fetch when the user cache is wiped

- [ ] **Gap.** `NotesListFeature`'s `.onAppear` fetch is not cancellable.
      When a session change starts `RootFeature.wipeUserCache`, a fetch
      that began earlier (the list's first `.task`, or the refetch after a
      save or delete) can still deliver `.notesLoaded` with the previous
      account's rows after `.userCacheWiped` or `.userCacheWipeFailed` has
      reset `notesList`. On success the stale rows show until the next
      fetch; on failure they come back even though `.userCacheWipeFailed`
      exists to hide them.
- **Desired behavior.** A wipe supersedes any notes fetch issued before
  it. Only a fetch started after the reset can populate the list.
- **Scope.**
  - `NotesListFeature/Sources/NotesListView.swift`: add a public
    `enum CancelID: Hashable, Sendable { case fetch }` and mark the
    `.onAppear` effect `.cancellable(id: CancelID.fetch, cancelInFlight:
    true)`, so overlapping refetches also collapse to the latest one.
  - `RootFeature/Sources/RootView.swift`: `wipeUserCache` cancels
    `NotesListFeature.CancelID.fetch` before it starts the delete (for
    example `.merge(.cancel(id:), .run { … })`). `.userCacheWipeFailed`
    also returns `.cancel(id: NotesListFeature.CancelID.fetch)` in place
    of `.none`. Add a short comment on why: a pre-wipe read must not
    repopulate the reset list.
- **Dependencies.** None.
- **Acceptance.** A new `RootFeatureTests` case sets a `notesClient.fetchAll`
  that suspends until the test releases it (for example on an
  `AsyncStream` or a checked continuation the test holds) and then returns
  a previous-account note. Start that fetch with `.notesList(.onAppear)`,
  send `.sessionChanged(nil)`, let the wipe finish, then release the fetch.
  `store.state.notesList.notes` never contains the stale note, and the
  test finishes with no unexpected `.notesLoaded` carrying it. A second
  case covers the same ordering through `.userCacheWipeFailed` (closed
  database, as in `wipeFailureKeepsTheMarkerAndHidesTheRows`). The
  existing `RootFeatureTests` and `NotesListFeatureTests` pass unchanged.
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
