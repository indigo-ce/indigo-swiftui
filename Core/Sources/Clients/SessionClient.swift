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

/// The session lifecycle operations the template ships: sign-in, sign-out,
/// and the two unauthenticated account-entry routes served alongside them —
/// sign-up and password-reset request.
///
/// Signing up does not sign in: the token the sign-up route answers with is a
/// server-side web session token, not the JWT pair `authTokensClient` stores,
/// so a new account must still go through `signIn` before the app holds a
/// session. Neither new operation reads or writes stored credentials; request
/// errors propagate untouched so callers can surface the server's message
/// through `APIErrorBody.from(error)`.
///
/// Sign-out runs in a fixed order: revoke the refresh token on the server on
/// a **best-effort** basis, then destroy the local credentials. A revoke
/// failure (offline, 5xx, timeout) is logged and never keeps the user signed
/// in — the stored token material is what actually ends the session on this
/// device, so only its destruction can throw. The resulting session change is
/// what the observer in `RootFeature` already reacts to: the user-scoped cache
/// is wiped with no extra wiring.
///
/// Call this from a sign-out control instead of `authTokensClient.destroy()`:
/// destroying locally alone leaves the refresh token alive on the server,
/// where anyone who copied it off the device can keep minting access tokens
/// until it expires.
///
/// Sign-in is the mirror image: it exchanges credentials for tokens and
/// persists them through the gated credential client. Persisting is what
/// publishes `.valid` on `@Shared(.authSession)`; the observer in
/// `RootFeature` then reacts with no extra wiring (and wipes the user-scoped
/// cache when the token's `sub` claim switches account). A failed exchange
/// stores nothing: every request error propagates untouched to the caller,
/// who can surface the server's message through `APIErrorBody.from(error)`.
@DependencyClient
public struct SessionClient: Sendable {
  public var signIn: @Sendable (_ email: String, _ password: String) async throws -> Void
  public var signOut: @Sendable () async throws -> Void
  public var signUp:
    @Sendable (_ name: String, _ email: String, _ password: String) async throws -> Void
  public var requestPasswordReset: @Sendable (_ email: String) async throws -> Void
}

extension SessionClient: DependencyKey {
  // Dependencies are resolved inside the closure — the way
  // `JWTAuthClient+Live.swift` does — so `withDependencies` overrides apply
  // at call time.
  public static let liveValue: SessionClient = Self(
    signIn: { email, password in
      @Dependency(\.apiClient) var apiClient
      @Dependency(\.networkSession) var networkSession
      @Dependency(\.authTokensClient) var authTokensClient
      @Shared(.authSession) var session: AuthSession?

      // `send`, not `sendAuthenticated`: there is no session yet. The route
      // authenticates with `Authorization: Basic base64(email:password)`, no
      // body, and answers 200 with the token pair (`user` and `tokenType` are
      // ignored — identity is read from the token's `sub` claim, as
      // `RootFeature` already does). Saving through the gated credential
      // client is what publishes the session; any request failure leaves the
      // stored credentials untouched and rethrows.
      let response: SignInResponse = try await apiClient.send(
        decoder: .api,
        urlSession: networkSession
      ) {
        Path("api", "v1", "auth", "sign-in")
        // No body, but the server still rejects the POST without an explicit
        // JSON content type.
        method(.post)
        jsonContentRequest
        basicAuth(username: email, password: password)
      }.value

      // Signing in can also switch accounts: the save below overwrites the
      // previous session, and its refresh token would stay live on the
      // server with no copy left on the device to revoke later. Capture and
      // revoke it first — the same reason `signOut` revokes before destroy.
      if let displacedRefresh = session?.tokens?.refresh {
        await revokeRefreshToken(displacedRefresh)
      }

      try await authTokensClient.save(
        AuthTokens(access: response.accessToken, refresh: response.refreshToken)
      )
    },
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
    },
    signUp: { name, email, password in
      @Dependency(\.apiClient) var apiClient
      @Dependency(\.networkSession) var networkSession

      // `send`, not `sendAuthenticated`: there is no session yet. The route
      // takes a JSON body and answers 200 with `{user, token}` — but that
      // token is a server-side web session token, not the JWT pair
      // `authTokensClient` stores, so this closure deliberately never touches
      // it or the stored credentials: signing up does not sign in, and the
      // account must still go through `signIn`. No `callbackURL` is sent, so
      // the backend default applies. A 400 (malformed body, taken email)
      // rethrows; read it with `APIErrorBody.from(error)`.
      let _: SignUpResponse = try await apiClient.send(
        decoder: .api,
        urlSession: networkSession
      ) {
        Path("api", "v1", "auth", "sign-up")
        post(SignUpRequest(name: name, email: email, password: password), encoder: .api)
      }.value
    },
    requestPasswordReset: { email in
      @Dependency(\.apiClient) var apiClient
      @Dependency(\.networkSession) var networkSession

      // Asks the server to send the password-reset email for `email`. No
      // `redirectTo` is sent, so the backend default applies. Errors propagate
      // untouched; nothing about the stored session is read or written.
      let _: ForgotPasswordResponse = try await apiClient.send(
        decoder: .api,
        urlSession: networkSession
      ) {
        Path("api", "v1", "auth", "forgot-password")
        post(ForgotPasswordRequest(email: email), encoder: .api)
      }.value
    }
  )

  public static var previewValue: SessionClient {
    SessionClient(
      signIn: { _, _ in },
      signOut: {},
      signUp: { _, _, _ in },
      requestPasswordReset: { _ in }
    )
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

// MARK: - Sign-in endpoint models

// The sign-in response shape. Keep it private to this file, the same way the
// revoke models below and the refresh models in `JWTAuthClient+Live.swift`
// are. The backend also sends `user` and `tokenType`, which are deliberately
// not modeled: identity is read from the token's `sub` claim.
private struct SignInResponse: Decodable, Sendable {
  let accessToken: String
  let refreshToken: String
}

// MARK: - Sign-up endpoint models

// The sign-up response shape. Keep it private to this file, like the other
// endpoint models here. The backend sends `user` and `token`, neither of
// which this operation uses — the token is a web session token, not the JWT
// pair `authTokensClient` stores — so nothing is decoded.
private struct SignUpResponse: Decodable, Sendable {}

private struct SignUpRequest: Encodable, Sendable {
  let name: String
  let email: String
  let password: String
}

// MARK: - Forgot-password endpoint models

// The forgot-password response shape: `{status, message}`. Neither field is
// used, so nothing is decoded.
private struct ForgotPasswordResponse: Decodable, Sendable {}

private struct ForgotPasswordRequest: Encodable, Sendable {
  let email: String
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
