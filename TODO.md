# Template Project TODOs

## Architecture Sync

Ordered by priority; where an item depends on an earlier one it says so. Each is
scoped to one focused pull request. Validate Swift changes with
`mise exec -- tuist generate --no-open` followed by `mise exec -- tuist build`;
do not rely on a simulator run.

### 1. Drop the `xctest-dynamic-overlay` pin from `Package.swift`

- [ ] **Gap.** `Package.swift` declares
      `xctest-dynamic-overlay` directly, held at `"1.11.0"..<"1.13.0"`, to
      keep a forwarded `IssueReporting` product from appearing twice in the
      graph (tuist/tuist#12846). That workaround no longer has anything to
      protect: the resolved releases of the graph's packages depend on
      `swift-issue-reporting` (resolved at 2.1.1 in `Package.resolved`)
      instead, so the root manifest should be the only thing still asking
      for `xctest-dynamic-overlay`.
      The pin is now the only thing that puts a second, legacy copy of
      `IssueReporting` (1.11.0) in `Package.resolved`. The pinned package and
      the `XCTestDynamicOverlay` entry in `productTypes` are dead weight that
      a cloner has to understand before touching dependencies.
- **Desired behavior.** The dependency graph carries one issue-reporting
  package, `swift-issue-reporting`, and `Package.swift` declares no
  package or product type that nothing in the graph uses.
- **Scope.** In `Package.swift`: delete the `xctest-dynamic-overlay`
  `.package(...)` entry and its three-line "Held below 1.13" comment; delete
  `"XCTestDynamicOverlay"` from the `frameworkProductTypes([...])` list.
  Keep `"IssueReporting"`. Keep `"IssueReportingPackageSupport"` only if
  the resolved `swift-issue-reporting` manifest (under `Tuist/.build/checkouts/`
  after `tuist install`) still declares a product with that name;
  otherwise delete it too. Re-resolve so `Package.resolved` drops the
  `xctest-dynamic-overlay` pin. No version bumps of other packages beyond
  what re-resolution forces, and no other file.
- **Dependencies.** None.
- **Acceptance.** `Package.swift` and `Package.resolved` contain no
  `xctest-dynamic-overlay`; `Package.resolved` still pins
  `swift-issue-reporting` at 2.x; `productTypes` lists only products the
  graph vends.
- **Validation.** `mise exec -- tuist install`, then
  `grep -c xctest-dynamic-overlay Package.swift Package.resolved` reports
  0 for both. If `tuist install` still resolves `xctest-dynamic-overlay`, a
  transitive package depends on it: stop and record which one here instead
  of reinstating a pin. Then `mise exec -- tuist generate --no-open` (it
  must not raise the duplicate-product/circular-dependency error) and
  `mise exec -- tuist build`.

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
