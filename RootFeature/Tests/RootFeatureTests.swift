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

    #expect(store.state.authSession?.tokens?.access == "fresh")
    #expect(store.state.isSessionLoaded)

    await store.finish()
  }

  @Test
  func taskRejectedRefreshDestroysCredentials() async {
    let store = makeStore { _ in throw AuthTokens.Error.refreshRejected }

    await store.send(.task)
    await store.receive(\.sessionLoaded)

    #expect(store.state.authSession == nil)
    #expect(store.state.isSessionLoaded)

    await store.finish()
  }

  @Test
  func taskTransientRefreshFailurePreservesTokens() async {
    let store = makeStore { _ in throw URLError(.timedOut) }

    await store.send(.task)
    await store.receive(\.sessionLoaded)

    #expect(store.state.authSession?.tokens?.access == "stale")
    #expect(store.state.isSessionLoaded)

    await store.finish()
  }
}
