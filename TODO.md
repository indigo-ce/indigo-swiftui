# Template Project TODOs

## Architecture Sync

Ordered by priority; where an item depends on an earlier one it says so. Each is
scoped to one focused pull request. Validate Swift changes with
`mise exec -- tuist generate --no-open` followed by `mise exec -- tuist build`;
do not rely on a simulator run.

### 1. Keep Xcode Cloud output alive while `tuist generate` runs

- [ ] **Gap.** `ci_scripts/ci_post_clone.sh` runs `mise exec -- tuist generate`
      with no output of its own for the duration of the command. Generating a
      workspace with the full dependency graph can stay silent for many
      minutes, and Xcode Cloud kills a post-clone script that prints nothing
      for 15 minutes. `tuist install` already passes `--verbose` for exactly
      this reason; `generate` has no equivalent, so a slow generate fails the
      build with an inactivity timeout rather than a real error.
- **Desired behavior.** A background heartbeat prints a line every 60 seconds
  while `tuist generate` runs, is always stopped afterwards, and a failed
  generate still fails the script with the existing error message.
- **Scope.** Edit only `ci_scripts/ci_post_clone.sh`. Start the heartbeat
  (`while true; do echo "tuist generate running..."; sleep 60; done &`) just
  before the generate step and capture its PID. Under `set -e` a failing
  command exits before any following `$?` capture runs, so record the exit
  status without tripping it (for example
  `mise exec -- tuist generate || GENERATE_EXIT=$?` with `GENERATE_EXIT=0`
  set first, or a `trap 'kill $KEEPALIVE_PID 2>/dev/null' EXIT`), kill the
  heartbeat on both paths, and keep the `Failed to generate Xcode workspace`
  message and non-zero exit on failure. Leave the install step and the
  macro-fingerprint `defaults write` line as they are.
- **Dependencies.** None.
- **Acceptance.** On success the script exits 0 with the heartbeat process
  gone; on a failing generate it prints `Failed to generate Xcode workspace`,
  exits 1, and leaves no heartbeat running; no other line of the script
  changes behavior.
- **Validation.** `bash -n ci_scripts/ci_post_clone.sh` for syntax, then
  `mise exec -- tuist generate --no-open` and `mise exec -- tuist build` to
  confirm nothing else moved. The Xcode Cloud timeout itself cannot be
  exercised headlessly.

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
