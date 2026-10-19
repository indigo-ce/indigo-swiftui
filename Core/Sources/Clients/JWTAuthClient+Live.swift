import Dependencies
import Foundation
import HTTPRequestBuilder
import HTTPRequestClient
import JWTAuth
import Synchronization

// MARK: - Live implementation

// The template advertises "JWTAuth with automatic token refresh," so this is
// the demonstration wiring. `JWTAuthClient` ships `testValue`/`previewValue`
// from the library; providing `liveValue` (the real network refresh) is the
// app's job — that's what this file does.
//
// Adjust `host`, the refresh endpoint path, and the request/response models to
// match your backend. `host` is configuration-dependent: DEBUG builds talk to
// the local dev server at `http://localhost:4321`; Release builds carry the
// placeholder `https://api.example.com` for you to replace. The one part you
// should NOT change casually is the error mapping in `refresh` — see the note
// below.
extension JWTAuthClient: @retroactive DependencyKey {
  /// Base URL of your API. DEBUG builds point at the backend's local dev
  /// server; Release builds carry the placeholder production host — replace
  /// it with your real host (or read it from config).
  #if DEBUG
    public static let host = "http://localhost:4321"
  #else
    public static let host = "https://api.example.com"
  #endif

  public static let liveValue = Self(
    baseURL: { host },
    refresh: { tokens in
      @Dependency(\.authSessionGate) var gate

      // Single-flight: while a refresh from these tokens is in flight, every
      // other caller refreshing from the same tokens shares its outcome
      // instead of racing a second single-use request — see
      // `RefreshSingleFlight`.
      let newTokens = try await RefreshSingleFlight.shared.refresh(tokens) { tokens in
        @Dependency(\.httpRequestClient) var httpClient
        @Dependency(\.networkSession) var networkSession

        do {
          let response: SuccessResponse<TokenResponse> = try await httpClient.send(
            baseURL: host,
            decoder: .api,
            urlSession: networkSession
          ) {
            Path("api", "v1", "auth", "refresh-access")
            post(RefreshTokenRequest(refreshToken: tokens.refresh), encoder: .api)
          }
          return AuthTokens(
            access: response.value.accessToken,
            refresh: response.value.refreshToken
          )
        } catch let error as HTTPRequestClient.Error {
          // THE CONTRACT: only a definitive server rejection destroys the
          // session. A 401 from /api/v1/auth/refresh-access means the refresh
          // token is no longer valid — map it to `refreshRejected` so the
          // library wipes the stored credentials and forces re-authentication.
          //
          // Every other failure (timeout, DNS, offline, 5xx, decoding error —
          // `.invalidHTTPResponse`, `.decodingError`, `.other`) is transient:
          // rethrow it untouched so the library KEEPS the tokens and a later
          // retry can succeed. Mapping these to `refreshRejected` would log the
          // user out on a momentary network blip — a real bug this contract fixes.
          if case .badResponse(_, 401, _) = error {
            throw AuthTokens.Error.refreshRejected
          }
          throw error
        }
      }
      // Record the publish the library is about to perform with these
      // tokens, so a concurrent sign-out can veto it at save time — see
      // `AuthSessionGate`. Every caller sharing a flight stages its own
      // publish, because the library saves once per caller.
      await gate.stagePublish(newRefresh: newTokens.refresh, sourceRefresh: tokens.refresh)
      return newTokens
    }
  )
}

// MARK: - Refresh single flight

/// Serializes refresh requests per source refresh token.
///
/// The backend rotates refresh tokens and invalidates the old one
/// immediately, with no grace window. Two refreshes racing from the same
/// source token — callers whose `sendAuthenticated` requests overlap while
/// the access token is expired, for example when a superseding request
/// cancels one that is already refreshing — would hand the backend the same
/// single-use token twice: the loser is definitively rejected with 401,
/// which the shipped wiring maps to `refreshRejected`, destroying a session
/// that was never invalid. While a refresh of a given source token is in
/// flight, every other caller refreshing from that same token therefore
/// awaits and shares its outcome instead of firing a second request. A
/// refresh that has already ended is never shared: success replaced the
/// tokens callers hold, and a transient failure must be retried with a
/// fresh request.
///
/// The flight runs in its own task, so cancelling the caller that started it
/// does not abandon a rotation the server may already have performed.
final class RefreshSingleFlight: Sendable {
  static let shared = RefreshSingleFlight()

  private let inFlight = Mutex<[String: Task<AuthTokens, any Error>]>([:])

  func refresh(
    _ tokens: AuthTokens,
    perform: @escaping @Sendable (AuthTokens) async throws -> AuthTokens
  ) async throws -> AuthTokens {
    // Look up and register under one lock, so two callers can never both
    // miss and start separate flights. The task cannot reach its cleanup
    // before the lock is released, so the entry is always registered before
    // it is removed.
    let flight = inFlight.withLock { flights in
      if let existing = flights[tokens.refresh] {
        return existing
      }
      let task = Task { () -> AuthTokens in
        defer { _ = inFlight.withLock { $0.removeValue(forKey: tokens.refresh) } }
        return try await perform(tokens)
      }
      flights[tokens.refresh] = task
      return task
    }
    return try await flight.value
  }
}

// MARK: - Readability alias

/// Readability alias over the library's `jwtAuthClient` key — the transport
/// the examples in `docs/api-clients.md` call `send` / `sendAuthenticated` on.
/// Both keys address the same stored value: the alias has get and set, so
/// an override through either one (for example `$0.apiClient.refresh = …` in
/// a `withDependencies` block) is visible through the other.
extension DependencyValues {
  public var apiClient: JWTAuthClient {
    get { jwtAuthClient }
    set { jwtAuthClient = newValue }
  }
}

// MARK: - Refresh endpoint models

// Template request/response shapes for the token-refresh call. Rename fields to
// match your API; keys are sent as declared, and the date strategies in
// `JSONCoders.api` are the thing to adjust per backend.
private struct RefreshTokenRequest: Encodable, Sendable {
  let refreshToken: String
}

private struct TokenResponse: Decodable {
  let accessToken: String
  let refreshToken: String
}
