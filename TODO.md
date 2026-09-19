# Template Project TODOs

## Architecture Sync

Ordered: earlier items unblock later ones. Each is scoped to one focused pull
request. Validate Swift changes with `mise exec -- tuist generate --no-open`
followed by `mise exec -- tuist build`; do not rely on a simulator run.

### 1. Upgrade the Swift toolchain and dependency graph

- [x] **Gap.** The project is on Swift tools `6.2` with an older locked dependency
      graph. The database stack has also had compatibility issues across
      `sqlite-data` and `swift-structured-queries` releases, so selectively
      bumping one transitive package is not a reliable maintenance strategy.
- **Desired behavior.** The template uses Swift tools `6.4` and the latest
  compatible direct dependencies as one deliberately re-resolved graph.
- **Scope.** Update `Package.swift` to Swift tools `6.4`, raise direct dependency
  floors to the versions reported by `swift outdated`, and re-resolve
  `Package.resolved`. The database stack should resolve to `sqlite-data 1.12.0`,
  `swift-structured-queries 0.39.2`, and GRDB `7.11.1`.
- **Acceptance.** `Package.swift` declares GRDB and `swift-structured-queries` as
  root dependencies; `Package.resolved` shows `sqlite-data 1.12.0`,
  `swift-structured-queries 0.39.2`, and GRDB `7.11.1`.
- **Validation.** `mise exec -- tuist install`, then
  `mise exec -- tuist generate --no-open`, iOS and macOS builds, and
  `mise exec -- tuist test AllTests`.

### 2. Declare `DependenciesMacros` in `.indigoFoundation`

- [x] **Gap.** `Core/Sources/Clients/NotesClient.swift` imports
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

### 3. Align `JSONCoders.api` with the JSON the template actually exchanges

- [x] **Gap.** `Core/Sources/Clients/JSONCoders.swift` configures `.api` with
      `convertToSnakeCase`/`convertFromSnakeCase` and a plain `.iso8601` date
      strategy. Both fight the only wire models the template ships.
      `JWTAuthClient+Live.swift` declares `RefreshTokenRequest.refreshToken` and
      `TokenResponse.accessToken`/`.refreshToken`, so the encoder silently
      rewrites the refresh body to `{"refresh_token": …}` — a key the request
      model never mentions — and the decoder expects `access_token` back. No
      test catches it because nothing exercises the live path. Separately,
      `.iso8601` accepts only `.withInternetDateTime`, so a timestamp carrying
      fractional seconds (`…T12:00:00.123Z`, which JSON backends routinely emit)
      throws `DecodingError.dataCorrupted`.
- **Desired behavior.** `.api` round-trips the template's own models with their
  declared key names and tolerates both ISO-8601 spellings on the way in.
- **Scope.** Drop `keyEncodingStrategy` and `keyDecodingStrategy` so keys pass
  through verbatim. Replace `decoder.dateDecodingStrategy = .iso8601` with a
  `.custom` strategy that tries `ISO8601DateFormatter` with
  `[.withInternetDateTime, .withFractionalSeconds]`, falls back to
  `[.withInternetDateTime]`, and throws `DecodingError.dataCorrupted` naming the
  offending string when neither parses. Keep
  `encoder.dateEncodingStrategy = .iso8601`. Update the file's header comment,
  which currently promises "snake_case on the wire", and the matching claim at
  `Core/Sources/Clients/JWTAuthClient+Live.swift:64` that `.api` "handles
  snake_case ⇄ camelCase by default". Both should say that keys are sent as
  declared and point at the strategies as the thing to adjust per backend.
  `JWTAuthClient+Live.swift` is the only consumer of `.api` today, so nothing
  else needs touching.
- **Acceptance.** `JSONCoders.swift` declares no key strategy; neither comment
  claims key conversion; a `Date` encoded by `.api` and decoded by `.api`
  survives the round trip.
- **Validation.** Add `Core` tests: encoding a camelCase `Encodable` emits
  `refreshToken`, not `refresh_token`; decoding
  `{"accessToken":…,"refreshToken":…}` into a camelCase `Decodable` succeeds;
  decoding an ISO-8601 timestamp succeeds both with and without fractional
  seconds; decoding a malformed date string throws. `mise exec -- tuist generate
  --no-open`, then `mise exec -- tuist test AllTests`.

### 4. Build the token-refresh request with `HTTPRequestBuilder`

- [x] **Gap.** `Core/Sources/Clients/JWTAuthClient+Live.swift` is the template's
      only networking example, and it hand-assembles a `URLRequest`:
      `URL(string: "\(host)/auth/refresh")!` force-unwrapped, `httpMethod`,
      `Content-Type`, and `httpBody` set by hand. `HTTPRequestBuilder` ships in
      `.indigoFoundation` for exactly this and is imported nowhere, so the
      template demonstrates the opposite of the stack it bundles. The path also
      omits the `api/v1` prefix that `docs/api-clients.md` uses throughout.
- **Desired behavior.** The refresh call is declarative, has no force-unwrap, and
  models the request shape every cloned project will copy.
