import ComposableArchitecture
import Foundation
import JWTAuth
import Testing

@testable import RootFeature

@Suite
@MainActor
struct RootFeatureTests {
  // "stale" is not a decodable JWT, so `AuthTokens.toSession()` reports
  // `.expired`, which is what drives the refresh — no signed fixture token is
  // needed. `authTokensClient` stays live so the real persistence path runs
  // against the stub keychain.
  private func makeStore(
    refresh: @escaping @Sendable (AuthTokens) async throws -> AuthTokens
  ) -> TestStoreOf<RootFeature> {
    let store = TestStore(initialState: RootFeature.State()) {
      RootFeature()
    } withDependencies: {
      $0.keychainClient.load = { _ in "stale" }
      $0.keychainClient.save = { _, _ in }
      $0.keychainClient.delete = { _ in }
      $0.authTokensClient = .liveValue
      $0.jwtAuthClient.refresh = refresh
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    return store
  }

  @Test
  func taskRefreshesExpiredTokens() async {
    let store = makeStore { _ in AuthTokens(access: "fresh", refresh: "fresh") }

    await store.send(.task)
    await store.receive(\.sessionLoaded)

    await store.finish()

    // `.sessionLoaded` no longer implies the refresh has run: the launch gate
    // waits on the keychain restore only, so post-refresh assertions belong
    // after `finish()`.
    #expect(store.state.authSession?.tokens?.access == "fresh")
    #expect(store.state.isAuthenticated)
    #expect(store.state.isSessionLoaded)
  }

  @Test
  func taskRejectedRefreshDestroysCredentials() async {
    let store = makeStore { _ in throw AuthTokens.Error.refreshRejected }

    await store.send(.task)
    await store.receive(\.sessionLoaded)

    await store.finish()

    #expect(store.state.authSession == nil)
    #expect(!store.state.isAuthenticated)
    #expect(store.state.isSessionLoaded)
  }

  @Test
  func taskTransientRefreshFailurePreservesTokens() async {
    let store = makeStore { _ in throw URLError(.timedOut) }

    await store.send(.task)
    await store.receive(\.sessionLoaded)

    await store.finish()

    #expect(store.state.authSession?.tokens?.access == "stale")
    // The transient-failure case pins the `.expired` rule: a merely stale
    // access token still counts as signed in.
    #expect(store.state.isAuthenticated)
    #expect(store.state.isSessionLoaded)
  }

  @Test
  func sessionLoadedDoesNotWaitForRefresh() async {
    // The refresh suspends on a continuation this test owns, proving the
    // launch gate is lifted while the network refresh is still in flight.
    let (refreshStarted, refreshStartedContinuation) =
      AsyncStream<CheckedContinuation<Void, Never>>.makeStream()

    let store = makeStore { _ in
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        refreshStartedContinuation.yield(continuation)
      }
      return AuthTokens(access: "fresh", refresh: "fresh")
    }

    await store.send(.task)
    await store.receive(\.sessionLoaded)

    #expect(store.state.isSessionLoaded)
    // Still `.expired(stale)` while the refresh is suspended — signed in.
    #expect(store.state.isAuthenticated)

    var refreshContinuation: CheckedContinuation<Void, Never>?
    for await continuation in refreshStarted {
      refreshContinuation = continuation
      break
    }
    refreshContinuation?.resume()

    await store.finish()
  }
}
