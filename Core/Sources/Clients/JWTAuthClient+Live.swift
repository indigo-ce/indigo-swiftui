import Dependencies
import Foundation
import HTTPRequestBuilder
import HTTPRequestClient
import JWTAuth
// MARK: - Live implementation

// The template advertises "JWTAuth with automatic token refresh," so this is
// the demonstration wiring. `JWTAuthClient` ships `testValue`/`previewValue`
// from the library; providing `liveValue` (the real network refresh) is the
// app's job — that's what this file does.
//
// Adjust `host`, the refresh endpoint path, and the request/response models to
// match your backend. The one part you should NOT change casually is the error
// mapping in `refresh` — see the note below.
extension JWTAuthClient: @retroactive DependencyKey {
  /// Base URL of your API. Replace with your real host (or read it from config).
  public static let host = "https://api.example.com"

  public static let liveValue = Self(
    baseURL: { host },
    refresh: { tokens in
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
  )
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
