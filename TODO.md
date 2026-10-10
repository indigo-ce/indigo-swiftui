# Template Project TODOs

## Architecture Sync

Ordered by priority; where an item depends on an earlier one it says so. Each is
scoped to one focused pull request. Validate Swift changes with
`mise exec -- tuist generate --no-open` followed by `mise exec -- tuist build`;
do not rely on a simulator run.

### 1. Adopt Xcode's recommended build settings in the App xcconfigs

- [x] **Gap.** The framework projects get `ENABLE_MODULE_VERIFIER`,
      `MODULE_VERIFIER_SUPPORTED_LANGUAGE_STANDARDS` and
      `STRING_CATALOG_GENERATE_SYMBOLS` from
      `Tuist/ProjectDescriptionHelpers/Project+Templates.swift`. The `App`
      project takes its settings only from `Configs/Debug.xcconfig` and
      `Configs/Release.xcconfig`, and neither file sets those keys or
      `REGISTER_APP_GROUPS`. Xcode 26 therefore raises "Update to recommended
      settings" on the `App` project. Accepting the prompt in Xcode does not
      stick, because the next `tuist generate` throws the change away, so
      every clone keeps seeing the warning.
- **Desired behavior.** The `App` project carries the same recommended
  settings as the framework template, persisted in the xcconfigs so they
  survive regeneration.
- **Scope.** In the `// Xcode` section of both xcconfigs, add
  `ENABLE_MODULE_VERIFIER=YES`,
  `MODULE_VERIFIER_SUPPORTED_LANGUAGE_STANDARDS="gnu11 gnu++14"`,
  `REGISTER_APP_GROUPS=YES` and `STRING_CATALOG_GENERATE_SYMBOLS=YES`, in
  the file's existing `KEY=VALUE` style. Do not change `App/Project.swift`,
  the framework template, or any other key.
- **Dependencies.** None.
- **Acceptance.** Both xcconfigs set all four keys to the values above, and
  the two files still differ only in their existing Debug/Release-specific
  lines.
- **Validation.** `grep -cE '^(ENABLE_MODULE_VERIFIER|MODULE_VERIFIER_SUPPORTED_LANGUAGE_STANDARDS|REGISTER_APP_GROUPS|STRING_CATALOG_GENERATE_SYMBOLS)=' Configs/Debug.xcconfig Configs/Release.xcconfig`
  reports 4 for each file, then `mise exec -- tuist generate --no-open` and
  `mise exec -- tuist build`.

### 2. Put the sign-out gate back in the documented refresh wiring

- [ ] **Gap.** The "Setting Up JWT Authentication" section of
      `docs/api-clients.md` says to copy its `JWTAuthClient` sample, but the
      sample predates `AuthSessionGate`. The shipped `refresh` closure in
      `Core/Sources/Clients/JWTAuthClient+Live.swift` resolves
      `@Dependency(\.authSessionGate)` and calls
      `await gate.stagePublish(newRefresh:sourceRefresh:)` before returning
      the new tokens; the sample does neither and returns `AuthTokens`
      inline. The "Session Lifecycle" bullet further down says that the
      `refresh` closure records the publish it is about to hand back, which
      is the call the sample leaves out. A cloner who copies the sample gets
      a refresh that the gated `authTokensClient` cannot veto, so a refresh
      that lands mid-sign-out can sign the user back in with a refresh token
      that sign-out never revoked. Separately, the "Making Authenticated
      Requests" example calls `Path("api", "v1", "user", "profile")`, but the
      authenticated profile route the paired backend serves is
      `GET /api/v1/account/profile`.
- **Desired behavior.** The documented refresh wiring matches the shipped
  file line for line in its logic, and the authenticated-request example
  names a route the backend actually serves.
- **Scope.** Only `docs/api-clients.md`. In the JWT setup sample, add
  `@Dependency(\.authSessionGate) var gate`, bind the result to `newTokens`,
  call `await gate.stagePublish(newRefresh: newTokens.refresh, sourceRefresh: tokens.refresh)`
  and return `newTokens`, with a one-line comment pointing at
  `AuthSessionGate`, exactly as the shipped closure does. Add one sentence
  after the sample saying that the `stagePublish` call is required for as
  long as `.gated` is installed. Change the authenticated-request path to
  `Path("api", "v1", "account", "profile")`. Leave the generic `stacks`,
  `items`, and `games` examples alone. Do not change any Swift file.
- **Dependencies.** None.
- **Acceptance.** The sample's `refresh` closure resolves the same three
  dependencies as `JWTAuthClient+Live.swift`
  (`httpRequestClient`, `networkSession`, `authSessionGate`) and calls
  `stagePublish` before returning. `docs/api-clients.md` has no
  `"user", "profile"` path left. No other file changes.
- **Validation.** `grep -c stagePublish docs/api-clients.md` reports at least
  1, and `grep -n '"user", "profile"' docs/api-clients.md` returns nothing.
  Compare the sample's `refresh` closure against
  `Core/Sources/Clients/JWTAuthClient+Live.swift` by eye. No build is needed
  for a docs-only change.

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
