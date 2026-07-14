import Dependencies
import Foundation
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

      var request = URLRequest(url: URL(string: "\(host)/auth/refresh")!)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONEncoder.api.encode(
        RefreshTokenRequest(refreshToken: tokens.refresh)
      )

      do {
        let response: SuccessResponse<TokenResponse> = try await httpClient.send(
          request,
          decoder: .api
        )
        return AuthTokens(
          access: response.value.accessToken,
          refresh: response.value.refreshToken
        )
      } catch let error as HTTPRequestClient.Error {
        // THE CONTRACT: only a definitive server rejection destroys the
        // session. A 401 from /auth/refresh means the refresh token is no
        // longer valid — map it to `refreshRejected` so the library wipes the
        // stored credentials and forces re-authentication.
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

// MARK: - Refresh endpoint models

// Template request/response shapes for the token-refresh call. Rename fields to
// match your API; `JSONCoders.api` handles snake_case ⇄ camelCase by default.
private struct RefreshTokenRequest: Encodable {
  let refreshToken: String
}

private struct TokenResponse: Decodable {
  let accessToken: String
  let refreshToken: String
}
