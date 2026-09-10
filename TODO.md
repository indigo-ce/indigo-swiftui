# Template Project TODOs

## Architecture Sync

Ordered: earlier items unblock later ones. Each is scoped to one focused pull
request. Validate Swift changes with `mise exec -- tuist generate --no-open`
followed by `mise exec -- tuist build`; do not rely on a simulator run.

### 1. Pin GRDB and swift-structured-queries as explicit root dependencies

- [ ] **Gap.** `Package.swift` declares `sqlite-data` but not the two packages it
      pulls in, so `Package.resolved` sits at GRDB `7.8.0` and
      swift-structured-queries `0.31.1` — chosen by transitive resolution, not by
      us. `packageSettings.productTypes` already names `GRDB` and `GRDBSQLite`
      as framework products, so the workspace links them directly while nothing
      constrains their versions. Any unrelated dependency bump can slide those
      two independently of `sqlite-data 1.6.6`, and the combination is a known
      breakage surface: `sqlite-data`'s CloudKit sources fail to compile against
      older GRDB / structured-queries revisions.
- **Desired behavior.** The three packages move as one unit under an explicit,
  reviewable floor in `Package.swift`.
- **Scope.** Add `.package(url: "https://github.com/groue/GRDB.swift", from: "7.11.1")`
  and `.package(url: "https://github.com/pointfreeco/swift-structured-queries", from: "0.31.3")`
  to `Package.swift`. Re-resolve and commit the updated `Package.resolved`. Do
  not remove or reorder existing dependencies, and do not change
  `swift-tools-version`.
- **Acceptance.** `Package.resolved` shows GRDB ≥ 7.11.1 and
  swift-structured-queries ≥ 0.31.3 with `sqlite-data` still at 1.6.6; both new
  packages appear in `Package.swift`'s dependency list.
- **Validation.** `mise exec -- tuist install`, then
  `mise exec -- tuist generate --no-open` and `mise exec -- tuist build`. Confirm
  `Core` still compiles its `@Table` model and structured-query call sites in
  `Core/Sources/Models/Note.swift` and `Core/Sources/Clients/NotesClient.swift`.

### 2. Declare `DependenciesMacros` in `.indigoFoundation`

- [ ] **Gap.** `Core/Sources/Clients/NotesClient.swift` imports
      `DependenciesMacros`, but `.indigoFoundation` in
      `Tuist/ProjectDescriptionHelpers/Project+Templates.swift` never lists it.
      The import only resolves because `ComposableArchitecture` happens to link
      it transitively. `AGENTS.md` tells contributors to check hygiene with
      `tuist inspect implicit-imports`, which this violates, and the documented
      four-step recipe for adding a package expects every used module to be
      declared.
- **Desired behavior.** Every module a first-party target imports is an explicit
  dependency.
- **Scope.** Add `.external(name: "DependenciesMacros")` to `.indigoFoundation`.
  `"DependenciesMacros"` is already in `Package.swift`'s `frameworkProductTypes`
  list, so no package change is needed. Leave the other unimported entries in
  `.indigoFoundation` alone — the helper is deliberately batteries-included.
- **Acceptance.** `mise exec -- tuist inspect implicit-imports` reports no
  finding for `DependenciesMacros` in `Core`.
- **Validation.** `mise exec -- tuist generate --no-open` then
  `mise exec -- tuist build`.

### 3. Build the token-refresh request with `HTTPRequestBuilder`

- [ ] **Gap.** `Core/Sources/Clients/JWTAuthClient+Live.swift` is the template's
      only networking example, and it hand-assembles a `URLRequest`:
      `URL(string: "\(host)/auth/refresh")!` force-unwrapped, `httpMethod`,
      `Content-Type`, and `httpBody` set by hand. `HTTPRequestBuilder` ships in
      `.indigoFoundation` for exactly this and is imported nowhere, so the
      template demonstrates the opposite of the stack it bundles. The path also
      omits the `api/v1` prefix that `docs/api-clients.md` uses throughout.
- **Desired behavior.** The refresh call is declarative, has no force-unwrap, and
  models the request shape every cloned project will copy.
- **Scope.** Rewrite the `refresh` closure to
  `try await httpClient.send(baseURL: host, decoder: .api) { Path("api", "v1", "auth", "refresh-access"); post(RefreshTokenRequest(refreshToken: tokens.refresh), encoder: .api) }.value`,
  add `import HTTPRequestBuilder`, and drop the manual `URLRequest`
  construction. **Preserve the error mapping exactly**: only
  `HTTPRequestClient.Error.badResponse(_, 401, _)` maps to
  `AuthTokens.Error.refreshRejected`; everything else rethrows untouched. Keep
  the explanatory comment. Do not change `host`, `RefreshTokenRequest`,
  `TokenResponse`, or `JSONCoders`.
- **Acceptance.** No `URL(string:)!` remains in the file; the closure returns
  `AuthTokens` built from the decoded `TokenResponse`; the 401-only wipe contract
  described in `AGENTS.md` is unchanged.
