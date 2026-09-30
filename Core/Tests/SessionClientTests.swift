import Dependencies
import Foundation
import JWTAuth
import Sharing
import SQLiteData
import Testing

@testable import Core

// Intercepts the session requests (revoke, sign-in) at the transport layer
// so the tests below drive the real `SessionClient.liveValue` closures end to
// end. `HTTPRequestClient.send` is a `let` endpoint with an internal
// initializer, so the client itself cannot be stubbed per endpoint — scoping
// a `URLProtocol` to the API host is the seam that remains. Unlike the
// refresh stub in `JWTAuthClientLiveTests.swift`, this one also records each
// request's method, path, body (read from `httpBodyStream`, which is where
// URLSession hands the body to a `URLProtocol`), and `Authorization` header.
private final class AuthStubProtocol: URLProtocol {
  struct Stub: Sendable {
    var statusCode: Int
    var body: Data
    var transportError: (any Error)?
  }

  struct Recorded: Equatable, Sendable {
    var httpMethod: String
    var path: String
    var body: Data
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
        body: Self.body(of: request),
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

  private static func body(of request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 16 * 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
      let read = stream.read(buffer, maxLength: bufferSize)
      guard read > 0 else { break }
      data.append(buffer, count: read)
    }
    return data
  }
}

@Suite(.serialized) struct SessionClientTests {
  private static let successStub = AuthStubProtocol.Stub(
    statusCode: 200,
    body: Data(#"{"success":true}"#.utf8)
  )

  /// All four fields the backend sends, so decoding must tolerate the ignored
  /// `user` and `tokenType` keys.
  private static let signInSuccessStub = AuthStubProtocol.Stub(
    statusCode: 200,
    body: Data(
      #"{"user":{"id":"u1"},"accessToken":"access-1","refreshToken":"refresh-1","tokenType":"Bearer"}"#
        .utf8
    )
  )

  private func stubbedSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AuthStubProtocol.self]
    return URLSession(configuration: configuration)
  }

  /// Resets the stub to the given response and clears the recordings, seeds
  /// the session when asked, drives the real `SessionClient.liveValue.signOut`,
  /// and returns the keychain deletions it performed. Resetting on every call
  /// keeps the serialized suite order-independent.
  private func signOut(
    seedTokens: Bool = true,
    revokeStub: AuthStubProtocol.Stub = Self.successStub,
    keychainDelete: (@Sendable (KeychainClient.Keys) async throws -> Void)? = nil
  ) async throws -> [KeychainClient.Keys] {
    AuthStubProtocol.stub = revokeStub
    AuthStubProtocol.requests = []
    let deletes = LockIsolated<[KeychainClient.Keys]>([])
    try await withDependencies {
      // The live pipeline is the subject under test; only the transport and
      // the keychain are stubbed. `signOut` coordinates with token refresh
      // through the gate, so the gated credential client is the one installed.
      $0.httpRequestClient = .liveValue
      $0.jwtAuthClient = .liveValue
      $0.authTokensClient = .gated
      $0.authSessionGate = AuthSessionGate()
      $0.networkSession = stubbedSession()
      $0.keychainClient.save = { _, _ in }
      $0.keychainClient.load = { _ in nil }
      $0.keychainClient.delete = keychainDelete ?? { key in
        deletes.withValue { $0.append(key) }
      }
    } operation: {
      if seedTokens {
        try await AuthTokensClient.liveValue.save(AuthTokens(access: "a", refresh: "r"))
      }
      try await SessionClient.liveValue.signOut()
    }
    return deletes.value
  }

  /// Mirrors `signOut(...)` for sign-in: drives the real
  /// `SessionClient.liveValue.signIn` starting from no session, records the
  /// keychain saves it performs, and returns them so tests can assert that a
  /// failed exchange stores nothing. Resetting on every call keeps the
  /// serialized suite order-independent. Seeding, when asked, runs in its own
  /// dependency scope with throwaway keychain stubs so the seeded writes are
  /// not recorded as sign-in saves.
  private func signIn(
    signInStub: AuthStubProtocol.Stub = Self.signInSuccessStub,
    seedTokens: Bool = false,
    keychainSave: (@Sendable (String, KeychainClient.Keys) async throws -> Void)? = nil
  ) async throws -> [KeychainClient.Keys] {
    AuthStubProtocol.stub = signInStub
    AuthStubProtocol.requests = []
    // Explicitly clear the shared session — a prior test may have left one
    // published, and the failure tests below assert that nothing was stored.
    @Shared(.authSession) var session: AuthSession?
    $session.withLock { $0 = nil }
    if seedTokens {
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
        try await AuthTokensClient.liveValue.save(AuthTokens(access: "a-old", refresh: "r-old"))
      }
      AuthStubProtocol.requests = []
    }
    let saves = LockIsolated<[KeychainClient.Keys]>([])
    try await withDependencies {
      $0.httpRequestClient = .liveValue
      $0.jwtAuthClient = .liveValue
      $0.authTokensClient = .gated
      $0.authSessionGate = AuthSessionGate()
      $0.networkSession = stubbedSession()
      $0.keychainClient.save = keychainSave ?? { _, key in
        saves.withValue { $0.append(key) }
      }
      $0.keychainClient.load = { _ in nil }
      $0.keychainClient.delete = { _ in }
    } operation: {
      try await SessionClient.liveValue.signIn("user@example.com", "secret")
    }
    return saves.value
  }

  @Test func signInExchangesCredentialsAndStoresTheTokens() async throws {
    let saves = try await signIn()
    let requests = AuthStubProtocol.requests

    #expect(requests.count == 1)
    #expect(requests.first?.httpMethod == "POST")
    #expect(requests.first?.path == "/api/v1/auth/sign-in")
    #expect(
      requests.first?.authorizationHeader
        == "Basic dXNlckBleGFtcGxlLmNvbTpzZWNyZXQ="
    )
    #expect(requests.first?.body.isEmpty == true)

    #expect(saves == [.accessToken, .refreshToken])
    @Shared(.authSession) var session: AuthSession?
    #expect(session?.tokens == AuthTokens(access: "access-1", refresh: "refresh-1"))
  }

  /// Signing in over an existing session is an account switch: the displaced
  /// refresh token must be revoked before the save overwrites it, or it stays
  /// live on the server with no device copy left to revoke later.
  @Test func signInDisplacesAnExistingSessionAndRevokesItsRefreshToken() async throws {
    let saves = try await signIn(seedTokens: true)
    let requests = AuthStubProtocol.requests

    #expect(requests.count == 2)
    #expect(requests.first?.httpMethod == "POST")
    #expect(requests.first?.path == "/api/v1/auth/sign-in")
    #expect(
      requests.first?.authorizationHeader
        == "Basic dXNlckBleGFtcGxlLmNvbTpzZWNyZXQ="
    )
    #expect(requests.last?.path == "/api/v1/auth/revoke-access")
    let revoked = String(decoding: requests.last?.body ?? Data(), as: UTF8.self)
    #expect(revoked.contains(#""refreshToken":"r-old""#))

    #expect(saves == [.accessToken, .refreshToken])
    @Shared(.authSession) var session: AuthSession?
    #expect(session?.tokens == AuthTokens(access: "access-1", refresh: "refresh-1"))
  }

  @Test func signIn401ThrowsAndStoresNothing() async throws {
    do {
      _ = try await signIn(
        signInStub: AuthStubProtocol.Stub(
          statusCode: 401,
          body: Data(#"{"error":"Invalid email or password"}"#.utf8)
        )
      )
      Issue.record("Expected the 401 to throw, but signIn succeeded")
    } catch {
      #expect(APIErrorBody.from(error)?.error == "Invalid email or password")
    }
    #expect(AuthStubProtocol.requests.count == 1)
    @Shared(.authSession) var session: AuthSession?
    #expect(session == nil)
  }

  @Test func signInTransportFailureThrowsAndStoresNothing() async throws {
    do {
      _ = try await signIn(
        signInStub: AuthStubProtocol.Stub(
          statusCode: 200,
          body: Data(),
          transportError: URLError(.notConnectedToInternet)
        )
      )
      Issue.record("Expected the transport failure to throw, but signIn succeeded")
    } catch {}
    #expect(AuthStubProtocol.requests.isEmpty)
    @Shared(.authSession) var session: AuthSession?
    #expect(session == nil)
  }

  @Test func signInKeychainFailureRethrows() async throws {
    await #expect(throws: URLError(.badURL).self) {
      _ = try await signIn(
        keychainSave: { _, _ in throw URLError(.badURL) }
      )
    }
  }

  @Test func signOutRevokesTheRefreshTokenThenDestroysTheSession() async throws {
    let deletes = try await signOut()
    let requests = AuthStubProtocol.requests

    #expect(requests.count == 1)
    #expect(requests.first?.path == "/api/v1/auth/revoke-access")
    let body = String(data: requests.first?.body ?? Data(), encoding: .utf8)
    #expect(body?.contains(#""refreshToken":"r""#) == true)

    #expect(deletes == [.accessToken, .refreshToken])
    @Shared(.authSession) var session: AuthSession?
    #expect(session == nil)
  }

  @Test func revoke500StillDestroysTheSessionWithoutThrowing() async throws {
    let deletes = try await signOut(
      revokeStub: AuthStubProtocol.Stub(statusCode: 500, body: Data("boom".utf8))
    )

    #expect(AuthStubProtocol.requests.count == 1)
    #expect(deletes == [.accessToken, .refreshToken])
    @Shared(.authSession) var session: AuthSession?
    #expect(session == nil)
  }

  @Test func revokeTransportFailureStillDestroysTheSessionWithoutThrowing() async throws {
    let deletes = try await signOut(
      revokeStub: AuthStubProtocol.Stub(
        statusCode: 200,
        body: Data(),
        transportError: URLError(.notConnectedToInternet)
      )
    )

    #expect(AuthStubProtocol.requests.isEmpty)
    #expect(deletes == [.accessToken, .refreshToken])
    @Shared(.authSession) var session: AuthSession?
    #expect(session == nil)
  }

  @Test func signOutWithoutSessionSkipsTheRevokeAndStillDestroys() async throws {
    let deletes = try await signOut(seedTokens: false)

    #expect(AuthStubProtocol.requests.isEmpty)
    #expect(deletes == [.accessToken, .refreshToken])
  }

  @Test func destroyFailureRethrows() async throws {
    // Seed with a succeeding delete first: the library's `save` deletes the
    // old material before writing, so the throwing delete must only take
    // effect for the sign-out itself.
    try await withDependencies {
      $0.httpRequestClient = .liveValue
      $0.jwtAuthClient = .liveValue
      $0.authTokensClient = .gated
      $0.authSessionGate = AuthSessionGate()
      $0.networkSession = stubbedSession()
      AuthStubProtocol.stub = Self.successStub
      AuthStubProtocol.requests = []
      $0.keychainClient.save = { _, _ in }
      $0.keychainClient.load = { _ in nil }
      $0.keychainClient.delete = { _ in }
    } operation: {
      try await AuthTokensClient.liveValue.save(AuthTokens(access: "a", refresh: "r"))
    }

    do {
      try await withDependencies {
        $0.httpRequestClient = .liveValue
        $0.jwtAuthClient = .liveValue
        $0.authTokensClient = .gated
        $0.authSessionGate = AuthSessionGate()
        $0.networkSession = stubbedSession()
        AuthStubProtocol.stub = Self.successStub
        AuthStubProtocol.requests = []
        $0.keychainClient.save = { _, _ in }
        $0.keychainClient.load = { _ in nil }
        $0.keychainClient.delete = { _ in throw URLError(.badURL) }
      } operation: {
        try await SessionClient.liveValue.signOut()
      }
      Issue.record("Expected the destroy failure to propagate, but signOut succeeded")
    } catch {
      // Expected: the destroy failure is the one thing that throws.
    }
  }

  /// A refresh whose network call returned while sign-out was running hands
  /// its rotated pair to the library, which publishes it unconditionally. The
  /// gated credential client must veto that publish — its source refresh token
  /// no longer exists — and revoke the rotated refresh token it drops.
  @Test func signOutVetoesARefreshPublishThatCompletesAfterwards() async throws {
    try await withDependencies {
      $0.httpRequestClient = .liveValue
      $0.jwtAuthClient = .liveValue
      $0.authTokensClient = .gated
      $0.authSessionGate = AuthSessionGate()
      $0.networkSession = stubbedSession()
      AuthStubProtocol.stub = Self.successStub
      AuthStubProtocol.requests = []
      $0.keychainClient.save = { _, _ in }
      $0.keychainClient.load = { _ in nil }
      $0.keychainClient.delete = { _ in }
    } operation: {
      try await AuthTokensClient.liveValue.save(AuthTokens(access: "a", refresh: "r"))

      // As if the refresh had returned from the network: the publish the
      // library is about to perform is staged, then `signOut` runs to
      // completion, then the library's publish lands.
      @Dependency(\.authSessionGate) var gate
      await gate.stagePublish(newRefresh: "r2", sourceRefresh: "r")

      try await SessionClient.liveValue.signOut()

      @Dependency(\.authTokensClient) var authTokensClient
      try await authTokensClient.save(AuthTokens(access: "a2", refresh: "r2"))

      @Shared(.authSession) var session: AuthSession?
      #expect(session == nil)
      let revoked = AuthStubProtocol.requests.map { String(decoding: $0.body, as: UTF8.self) }
      #expect(revoked.count == 2)
      #expect(revoked.first?.contains(#""refreshToken":"r""#) == true)
      #expect(revoked.last?.contains(#""refreshToken":"r2""#) == true)
    }
  }
}
