import Dependencies
import Foundation
import HTTPRequestClient
import JWTAuth
import Testing

@testable import Core

// Intercepts the refresh request at the transport layer so the tests below
// drive the real `JWTAuthClient.liveValue.refresh` closure end to end.
// `HTTPRequestClient.send` is a `let` endpoint with an internal initializer,
// so the client itself cannot be stubbed per endpoint — scoping a
// `URLProtocol` to the refresh host is the seam that remains.
private final class RefreshStubProtocol: URLProtocol {
  struct Stub: Sendable {
    var statusCode: Int
    var body: Data
  }

  nonisolated(unsafe) static var stub = Stub(statusCode: 500, body: Data())
  static let requestCount = LockIsolated(0)

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == URL(string: JWTAuthClient.host)?.host
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let stub = Self.stub
    Self.requestCount.withValue { $0 += 1 }
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

@Suite(.serialized) struct JWTAuthClientLiveTests {
  private func refresh(tokens: AuthTokens, statusCode: Int, body: Data = Data()) async throws
    -> AuthTokens
  {
    RefreshStubProtocol.stub = RefreshStubProtocol.Stub(statusCode: statusCode, body: body)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RefreshStubProtocol.self]
    return try await withDependencies {
      // The live pipeline is the subject under test; only the transport is stubbed.
      $0.httpRequestClient = .liveValue
      $0.networkSession = URLSession(configuration: configuration)
    } operation: {
      try await JWTAuthClient.liveValue.refresh(tokens)
    }
  }

  @Test func refreshMaps401ToRefreshRejected() async {
    let tokens = AuthTokens(access: "expired-access", refresh: "expired-refresh")
    do {
      _ = try await refresh(tokens: tokens, statusCode: 401)
      Issue.record("Expected AuthTokens.Error.refreshRejected, but refresh succeeded")
    } catch let error as AuthTokens.Error {
      guard case .refreshRejected = error else {
        Issue.record("Expected AuthTokens.Error.refreshRejected, got \(error)")
        return
      }
    } catch {
      Issue.record("Expected AuthTokens.Error.refreshRejected, got \(error)")
    }
  }

  @Test func refreshRethrowsNon401Failures() async {
    let tokens = AuthTokens(access: "expired-access", refresh: "expired-refresh")
    do {
      _ = try await refresh(tokens: tokens, statusCode: 500, body: Data("boom".utf8))
      Issue.record("Expected the 500 failure to propagate, but refresh succeeded")
    } catch let error as HTTPRequestClient.Error {
      guard case .badResponse(_, 500, "boom") = error else {
        Issue.record("Expected the original 500 badResponse, got \(error)")
        return
      }
    } catch {
      Issue.record("Expected the original 500 badResponse, got \(error)")
    }
  }

  /// Two callers refreshing from the same source token — for example a
  /// profile fetch superseding one that is already refreshing — must share
  /// the in-flight request: the backend rotates refresh tokens with no grace
  /// window, so a second single-use request would be definitively rejected
  /// with 401 and wipe a valid session.
  @Test func concurrentRefreshesOfTheSameTokenShareOneFlight() async throws {
    let coordinator = RefreshSingleFlight()
    let flights = LockIsolated(0)
    let (release, releaseContinuation) = AsyncStream<Void>.makeStream()
    let perform: @Sendable (AuthTokens) async throws -> AuthTokens = { _ in
      flights.withValue { $0 += 1 }
      for await _ in release { break }
      return AuthTokens(access: "new-access", refresh: "new-refresh")
    }

    let tokens = AuthTokens(access: "expired-access", refresh: "shared-refresh")
    async let first = coordinator.refresh(tokens, perform: perform)
    while flights.value == 0 { await Task.yield() }
    async let second = coordinator.refresh(tokens, perform: perform)
    // Give the second caller time to join the parked flight before it ends.
    try await Task.sleep(for: .milliseconds(50))
    releaseContinuation.finish()

    let (a, b) = try await (first, second)
    #expect(flights.value == 1)
    #expect(a == b)
  }

  /// A completed flight is never shared: success replaced the tokens callers
  /// hold, and a transient failure must be retried with a fresh request.
  @Test func aCompletedFlightDoesNotShareWithLaterRefreshes() async throws {
    let tokens = AuthTokens(access: "expired-access", refresh: "retried-refresh")
    RefreshStubProtocol.requestCount.setValue(0)

    let first = try await refresh(
      tokens: tokens,
      statusCode: 200,
      body: Data(#"{"accessToken":"a1","refreshToken":"r1"}"#.utf8)
    )
    let second = try await refresh(
      tokens: tokens,
      statusCode: 200,
      body: Data(#"{"accessToken":"a2","refreshToken":"r2"}"#.utf8)
    )

    #expect(RefreshStubProtocol.requestCount.value == 2)
    #expect(first.access == "a1")
    #expect(second.access == "a2")
  }
}
