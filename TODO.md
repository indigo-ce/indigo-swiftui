# Template Project TODOs

## Architecture Sync

Ordered by priority; where an item depends on an earlier one it says so. Each is
scoped to one focused pull request. Validate Swift changes with
`mise exec -- tuist generate --no-open` followed by `mise exec -- tuist build`;
do not rely on a simulator run.

### 1. Send an explicit JSON content type on the sign-in request

- [x] **Gap.** `SessionClient.signIn` in `Core/Sources/Clients/SessionClient.swift`
      posts to `api/v1/auth/sign-in` with `method(.post)` and `basicAuth(...)`
      only. The route takes its credentials from the `Authorization` header and
      has no body, so the request carries no `Content-Type` at all. The backend
      has been observed to reject a bodyless POST that does not declare a JSON
      content type, which would make the shipped sign-in fail against a real
      deployment while every stubbed test passes — the existing tests record
      the method, path, body, and `Authorization` header but never a content
      type.
- **Desired behavior.** The sign-in request always declares
  `Content-Type: application/json`, even though it has no body.
- **Scope.** Add the JSON content-type modifier to the sign-in request builder
  in `SessionClient.signIn` (`jsonContentRequest` from `HTTPRequestBuilder`; if
  the pinned version lacks it, set the header directly with
  `header(key: "Content-Type", value: "application/json")`). Extend the
  `AuthStubProtocol` recorder in `Core/Tests/SessionClientTests.swift` with a
  `Content-Type` field and assert it in
  `signInExchangesCredentialsAndStoresTheTokens`. Leave the revoke request
  alone — it carries a JSON body, so the encoder already sets the header. Update
  the sign-in paragraph of `docs/api-clients.md` only if it lists the request's
  headers.
- **Dependencies.** None.
- **Acceptance.** The recorded sign-in request has `Content-Type` equal to
  `application/json` and still has an empty body and the same `Authorization`
  header; every existing `SessionClientTests` case still passes.
- **Validation.** `mise exec -- tuist generate --no-open`, then
  `mise exec -- tuist build` (this compiles the test target, so the new
  assertion must build). The assertion itself runs in CI's
  `tuist test --platform ios`.

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
