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
  func taskFetchesTheProfileOnceAndShowsIt() async {
    // The fetch parks on a continuation so the test can send a second
    // `.task` while the first request is genuinely in flight.
    let (fetchStarted, fetchStartedContinuation) =
      AsyncStream<CheckedContinuation<AccountProfile, Never>>.makeStream()
    let attempts = LockIsolated(0)
    let store = makeStore {
      attempts.withValue { $0 += 1 }
      return await withCheckedContinuation { continuation in
        fetchStartedContinuation.yield(continuation)
      }
    }

    await store.send(.task) {
      $0.isLoading = true
    }

    var pendingContinuation: CheckedContinuation<AccountProfile, Never>?
    for await continuation in fetchStarted {
      pendingContinuation = continuation
      break
    }

    // A second `.task` while the first fetch is in flight is ignored.
    await store.send(.task)

    pendingContinuation?.resume(returning: profile)
    await store.receive(.profileResponse(profile)) {
      $0.isLoading = false
      $0.profile = profile
    }
    #expect(attempts.value == 1)
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
