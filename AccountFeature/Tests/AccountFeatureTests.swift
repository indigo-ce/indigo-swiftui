import ComposableArchitecture
import Core
import Dependencies
import Foundation
import HTTPRequestClient
import Testing

@testable import AccountFeature

@Suite
@MainActor
struct AccountFeatureTests {
  private let profile = AccountProfile(
    id: "1",
    email: "user@example.com",
    name: "Test User",
    emailVerified: true,
    createdAt: Date(timeIntervalSince1970: 0),
    updatedAt: Date(timeIntervalSince1970: 0)
  )

  private func makeStore(
    fetchProfile: @escaping @Sendable () async throws -> AccountProfile
  ) -> TestStoreOf<AccountFeature> {
    TestStore(initialState: AccountFeature.State()) {
      AccountFeature()
    } withDependencies: {
      $0.accountClient.fetchProfile = fetchProfile
    }
  }

  // MARK: Profile loading

  @Test
  func taskFetchesTheProfileAndShowsIt() async {
    let attempts = LockIsolated(0)
    let store = makeStore {
      attempts.withValue { $0 += 1 }
      return profile
    }

    await store.send(.task) {
      $0.isLoading = true
    }
    await store.receive(.profileResponse(profile)) {
      $0.isLoading = false
      $0.profile = profile
    }
    #expect(attempts.value == 1)
  }

  /// A `.task` while a fetch is still in flight supersedes it: the stale
  /// fetch is cancelled (TCA drops its sends, so it can never land) and the
  /// fresh fetch resolves the loading flag — a cancelled request can never
  /// wedge the screen in its progress state.
  @Test
  func taskWhileAFetchIsInFlightSupersedesIt() async {
    let (fetchStarted, fetchStartedContinuation) =
      AsyncStream<CheckedContinuation<AccountProfile, Never>>.makeStream()
    let attempts = LockIsolated(0)
    let store = makeStore {
      let attempt = attempts.withValue {
        $0 += 1
        return $0
      }
      if attempt == 1 {
        return await withCheckedContinuation { continuation in
          fetchStartedContinuation.yield(continuation)
        }
      }
      return profile
    }

    await store.send(.task) {
      $0.isLoading = true
    }
    var pendingContinuation: CheckedContinuation<AccountProfile, Never>?
    for await continuation in fetchStarted {
      pendingContinuation = continuation
      break
    }

    // The second `.task` starts while the first fetch is in flight. Loading
    // is already true, so no state changes.
    await store.send(.task)
    await store.receive(.profileResponse(profile)) {
      $0.isLoading = false
      $0.profile = profile
    }

    // Resuming the superseded fetch changes nothing observable: its sends
    // are dropped with the cancelled effect.
    pendingContinuation?.resume(returning: profile)
    await store.finish()
    #expect(attempts.value == 2)
  }

  @Test
  func unauthorizedFetchSurfacesTheServerMessageWithoutSideEffects() async {
    let store = makeStore {
      throw HTTPRequestClient.Error.badResponse(UUID(), 401, #"{"error":"Token expired"}"#)
    }

    await store.send(.task) {
      $0.isLoading = true
    }
    // A 401 keeps its message and nothing more: no sign-out, no session
    // touch — the feature has no session dependency to reach.
    await store.receive(.failed("Token expired")) {
      $0.isLoading = false
      $0.errorMessage = "Token expired"
    }
    #expect(store.state.profile == nil)
  }

  @Test
  func transportFailureFallsBackToTheGenericMessage() async {
    let store = makeStore {
      throw URLError(.timedOut)
    }

    await store.send(.task) {
      $0.isLoading = true
    }
    await store.receive(.failed("Something went wrong. Please try again.")) {
      $0.isLoading = false
      $0.errorMessage = "Something went wrong. Please try again."
    }
  }

  @Test
  func retryAfterAFailedFetchFetchesAgain() async {
    let attempts = LockIsolated(0)
    let store = makeStore {
      let attempt = attempts.withValue {
        $0 += 1
        return $0
      }
      if attempt == 1 {
        throw URLError(.timedOut)
      }
      return profile
    }

    await store.send(.task) {
      $0.isLoading = true
    }
    await store.receive(.failed("Something went wrong. Please try again.")) {
      $0.isLoading = false
      $0.errorMessage = "Something went wrong. Please try again."
    }

    await store.send(.retryButtonTapped)
    await store.receive(.task) {
      $0.isLoading = true
      $0.errorMessage = nil
    }
    await store.receive(.profileResponse(profile)) {
      $0.isLoading = false
      $0.profile = profile
    }
    #expect(attempts.value == 2)
  }

  @Test
  func failedRefetchSurfacesTheServerMessageAndKeepsTheProfile() async {
    let attempts = LockIsolated(0)
    let store = makeStore {
      let attempt = attempts.withValue {
        $0 += 1
        return $0
      }
      if attempt == 1 {
        return profile
      }
      throw HTTPRequestClient.Error.badResponse(UUID(), 401, #"{"error":"Token expired"}"#)
    }

    await store.send(.task) {
      $0.isLoading = true
    }
    await store.receive(.profileResponse(profile)) {
      $0.isLoading = false
      $0.profile = profile
    }

    // A failed refetch keeps the profile on screen and adds the server's
    // message instead of blanking the view.
    await store.send(.retryButtonTapped)
    await store.receive(.task) {
      $0.isLoading = true
    }
    await store.receive(.failed("Token expired")) {
      $0.isLoading = false
      $0.errorMessage = "Token expired"
    }
    #expect(store.state.profile == profile)
  }

  // MARK: Sign-out

  @Test
  func confirmingSignOutEmitsOnlyTheDelegateAction() async {
    let store = makeStore { profile }

    await store.send(.signOutButtonTapped) {
      $0.confirmationDialog = .signOut
    }
    await store.send(.confirmationDialog(.presented(.confirmSignOutButtonTapped))) {
      $0.confirmationDialog = nil
    }
    // The feature emits only the delegate action and runs no effect of its
    // own: the revoking sign-out stays with the presenter.
    await store.receive(.delegate(.signOutConfirmed))
  }
}