- **Validation.** `mise exec -- tuist generate --no-open` then
  `mise exec -- tuist build`. Add a `Core` test that feeds a
  `.badResponse(_, 401, _)` and a `.badResponse(_, 500, _)` through the mapping
  and asserts `refreshRejected` for the first and pass-through for the second;
  run it with `mise exec -- tuist test AllTests`.

### 4. Add `APIErrorBody` for reading 4xx response bodies

- [ ] **Gap.** `HTTPRequestClient` reports non-2xx responses as
      `.badResponse(_, status, body)` with the body as a raw `String`. The
      template has no way to read it, so every 4xx collapses into an opaque
      failure. `Core/Sources/IndigoError.swift` carries a single
      `case invalidToken` and offers no server-message path. Depends on item 3
      landing first so the new type has a live call site to document.
- **Desired behavior.** A cloned project can recover the server's message and its
  stable error code from a failed request, and localize the codes it recognizes
  while falling back to the server's prose for the rest.
- **Scope.** Add `Core/Sources/Clients/APIErrorBody.swift` with a
  `public struct APIErrorBody: Decodable, Sendable` holding `error: String` and
  `code: String?`, plus a `public static func from(_ error: any Error) -> APIErrorBody?`
  that pattern-matches `HTTPRequestClient.Error.badResponse`, converts the body
  string to `Data`, and decodes. Document the two fields: `error` is
  display-ready and follows `Accept-Language`; `code` is stable and does not.
  Do not change `IndigoError` and do not wire this into `JWTAuthClient+Live` —
  the refresh path's contract is status-code-based by design.
- **Acceptance.** The type is public, `Sendable`, and returns `nil` for errors
  that are not `.badResponse` and for bodies that fail to decode.
- **Validation.** A `Core` test covering three cases: a well-formed
  `{"error":…,"code":…}` body, a body without `code`, and a non-`.badResponse`
  error. `mise exec -- tuist test AllTests`.

### 5. Rewrite `docs/api-clients.md` against the shipped code

- [ ] **Gap.** The guide contradicts the template it documents. It tells readers
      to add `kaishin/http-request-client` and `kaishin/jwt-auth-client` at
      `from: "0.1.0"`; `Package.swift` actually uses `indigo-ce/http-request-client`
      at 1.6.0 and `indigo-ce/jwt-auth-client` at 2.0.0. Its
      `JWTAuthClient+Live` example returns the refresh result with **no error
      mapping at all**, which silently reverts the 401-only credential-wipe
      contract that the shipped code implements and `AGENTS.md` calls out — a
      reader who follows the doc gets logged out by any timeout or 5xx. It also
      references `JSONDecoder.shared` / `JSONEncoder.shared`, while the template
      ships `.api` in `Core/Sources/Clients/JSONCoders.swift`. Do this after
      items 3 and 4 so the doc can describe code that exists.
- **Desired behavior.** Every snippet in the guide compiles against this
  repository's dependencies and reflects the contracts it actually enforces.
- **Scope.** Correct the package URLs and version floors; replace the
  `JWTAuthClient+Live` snippet with the shipped implementation including the
  `refreshRejected` mapping and its rationale; rename `.shared` coders to `.api`
  and point at `JSONCoders.swift` rather than restating the strategies; add a
  short section on surfacing server errors via `APIErrorBody`. Keep the existing
  structure (single vs. domain clients, path styles, request building, testing)
  and the `Path("api", "v1", …)` convention. Documentation only — no source
  changes.
- **Acceptance.** No occurrence of `kaishin/http-request-client`,
  `kaishin/jwt-auth-client`, `JSONDecoder.shared`, or `JSONEncoder.shared`
  remains; the refresh example maps 401 and only 401.
- **Validation.** Cross-read each snippet against `Package.swift`,
  `Core/Sources/Clients/JSONCoders.swift`, and
  `Core/Sources/Clients/JWTAuthClient+Live.swift`. No build required.

### 6. Standardize on `mise exec -- tuist` and fix the stale version in the guide

- [ ] **Gap.** The repo pins Tuist in `mise.toml` (4.202.2) but instructs bare
      `tuist` almost everywhere: `AGENTS.md` (lines 15–17, 21–22, 39),
      `.github/workflows/tests.yml` (lines 25, 28, 31), `README.md`,
      `.agents/skills/xcode-snapshot/SKILL.md`,
      `.agents/skills/tuist-inspect/SKILL.md`,
      `.agents/skills/using-tuist-generated-projects/SKILL.md`, and
      `.agents/skills/swift-upgrade/SKILL.md`. Only `ci_scripts/ci_post_clone.sh`
      goes through `mise exec --`. A shell without a mise hook resolves whatever
      `tuist` is on `PATH`, and a version mismatch corrupts the `.build`
      checkout state and breaks macro expansion across the workspace.
      Separately, `docs/migration-guide.md:68` still writes `tuist = "4.200.5"`
      into a generated `mise.toml`, which is behind the repo's own pin.