- **Scope.** Add `import HTTPRequestBuilder`, drop the manual `URLRequest`
  construction, and replace it with the builder form. Keep the explicit result
  annotation — `send` is overloaded on `Response<T, ServerError>` and
  `SuccessResponse<T>`, so `T` cannot be inferred from a bare `.value`:

  ```swift
  let response: SuccessResponse<TokenResponse> = try await httpClient.send(
    baseURL: host,
    decoder: .api
  ) {
    Path("api", "v1", "auth", "refresh-access")
    post(RefreshTokenRequest(refreshToken: tokens.refresh), encoder: .api)
  }
  return AuthTokens(
    access: response.value.accessToken,
    refresh: response.value.refreshToken
  )
  ```

  `post` already applies the `POST` method and the JSON `Content-Type`/`Accept`
  headers, so no manual header work remains. **Preserve the error mapping
  exactly**: only `HTTPRequestClient.Error.badResponse(_, 401, _)` maps to
  `AuthTokens.Error.refreshRejected`; everything else rethrows untouched. Keep
  the explanatory comment. Do not change `host`, `RefreshTokenRequest`,
  `TokenResponse`, or `JSONCoders`.
- **Acceptance.** No `URL(string:)!` and no `httpMethod`/`setValue`/`httpBody`
  assignment remains in the file; the closure returns `AuthTokens` built from the
  decoded `TokenResponse`; the 401-only wipe contract described in `AGENTS.md` is
  unchanged.
- **Validation.** `mise exec -- tuist generate --no-open` then
  `mise exec -- tuist build`. Add a `Core` test that drives the real closure:
  `withDependencies { $0.httpRequestClient.send = { _, _ in throw HTTPRequestClient.Error.badResponse(UUID(), 401, "") } }`
  around `JWTAuthClient.liveValue.refresh(…)` must surface
  `AuthTokens.Error.refreshRejected`, and the same test with `500` must surface
  the original `.badResponse`. `HTTPRequestClient` is a `@DependencyClient`, so
  its single `send` endpoint is the only thing the test has to stub. Run with
  `mise exec -- tuist test AllTests`.

### 5. Add `APIErrorBody` for reading 4xx response bodies

- [x] **Gap.** `HTTPRequestClient` reports non-2xx responses as
      `.badResponse(_, status, body)` with the body as a raw `String`. The
      template has no way to read it, so every 4xx collapses into an opaque
      failure. `Core/Sources/IndigoError.swift` carries a single
      `case invalidToken` and offers no server-message path. Depends on item 4
      landing first so the new type has a live call site to document.
- **Desired behavior.** A cloned project can recover the server's message and,
  when the endpoint supplies one, a stable error code it can branch on — falling
  back to the server's prose for everything else.
- **Scope.** Add `Core/Sources/Clients/APIErrorBody.swift` with a
  `public struct APIErrorBody: Decodable, Sendable` holding `error: String` and
  `code: String?`, plus a `public static func from(_ error: any Error) -> APIErrorBody?`
  that pattern-matches `HTTPRequestClient.Error.badResponse`, converts the body
  string to `Data`, and decodes. Document the two fields as the template means
  them: `error` is a human-readable server message suitable for display or
  logging, and `code` is an optional stable machine-readable identifier that only
  some endpoints send — which is why branching code must handle `nil`. Do not
  promise that either field is localized; a cloned project's backend decides
  that, and the doc comment should say so rather than guess. Do not change
  `IndigoError` and do not wire this into `JWTAuthClient+Live` — the refresh
  path's contract is status-code-based by design.
- **Acceptance.** The type is public, `Sendable`, and returns `nil` for errors
  that are not `.badResponse` and for bodies that fail to decode.
- **Validation.** A `Core` test covering three cases: a well-formed
  `{"error":…,"code":…}` body, a body without `code`, and a non-`.badResponse`
  error. `mise exec -- tuist test AllTests`.

### 6. Rewrite `docs/api-clients.md` against the shipped code

- [x] **Gap.** The guide contradicts the template it documents. It tells readers
      to add `kaishin/http-request-client` and `kaishin/jwt-auth-client` at
      `from: "0.1.0"`; `Package.swift` actually uses `indigo-ce/http-request-client`
      at 1.6.0 and `indigo-ce/jwt-auth-client` at 2.0.0. Its
      `JWTAuthClient+Live` example returns the refresh result with **no error
      mapping at all**, which silently reverts the 401-only credential-wipe
      contract that the shipped code implements and `AGENTS.md` calls out — a
      reader who follows the doc gets logged out by any timeout or 5xx. Its
      "JSON Encoding/Decoding" section also defines its own
      `JSONDecoder.shared` / `JSONEncoder.shared` and threads `decoder: .shared`
      / `encoder: .shared` through eight call sites, while the template ships
      `.api` in `Core/Sources/Clients/JSONCoders.swift`. Do this after items 3,
      4, and 5 so the doc can describe coders and types that exist.
- **Desired behavior.** Every snippet in the guide compiles against this
  repository's dependencies and reflects the contracts it actually enforces.
