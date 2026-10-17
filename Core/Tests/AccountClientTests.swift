import Dependencies
import Foundation
import HTTPRequestClient
import JWTAuth
import Sharing
import SQLiteData
import Testing

@testable import Core

// Intercepts profile requests at the transport layer so the tests below drive
// the real `AccountClient.liveValue.fetchProfile` closure end to end.
// `HTTPRequestClient.send` is a `let` endpoint with an internal initializer,
// so the client itself cannot be stubbed per endpoint — scoping a
// `URLProtocol` to the API host is the seam that remains. This records each
// request's method, path, and `Authorization` header.
private final class ProfileStubProtocol: URLProtocol {
  struct Stub: Sendable {
    var statusCode: Int
    var body: Data
    var transportError: (any Error)?
  }

  struct Recorded: Equatable, Sendable {
    var httpMethod: String
    var path: String
    var authorizationHeader: String?
  }

  nonisolated(unsafe) static var stub = Stub(statusCode: 200, body: Data())
  nonisolated(unsafe) static var requests: [Recorded] = []

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == URL(string: JWTAuthClient.host)?.host
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    if let transportError = Self.stub.transportError {
      client?.urlProtocol(self, didFailWithError: transportError)
      return
    }
    Self.requests.append(
      Recorded(
        httpMethod: request.httpMethod ?? "GET",
        path: request.url?.path ?? "",
        authorizationHeader: request.allHTTPHeaderFields?["Authorization"]
      )
    )
    let stub = Self.stub
    guard let url = request.url,
      let response = HTTPURLResponse(
        url: url,
        statusCode: stub.statusCode,
        httpVersion: nil,
        headerFields: nil
      )
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: stub.body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Suite(.serialized) struct AccountClientTests {
  /// The full body the backend answers `GET /api/v1/account/profile` with:
  /// nullable `image` as JSON `null`, and ISO-8601 dates with fractional
  /// seconds.
  private static let profileBody = Data(
    #"{"id":"user-1","email":"user@example.com","name":"Test User","image":null,"emailVerified":true,"createdAt":"2024-01-15T10:30:00.123Z","updatedAt":"2025-06-01T08:00:00.456Z"}"#
      .utf8
  )

  private static let unauthorizedBody = Data(
    #"{"error":"You are not authorized to access this resource","code":"UNAUTHORIZED"}"#
      .utf8
  )

  /// A syntactically valid JWT with a future `exp`, so the library's
  /// `refreshExpiredTokens` treats the seeded session as unexpired and no
  /// refresh fires. The signature is arbitrary: JWTDecode only decodes
  /// claims, it never verifies signatures.
  private static func makeAccessToken(expiresIn: TimeInterval = 60 * 60) -> String {
    func base64URL(_ string: String) -> String {
      Data(string.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    }
    let header = #"{"alg":"HS256","typ":"JWT"}"#
    let payload =
      #"{"sub":"user-1","email":"user@example.com","exp":\#((Date().timeIntervalSince1970 + expiresIn).description)}"#
    return [header, payload, "signature"]
      .map(base64URL)
      .joined(separator: ".")
  }

  private func stubbedSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ProfileStubProtocol.self]
    return URLSession(configuration: configuration)
  }

  /// Resets the stub, clears the shared session, seeds an unexpired one with
  /// `accessToken` (in its own dependency scope with throwaway stubs, so the
  /// seeded write is not recorded as an interaction of the operation under
  /// test), then drives `operation` against the real live dependencies with
  /// the refresh closure overridden to fail loudly: an unexpired token must
  /// never trigger a refresh. Resetting on every call keeps the serialized
  /// suite order-independent.
  private func withSeededSession(
    accessToken: String,
    stub: ProfileStubProtocol.Stub,
    operation: () async throws -> Void
  ) async throws {
    ProfileStubProtocol.stub = stub
    ProfileStubProtocol.requests = []
    @Shared(.authSession) var session: AuthSession?
    $session.withLock { $0 = nil }

    try await withDependencies {
      $0.httpRequestClient = .liveValue
      $0.jwtAuthClient = .liveValue
      $0.authTokensClient = .gated
      $0.authSessionGate = AuthSessionGate()
      $0.networkSession = stubbedSession()
      $0.keychainClient.save = { _, _ in }
      $0.keychainClient.load = { _ in nil }
      $0.keychainClient.delete = { _ in }
    } operation: {
      try await AuthTokensClient.liveValue.save(
        AuthTokens(access: accessToken, refresh: "refresh-token")
      )
    }

    ProfileStubProtocol.requests = []
    try await withDependencies {
      $0.httpRequestClient = .liveValue
      $0.jwtAuthClient = .liveValue
      $0.authTokensClient = .gated
      $0.authSessionGate = AuthSessionGate()
      $0.networkSession = stubbedSession()
      $0.keychainClient.save = { _, _ in }
      $0.keychainClient.load = { _ in nil }
      $0.keychainClient.delete = { _ in }
      $0.apiClient.refresh = { _ in
        Issue.record("An unexpired access token must not trigger a refresh")
        throw URLError(.badServerResponse)
      }
    } operation: {
      try await operation()
    }
  }

  @Test func fetchProfileSendsTheAuthenticatedRequestAndDecodesTheBody() async throws {
    let accessToken = Self.makeAccessToken()
    try await withSeededSession(
      accessToken: accessToken,
      stub: ProfileStubProtocol.Stub(statusCode: 200, body: Self.profileBody)
    ) {
      let profile = try await AccountClient.liveValue.fetchProfile()

      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      #expect(
        profile == AccountProfile(
          id: "user-1",
          email: "user@example.com",
          name: "Test User",
          image: nil,
          emailVerified: true,
          createdAt: try #require(formatter.date(from: "2024-01-15T10:30:00.123Z")),
          updatedAt: try #require(formatter.date(from: "2025-06-01T08:00:00.456Z"))
        )
      )
    }
    let requests = ProfileStubProtocol.requests

    #expect(requests.count == 1)
    #expect(requests.first?.httpMethod == "GET")
    #expect(requests.first?.path == "/api/v1/account/profile")
    #expect(requests.first?.authorizationHeader == "Bearer \(accessToken)")
  }

  @Test func fetchProfile401RethrowsAndLeavesTheSessionUntouched() async throws {
    let accessToken = Self.makeAccessToken()
    do {
      try await withSeededSession(
        accessToken: accessToken,
        stub: ProfileStubProtocol.Stub(statusCode: 401, body: Self.unauthorizedBody)
      ) {
        _ = try await AccountClient.liveValue.fetchProfile()
      }
      Issue.record("Expected the 401 to throw, but fetchProfile succeeded")
    } catch let error as HTTPRequestClient.Error {
      guard case .badResponse(_, 401, _) = error else {
        Issue.record("Expected .badResponse with status 401, got \(error)")
        return
      }
    }

    // One request, no refresh in front of it, and the session exactly as
    // seeded: a 401 from a business endpoint rethrows untouched and mutates
    // no stored credential.
    #expect(ProfileStubProtocol.requests.count == 1)
    @Shared(.authSession) var session: AuthSession?
    #expect(session?.tokens == AuthTokens(access: accessToken, refresh: "refresh-token"))
  }
}