- **Desired behavior.** One documented invocation everywhere, and a migration
  guide that pins the version this repository actually uses.
- **Scope.** Replace bare `tuist …` with `mise exec -- tuist …` across the files
  above; update `docs/migration-guide.md:68` to `4.202.2`. Add one line to
  `AGENTS.md`'s "Build & test" section stating why (`mise.toml` is the pin; a
  stale `PATH` binary corrupts SPM state). Leave `ci_scripts/ci_post_clone.sh`
  as is. Do not change the pinned version in `mise.toml`.
- **Acceptance.** Every runnable `tuist` command in `AGENTS.md`, `README.md`,
  `docs/`, `.agents/`, and `.github/` is prefixed with `mise exec --`. Prose
  mentions (scheme names, command descriptions like "`tuist test AllTests`" in
  `Workspace.swift`'s comment) may stay unprefixed.
- **Validation.** Confirm the workflow file still parses as valid YAML and that
  `mise exec -- tuist generate --no-open` succeeds locally.

### 7. Make the `Sharing` → `SwiftSharing` module alias usable by first-party targets

- [ ] **Gap.** `Package.swift` renames the `Sharing` product to `SwiftSharing`
      and applies `-module-alias Sharing=SwiftSharing` to the external targets
      that need it. `Project.framework(…)` exposes a `usesSharing: Bool = false`
      parameter that applies the same flag, but **no project passes `true`** —
      `App`, `Core`, `Components`, `NotesListFeature`, and `NoteEditorFeature`
      all take the default. Meanwhile `AGENTS.md` instructs contributors to read
      with `@FetchAll` wrapped in `@ObservationStateIgnored` and lists `Sharing`
      as a foundation dependency. Anyone following that guidance writes
      `import Sharing` in a feature target and hits an unresolved-module error
      with no hint that a manifest flag is the fix.
- **Desired behavior.** The flag is either exercised by the template or clearly
  documented, so the failure is impossible to stumble into.
- **Scope.** Pass `usesSharing: true` in `Core/Project.swift` (the module that
  owns persistence and would import `Sharing` first) and document the rule in
  `AGENTS.md` under "Dependencies": any target that imports `Sharing` must be
  declared with `usesSharing: true`, because the product ships aliased as
  `SwiftSharing`. Add the same note to the `usesSharing` parameter in
  `Tuist/ProjectDescriptionHelpers/Project+Templates.swift`. No feature rewrite
  and no new `@FetchAll` usage in this item — that is a separate design change.
- **Acceptance.** `Core/Project.swift` sets `usesSharing: true`; `AGENTS.md`
  states the rule; the generated `Core` target carries
  `-module-alias Sharing=SwiftSharing` in `OTHER_SWIFT_FLAGS`.
- **Validation.** `mise exec -- tuist generate --no-open`, then
  `mise exec -- tuist build`. Temporarily adding `import Sharing` to a `Core`
  source must compile; revert before committing.

### 8. Wire the DEBUG network console to the existing shake modifier

- [ ] **Gap.** The template links `PulseUI` through `.indigoFoundation` and ships
      `Components/Sources/View+OnShake.swift`, and neither is used anywhere —
      `PulseUI` is imported by no source file and `onShake` has no call site.
      `README.md` and the dependency list advertise network debugging that the
      running app does not provide, so the cost of both is paid for nothing.
- **Desired behavior.** In DEBUG, requests made by the app are captured and a
  shake opens the console; release builds are untouched.
- **Scope.** Two changes. (a) In `Core/Sources/Clients/JWTAuthClient+Live.swift`,
  add a module-level `URLSessionProtocol` — `URLSessionProxy(configuration: .default)`
  under `#if DEBUG`, plain `URLSession(configuration: .default)` otherwise — and
  pass it as the `urlSession:` argument of the refresh call. (b) In
  `App/Sources/IndigoApp.swift`, add a `#if DEBUG` `@State` flag on the root
  view, present `PulseUI`'s `ConsoleView` in a `.fullScreenCover`, and toggle it
  from `.onShake { … }`. Guard the console presentation with `#if os(iOS)` —
  `onShake` is iOS-only. Requires item 3 (the refresh call must already go
  through `httpClient.send`, which takes the `urlSession:` argument). Add
  `.external(name: "Pulse")` to `.indigoFoundation` if `URLSessionProxy` is not
  visible via `PulseUI`; `"Pulse"` is already in `frameworkProductTypes`.
- **Acceptance.** A Release build contains no `PulseUI` view code and no
  `URLSessionProxy`; a DEBUG iOS build presents the console on shake; macOS
  builds are unaffected.
- **Validation.** `mise exec -- tuist generate --no-open`, then
  `mise exec -- tuist build` for both the `Indigo` (Debug) and
  `Indigo Release` schemes to prove the `#if` guards compile in both
  configurations. `mise exec -- tuist test AllTests` must stay green.
