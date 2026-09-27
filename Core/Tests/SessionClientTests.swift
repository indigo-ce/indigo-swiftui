import Dependencies
import Foundation
import JWTAuth
import Sharing
import SQLiteData
import Testing

@testable import Core

// Intercepts the revoke request at the transport layer so the tests below
// drive the real `SessionClient.liveValue.signOut` closure end to end.
// `HTTPRequestClient.send` is a `let` endpoint with an internal initializer,
// so the client itself cannot be stubbed per endpoint — scoping a
// `URLProtocol` to the API host is the seam that remains. Unlike the refresh
// stub in `JWTAuthClientLiveTests.swift`, this one also records each
// request's path and body (read from `httpBodyStream`, which is where
// URLSession hands the body to a `URLProtocol`).
private final class RevokeStubProtocol: URLProtocol {
  struct Stub: Sendable {
    var statusCode: Int
    var body: Data
    var transportError: (any Error)?
  }

  struct Recorded: Equatable, Sendable {
    var path: String
    var body: Data
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
      Recorded(path: request.url?.path ?? "", body: Self.body(of: request))
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
  private func revokeBody(status: Int, body: Data, transportError: (any Error)? = nil) {
    RevokeStubProtocol.stub = RevokeStubProtocol.Stub(
      statusCode: status, body: body, transportError: transportError
    )
    RevokeStubProtocol.requests = []
  }

  private func stubbedSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RevokeStubProtocol.self]
    return URLSession(configuration: configuration)
  }

  /// Seeds the session when asked, drives the real
  /// `SessionClient.liveValue.signOut`, and returns the keychain deletions it
  /// performed.
  private func signOut(
    seedTokens: Bool = true,
    keychainDelete: (@Sendable (KeychainClient.Keys) async throws -> Void)? = nil
  ) async throws -> [KeychainClient.Keys] {
    let deletes = LockIsolated<[KeychainClient.Keys]>([])
    try await withDependencies {
      // The live pipeline is the subject under test; only the transport and
      // the keychain are stubbed.
      $0.httpRequestClient = .liveValue
      $0.jwtAuthClient = .liveValue
      $0.authTokensClient = .liveValue
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

  @Test func signOutRevokesTheRefreshTokenThenDestroysTheSession() async throws {
    let deletes = try await signOut()
    let requests = RevokeStubProtocol.requests

    #expect(requests.count == 1)
    #expect(requests.first?.path == "/api/v1/auth/revoke-access")
    let body = String(data: requests.first?.body ?? Data(), encoding: .utf8)
    #expect(body?.contains(#""refreshToken":"r""#) == true)

    #expect(deletes == [.accessToken, .refreshToken])
    @Shared(.authSession) var session: AuthSession?
    #expect(session == nil)
  }

  @Test func revoke500StillDestroysTheSessionWithoutThrowing() async throws {
    revokeBody(
      status: 500,
      body: Data("boom".utf8)
    )
    let deletes = try await signOut()

    #expect(RevokeStubProtocol.requests.count == 1)
    #expect(deletes == [.accessToken, .refreshToken])
    @Shared(.authSession) var session: AuthSession?
    #expect(session == nil)
  }

  @Test func revokeTransportFailureStillDestroysTheSessionWithoutThrowing() async throws {
    revokeBody(status: 200, body: Data(), transportError: URLError(.notConnectedToInternet))
    let deletes = try await signOut()

    #expect(RevokeStubProtocol.requests.isEmpty)
    #expect(deletes == [.accessToken, .refreshToken])
    @Shared(.authSession) var session: AuthSession?
    #expect(session == nil)
  }

  @Test func signOutWithoutSessionSkipsTheRevokeAndStillDestroys() async throws {
    let deletes = try await signOut(seedTokens: false)

    #expect(RevokeStubProtocol.requests.isEmpty)
    #expect(deletes == [.accessToken, .refreshToken])
  }

  @Test func destroyFailureRethrows() async throws {
    // Seed with a succeeding delete first: the library's `save` deletes the
    // old material before writing, so the throwing delete must only take
    // effect for the sign-out itself.
    try await withDependencies {
      $0.httpRequestClient = .liveValue
      $0.jwtAuthClient = .liveValue
      $0.authTokensClient = .liveValue
      $0.networkSession = stubbedSession()
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
        $0.authTokensClient = .liveValue
        $0.networkSession = stubbedSession()
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
}
