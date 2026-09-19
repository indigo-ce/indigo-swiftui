import Foundation
import HTTPRequestClient

/// The shape a failed API request can carry: a human-readable message, plus a stable code on the
/// endpoints that define one.
///
/// `error` is a human-readable server message, suitable for display or logging. `code` is an
/// optional stable machine-readable identifier that only some endpoints send — branch on it when
/// it is present, and fall back to the server's prose when it is `nil`. Neither field is promised
/// to be localized; a cloned project's backend decides that.
public struct APIErrorBody: Decodable, Sendable {
  public let error: String
  public let code: String?

  public init(error: String, code: String? = nil) {
    self.error = error
    self.code = code
  }
}

extension APIErrorBody {
  /// Recovers the body of a non-2xx response. `HTTPRequestClient` reports those as `.badResponse`
  /// carrying the raw body string, so decoding it here is the only way to see what the server
  /// actually said — otherwise every 4xx collapses into the same opaque failure.
  ///
  /// Returns `nil` for errors that are not `.badResponse` and for bodies that fail to decode.
  public static func from(_ error: any Error) -> APIErrorBody? {
    guard
      case HTTPRequestClient.Error.badResponse(_, _, let body) = error,
      let data = body.data(using: .utf8)
    else { return nil }
    return try? JSONDecoder().decode(APIErrorBody.self, from: data)
  }
}
