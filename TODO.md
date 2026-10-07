# Template Project TODOs

## Architecture Sync

Ordered by priority; where an item depends on an earlier one it says so. Each is
scoped to one focused pull request. Validate Swift changes with
`mise exec -- tuist generate --no-open` followed by `mise exec -- tuist build`;
do not rely on a simulator run.

### 1. Bump the Tuist pin to 4.208.0

- [ ] **Gap.** `mise.toml` pins `tuist = "4.202.2"`, which is several
      releases behind the current 4.208 line. CI (`.github/workflows/tests.yml`)
      and Xcode Cloud (`ci_scripts/ci_post_clone.sh`) both install whatever
      `mise.toml` names, so the template keeps generating with an old Tuist
      until the pin moves.
- **Desired behavior.** Local, GitHub Actions, and Xcode Cloud runs all use
  Tuist 4.208.0 and generate the same workspace as before.
- **Scope.** Change only the `tuist` version in `mise.toml`. No manifest
  changes are expected. If generation newly fails or warns, fix it in the
  same PR only when the fix is a mechanical manifest adjustment the new
  Tuist asks for. Otherwise drop the bump and record the blocker here. Keep
  the `xctest-dynamic-overlay` hold in `Package.swift` as it is; it is a
  separate decision.
- **Dependencies.** None.
- **Acceptance.** `mise.toml` pins 4.208.0; `mise exec -- tuist version`
  reports it; generate and build succeed with no new warnings attributable
  to the bump.
- **Validation.** `mise install`, `mise exec -- tuist version`,
  `mise exec -- tuist install`, `mise exec -- tuist generate --no-open`,
  `mise exec -- tuist build`.

### 2. Ship an app privacy manifest

- [ ] **Gap.** The app bundle has no `PrivacyInfo.xcprivacy`. App Store
      Connect rejects uploads whose first-party code uses a required-reason
      API without declaring it, and the template already does:
      `RootFeature` persists `lastSignedInUserId` through
      `@Shared(.appStorage(...))`, which reads and writes `UserDefaults`.
      Every clone inherits the omission and finds out at upload time.
- **Desired behavior.** The app ships a minimal privacy manifest that
  declares exactly what the template's own code uses and states that it does
  no tracking. Cloners extend it as they add APIs.
- **Scope.** Add `App/Resources/PrivacyInfo.xcprivacy` (the `Resources`
  buildable folder bundles it with no manifest change) containing
  `NSPrivacyTracking` = `false` and one `NSPrivacyAccessedAPITypes` entry:
  `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` (data
  accessed only by the app itself). Do not declare categories the template
  does not use. Third-party packages ship their own manifests. Add one line
  to the "Setup" section of `README.md` telling cloners to
  extend the manifest when they adopt further required-reason APIs.
- **Dependencies.** None.
- **Acceptance.** The file is a valid plist with exactly the keys above, and
  the built app bundle contains `PrivacyInfo.xcprivacy`.
- **Validation.** `plutil -lint App/Resources/PrivacyInfo.xcprivacy`, then
  `mise exec -- tuist generate --no-open` and `mise exec -- tuist build`.
  Confirm the file is in the built `.app`, for example with
  `find ~/Library/Developer/Xcode/DerivedData -path '*Indigo.app*/PrivacyInfo.xcprivacy'`.

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
