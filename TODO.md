# Template Project TODOs

## Architecture Sync

Ordered by priority; where an item depends on an earlier one it says so. Each is
scoped to one focused pull request. Validate Swift changes with
`mise exec -- tuist generate --no-open` followed by `mise exec -- tuist build`;
do not rely on a simulator run.

### 1. Ship the `apiClient` dependency alias the guide already assumes

- [x] **Gap.** `docs/api-clients.md` writes its examples against
      `@Dependency(\.apiClient)` — the transport that `send` /
      `sendAuthenticated` are called on — at `:53`, `:149`, `:207`, and `:593`,
      including the canonical "Basic Structure" snippet at `:43-61` that the
      whole guide builds on. The template ships no such key: `rg -n 'apiClient'
      Core/` returns nothing, and the only definition anywhere is a four-line
      snippet at `:304-312` introduced with "Create an alias for convenience",
      which the reader has to notice and hand-copy. Every example before and
      after it fails to compile in a fresh clone until they backtrack. A second
      invented name, `\.apiEndpointClient` (`:8`, `:514`, `:538`), stands for
      the reader's *own* endpoint client — but the guide registers that client
      as `myAPIClient` at `:63-68`, so the document contradicts itself about
      what the reader just declared.
- **Desired behavior.** Every dependency key a guide example uses either ships
  in the template or is declared earlier in the same guide under the name the
  example uses.
- **Scope.** `Core/Sources/Clients/JWTAuthClient+Live.swift` and
  `docs/api-clients.md`. Nothing else.
  - Add to `JWTAuthClient+Live.swift`, below the `liveValue` extension:

    ```swift
    extension DependencyValues {
      public var apiClient: JWTAuthClient {
        get { jwtAuthClient }
        set { jwtAuthClient = newValue }
      }
    }
    ```

    Give it get **and** set, not get-only. `RootFeatureTests.makeStore`
    overrides the client with `$0.jwtAuthClient.refresh = …`; a read-only alias
    would split reads (`\.apiClient`) from overrides (`\.jwtAuthClient`), which
    is exactly the papercut the alias exists to remove. Add a doc comment
    saying it is a readability alias over the library's `jwtAuthClient` and
    that both keys address the same stored value.
  - In `docs/api-clients.md`, replace the "Create an alias for convenience"
    sentence and its snippet at `:304-312` with a statement that `Core` ships
    the alias, naming `Core/Sources/Clients/JWTAuthClient+Live.swift`, and show
    the shipped get/set form.
  - Rename `\.apiEndpointClient` to `\.myAPIClient` at `:8`, `:514`, and `:538`
    so those examples match the registration the guide already shows at
    `:63-68`.
  - Do not add a new `@DependencyClient` struct, do not touch `NotesClient`,
    and do not rename `jwtAuthClient` anywhere — the alias is purely additive.
- **Dependencies.** None.
- **Acceptance.** `@Dependency(\.apiClient) var apiClient` compiles in any
  target that imports `Core` and `JWTAuth`; `$0.apiClient.refresh = …`
  compiles inside a `withDependencies` block and is visible through
  `\.jwtAuthClient`; `rg -n 'apiEndpointClient' docs/` returns nothing; the
  guide no longer tells the reader to create the alias themselves.
- **Validation.** `mise exec -- tuist generate --no-open`,
  `mise exec -- tuist build`, then `mise exec -- tuist test AllTests`. To pin
  the get/set behavior, temporarily point `RootFeatureTests.makeStore` at
  `$0.apiClient.refresh` instead of `$0.jwtAuthClient.refresh`, confirm the
  suite still passes, and revert the override before committing.

### 2. Extend `usesSharing` to the generated test targets

