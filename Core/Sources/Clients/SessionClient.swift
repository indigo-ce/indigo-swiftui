import Dependencies
import DependenciesMacros
import Foundation
import HTTPRequestBuilder
import JWTAuth
import OSLog
import Sharing
import SQLiteData

private let logger = Logger(subsystem: "Indigo", category: "SessionClient")

// MARK: - Live implementation

/// The one sign-out operation the template ships. It runs in a fixed order:
/// revoke the refresh token on the server on a **best-effort** basis, then
/// destroy the local credentials. A revoke failure (offline, 5xx, timeout) is
/// logged and never keeps the user signed in — the stored token material is
/// what actually ends the session on this device, so only its destruction can
/// throw. The resulting session change is what the observer in `RootFeature`
/// already reacts to: the user-scoped cache is wiped with no extra wiring.
///
/// Call this from a sign-out control instead of `authTokensClient.destroy()`:
/// destroying locally alone leaves the refresh token alive on the server,
/// where anyone who copied it off the device can keep minting access tokens
/// until it expires.
@DependencyClient
public struct SessionClient: Sendable {
  public var signOut: @Sendable () async throws -> Void
}

extension SessionClient: DependencyKey {
  // Dependencies are resolved inside the closure — the way
  // `JWTAuthClient+Live.swift` does — so `withDependencies` overrides apply
  // at call time.
  public static let liveValue: SessionClient = Self(
    signOut: {
      @Dependency(\.authTokensClient) var authTokensClient
      @Dependency(\.authSessionGate) var gate
      @Shared(.authSession) var session: AuthSession?

      // Open the sign-out window before touching the network: from here until
      // `destroy` settles, the gated `authTokensClient` (`.gated`, installed
      // in `App`) refuses every credential publish, so a token refresh that
      // completes mid-sign-out cannot resurrect the session being destroyed.
      // See `AuthSessionGate`.
      await gate.beginSignOut()

      if let refresh = session?.tokens?.refresh {
        await revokeRefreshToken(refresh)
      }

      try await authTokensClient.destroy()
    }
  )

  public static var previewValue: SessionClient {
    SessionClient(signOut: {})
  }

  public static var testValue: SessionClient {
    SessionClient()
  }
}

extension DependencyValues {
  public var sessionClient: SessionClient {
    get { self[SessionClient.self] }
    set { self[SessionClient.self] = newValue }
  }
}

// MARK: - Revoke

/// Revokes `refresh` on the server, best effort: a failure is logged and
/// swallowed. Shared by `signOut` and the gated `AuthTokensClient`, which
/// revokes refresh tokens it refuses to store.
func revokeRefreshToken(_ refresh: String) async {
  @Dependency(\.apiClient) var apiClient
  @Dependency(\.networkSession) var networkSession

  // The route authenticates with the refresh token in the body, so this is
  // `send`, not `sendAuthenticated`: refreshing an already-expired access
  // token first would rotate the very token about to be revoked, and fail
  // outright when offline.
  do {
    let _: RevokeResponse = try await apiClient.send(
      decoder: .api,
      urlSession: networkSession
    ) {
      Path("api", "v1", "auth", "revoke-access")
      post(RevokeRequest(refreshToken: refresh), encoder: .api)
    }.value
  } catch {
    // Best effort: the server may still hold a live refresh token, but
    // callers must not be blocked by an unreachable revoke endpoint.
    logger.error("Refresh-token revoke failed: \(error, privacy: .public)")
  }
}

// MARK: - Revoke endpoint models

// Template request/response shapes for the sign-out call. Keep them private to
// this file, the same way the refresh models live in `JWTAuthClient+Live.swift`.
private struct RevokeRequest: Encodable, Sendable {
  let refreshToken: String
}

private struct RevokeResponse: Decodable {
  let success: Bool
}
