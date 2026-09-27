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
      @Dependency(\.apiClient) var apiClient
      @Dependency(\.authTokensClient) var authTokensClient
      @Dependency(\.networkSession) var networkSession
      @Shared(.authSession) var session: AuthSession?

      if let refresh = session?.tokens?.refresh {
        // The route authenticates with the refresh token in the body, so this
        // is `send`, not `sendAuthenticated`: refreshing an already-expired
        // access token first would rotate the very token about to be revoked,
        // and fail outright when offline.
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
          // the local destroy below is what ends the session on this device,
          // so the failure must not block sign-out.
          logger.error("Refresh-token revoke failed: \(error, privacy: .public)")
        }
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

// MARK: - Revoke endpoint models

// Template request/response shapes for the sign-out call. Keep them private to
// this file, the same way the refresh models live in `JWTAuthClient+Live.swift`.
private struct RevokeRequest: Encodable, Sendable {
  let refreshToken: String
}

private struct RevokeResponse: Decodable {
  let success: Bool
}