- [ ] **Gap.** `Project.framework(usesSharing:)` in
      `Tuist/ProjectDescriptionHelpers/Project+Templates.swift:36-86` builds
      `baseSettings` at `:43-49` and applies
      `-module-alias Sharing=SwiftSharing` to the framework target only. The
      `\(name)Tests` target it generates alongside (`:75-83`) is declared with
      no `settings:` at all, so `import Sharing` in
      `Core/Tests/…` or `RootFeature/Tests/…` fails with an unresolved module
      even though the project passed `usesSharing: true`. The app target already
      had this fixed by hand (`App/Project.swift:38` and `:54` set the flag on
      both the app and its test target), so the helper is now the only place
      where the rule does not hold. This bites first on auth work: a clone
      testing session state has to construct `@Shared(.authSession)` in the test
      target, which needs the alias.
- **Desired behavior.** `usesSharing: true` covers a project's framework target
  and its test target, so a target that can use `Sharing` can also be tested
  against it.
- **Scope.** In `Project.framework`, build a second settings dictionary that
  carries only `"OTHER_SWIFT_FLAGS": "$(inherited) -module-alias Sharing=SwiftSharing"`
  when `usesSharing` is `true` (empty otherwise), and pass it as the
  `\(name)Tests` target's `settings:`. Do not copy `DEFINES_MODULE` or
  `SWIFT_VERSION` onto the test target — the flag is the whole change. Update
  the `AGENTS.md` "Dependencies" paragraph so the rule reads that
  `usesSharing: true` aliases the framework **and** its test bundle. Touch no
  per-project `Project.swift`, `Package.swift`, or `App/Project.swift`.
- **Acceptance.** After generation, `CoreTests` and `RootFeatureTests` carry
  `-module-alias Sharing=SwiftSharing` in `OTHER_SWIFT_FLAGS`, while
  `ComponentsTests`, `NotesListFeatureTests`, and `NoteEditorFeatureTests`
  (projects that do not pass `usesSharing`) do not.
- **Validation.** `mise exec -- tuist generate --no-open`, then
  `rg -n 'module-alias' Core/Core.xcodeproj/project.pbxproj` to confirm the test
  target picked it up. Temporarily add `import Sharing` to
  `Core/Tests/CoreTests.swift`, run `mise exec -- tuist test AllTests`, and
  revert the import before committing.

### 3. Map the version build settings into the app's `Info.plist`

- [ ] **Gap.** `Configs/Debug.xcconfig` and `Configs/Release.xcconfig` set
      `MARKETING_VERSION=0.0.1` and `CURRENT_PROJECT_VERSION=1`, and
      `Core/Sources/Bundle+Extension.swift` ships `releaseVersionNumber`,
      `buildVersionNumber`, and `fullVersionString`, which read
      `CFBundleShortVersionString` and `CFBundleVersion` out of the Info.plist.
      Nothing connects the two: `App/Project.swift` passes
      `infoPlist: .extendingDefault(with:)` with only `UILaunchScreen`, so the
      bundle gets Tuist's defaults and the xcconfig values never reach it.
      Bumping the version in the xcconfig — the one place a clone would look —
      changes nothing the app can report.
- **Desired behavior.** The xcconfig is the single place a version is set, and
  the bundle reflects it.
- **Scope.** Add `"CFBundleShortVersionString": "$(MARKETING_VERSION)"` and
  `"CFBundleVersion": "$(CURRENT_PROJECT_VERSION)"` to the `.extendingDefault`
  dictionary in `App/Project.swift`. Do not change the values in either
  xcconfig, do not touch `Bundle+Extension.swift`, and do not add a plist to any
  framework target — only the app bundle carries a user-facing version.
- **Acceptance.** The generated app Info.plist under `App/Derived/InfoPlists/`
  (filename follows `appTarget`) contains both keys with the `$(…)` references,
  and a Debug build resolves `CFBundleShortVersionString` to `0.0.1`.
- **Validation.** `mise exec -- tuist generate --no-open`, then
  `rg 'MARKETING_VERSION|CURRENT_PROJECT_VERSION' App/Derived/InfoPlists/`.
  Build with `mise exec -- tuist build` and read
  `CFBundleShortVersionString` back out of the built `Info.plist` with
  `plutil -p`.

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