- **Scope.** Correct the package URLs and version floors; replace the
  `JWTAuthClient+Live` snippet with the shipped implementation including the
  `refreshRejected` mapping and its rationale; replace the hand-rolled `.shared`
  coder definitions with a pointer to `JSONCoders.swift` instead of restating
  the strategies, and rename every `decoder: .shared` / `encoder: .shared` call
  site to `.api`; add a short section on surfacing server errors via
  `APIErrorBody`. Keep the existing structure (single vs. domain clients, path
  styles, request building, testing) and the `Path("api", "v1", …)` convention.
  Documentation only — no source changes.
- **Acceptance.** `rg 'kaishin/|\.shared' docs/api-clients.md` returns nothing:
  no `kaishin/…` package URL, no `static let shared` coder definition, and no
  `decoder:`/`encoder: .shared` argument survives. The refresh example maps 401
  and only 401.
- **Validation.** Cross-read each snippet against `Package.swift`,
  `Core/Sources/Clients/APIErrorBody.swift`,
  `Core/Sources/Clients/JSONCoders.swift`, and
  `Core/Sources/Clients/JWTAuthClient+Live.swift`. No build required.

### 7. Standardize on `mise exec -- tuist` and fix the stale version in the guide

- [x] **Gap.** The repo pins Tuist in `mise.toml` (4.202.2) but instructs bare
      `tuist` almost everywhere: `AGENTS.md` (lines 15–17, 21–22, 39),
      `.github/workflows/tests.yml` (lines 27, 30, 33), `README.md` (26–27,
      104–107, 115), `docs/migration-guide.md` (540, 543, 663–670),
      `.agents/skills/xcode-snapshot/SKILL.md`,
      `.agents/skills/tuist-inspect/SKILL.md`,
      `.agents/skills/using-tuist-generated-projects/SKILL.md`,
      `.agents/skills/swift-upgrade/SKILL.md`, and
      `.agents/skills/bootstrap/SKILL.md:36`. Only `ci_scripts/ci_post_clone.sh`
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
  as is. Do not change the pinned version in `mise.toml`. Line numbers are a
  starting point, not the contract — re-grep for `tuist ` before finishing, since
  earlier edits in the same file shift them.
- **Acceptance.** Every runnable `tuist` command in `AGENTS.md`, `README.md`,
  `docs/`, `.agents/`, and `.github/` is prefixed with `mise exec --`. Prose
  mentions (scheme names, command descriptions like "`tuist test AllTests`" in
  `Workspace.swift`'s comment) may stay unprefixed.
- **Validation.** Confirm the workflow file still parses as valid YAML and that
  `mise exec -- tuist generate --no-open` succeeds locally.

### 8. Make the `Sharing` → `SwiftSharing` module alias usable by first-party targets

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

### 9. Wire the DEBUG network console to the existing shake modifier

- [ ] **Gap.** The template links `PulseUI` through `.indigoFoundation` and ships
      `Components/Sources/View+OnShake.swift`, and neither is used anywhere —
      `PulseUI` is imported by no source file and `onShake` has no call site.
      `README.md` and the dependency list advertise network debugging that the
      running app does not provide, so the cost of both is paid for nothing.
- **Desired behavior.** In DEBUG, requests made by the app are captured and a
  shake opens the console; release builds are untouched.
- **Scope.** Three changes. (a) Add `.external(name: "Pulse")` to
  `.indigoFoundation` in `Tuist/ProjectDescriptionHelpers/Project+Templates.swift`
  — `URLSessionProxy` and `URLSessionProtocol` are `Pulse` types, not `PulseUI`
  ones, and `"Pulse"` is already in `Package.swift`'s `frameworkProductTypes`, so
  no package change is needed. (b) In
  `Core/Sources/Clients/JWTAuthClient+Live.swift`, `import Pulse` and add a
  module-level `URLSessionProtocol` — `URLSessionProxy(configuration: .default)`
  under `#if DEBUG`, plain `URLSession(configuration: .default)` otherwise — then
  pass it as the `urlSession:` argument of the refresh call. (c) In
  `App/Sources/IndigoApp.swift`, add a `#if DEBUG` `@State` flag on the root
  view, present `PulseUI`'s `ConsoleView` in a `.fullScreenCover`, and toggle it
  from `.onShake { … }`. Guard the console presentation with `#if os(iOS)` —
  `onShake` is iOS-only. Requires item 4: the refresh call must already go
  through `httpClient.send(baseURL:decoder:urlSession:middleware:)`, which is
  where the `urlSession:` argument exists.
- **Acceptance.** A Release build contains no `PulseUI` view code and no
  `URLSessionProxy`; a DEBUG iOS build presents the console on shake; macOS
  builds are unaffected.
- **Validation.** `mise exec -- tuist generate --no-open`, then
  `mise exec -- tuist build Indigo --configuration Debug` and
  `mise exec -- tuist build "Indigo Release" --configuration Release` to prove
  the `#if` guards compile both ways — passing the scheme name alone does not
  select the configuration. `mise exec -- tuist test AllTests` must stay green.
