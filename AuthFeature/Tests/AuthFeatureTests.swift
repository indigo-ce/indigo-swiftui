import ComposableArchitecture
import Core
import Foundation
import HTTPRequestClient
import Testing

@testable import AuthFeature

@Suite
@MainActor
struct AuthFeatureTests {
  private func makeStore(
    initialState: AuthFeature.State,
    signIn: @escaping @Sendable (String, String) async throws -> Void = { _, _ in },
    signUp: @escaping @Sendable (String, String, String) async throws -> Void = { _, _, _ in }
  ) -> TestStoreOf<AuthFeature> {
    TestStore(initialState: initialState) {
      AuthFeature()
    } withDependencies: {
      $0.sessionClient.signIn = signIn
      $0.sessionClient.signUp = signUp
    }
  }

  // MARK: Sign-in

  @Test
  func signInSubmitCallsClientWithEnteredCredentials() async {
    let expectedEmail = "user@example.com"
    let expectedPassword = "secret"
    let store = makeStore(
      initialState: AuthFeature.State(email: expectedEmail, password: expectedPassword),
      signIn: { email, password in
        // A mismatch throws, which fails the `.signInResponse` receive below.
        if email != expectedEmail || password != expectedPassword {
          throw HTTPRequestClient.Error.badResponse(UUID(), 500, #"{"error":"wrong"}"#)
        }
      }
    )

    await store.send(.submitButtonTapped) {
      $0.isLoading = true
    }
    await store.receive(\.signInResponse) {
      $0.isLoading = false
    }
    // The sign-in path touches no other state: the presenter reacts to the
    // session change, not to anything the feature published.
    #expect(store.state.errorMessage == nil)
    #expect(!store.state.signUpSuccess)
    #expect(store.state.mode == .signIn)
  }

  @Test
  func signInBadResponseSurfacesServerMessage() async {
    let store = makeStore(
      initialState: AuthFeature.State(email: "user@example.com", password: "secret"),
      signIn: { _, _ in
        throw HTTPRequestClient.Error.badResponse(
          UUID(), 401, #"{"error":"Invalid email or password"}"#
        )
      }
    )

    await store.send(.submitButtonTapped) {
      $0.isLoading = true
    }
    await store.receive(.failed("Invalid email or password")) {
      $0.isLoading = false
      $0.errorMessage = "Invalid email or password"
    }
  }

  @Test
  func signInTransportFailureSurfacesGenericMessage() async {
    let store = makeStore(
      initialState: AuthFeature.State(email: "user@example.com", password: "secret"),
      signIn: { _, _ in throw URLError(.timedOut) }
    )

    await store.send(.submitButtonTapped) {
      $0.isLoading = true
    }
    await store.receive(.failed("Something went wrong. Please try again.")) {
      $0.isLoading = false
      $0.errorMessage = "Something went wrong. Please try again."
    }
  }

  @Test
  func errorMessageFallsBackOnUndecodableBody() {
    let error = HTTPRequestClient.Error.badResponse(UUID(), 500, "boom")
    #expect(AuthFeature.errorMessage(from: error) == "Something went wrong. Please try again.")
    #expect(AuthFeature.errorMessage(from: URLError(.timedOut)) == "Something went wrong. Please try again.")
  }

  // MARK: Sign-up

  @Test
  func signUpSubmitCallsClientAndLandsInSignIn() async {
    let expectedName = "Kai"
    let expectedEmail = "user@example.com"
    let expectedPassword = "secret"
    let store = makeStore(
      initialState: AuthFeature.State(
        mode: .signUp, name: expectedName, email: expectedEmail, password: expectedPassword
      ),
      signUp: { name, email, password in
        // A mismatch throws, which fails the `.signUpResponse` receive below.
        if name != expectedName || email != expectedEmail || password != expectedPassword {
          throw HTTPRequestClient.Error.badResponse(UUID(), 500, #"{"error":"wrong"}"#)
        }
      }
    )

    await store.send(.submitButtonTapped) {
      $0.isLoading = true
    }
    await store.receive(\.signUpResponse) {
      $0.isLoading = false
      $0.signUpSuccess = true
      $0.mode = .signIn
      $0.password = ""
    }
    // The email carries over so the user only types their password again.
    #expect(store.state.email == expectedEmail)
  }

  // MARK: Submission gating

  @Test
  func submitWhileLoadingSendsNoSecondRequest() async {
    var gateContinuation: CheckedContinuation<Void, Never>?
    let store = makeStore(
      initialState: AuthFeature.State(email: "user@example.com", password: "secret"),
      signIn: { _, _ in
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
          gateContinuation = continuation
        }
      }
    )

    await store.send(.submitButtonTapped) {
      $0.isLoading = true
    }
    // Still loading: the second tap is a no-op — no state change, no effect.
    await store.send(.submitButtonTapped)

    gateContinuation?.resume()
    await store.receive(\.signInResponse) {
      $0.isLoading = false
    }
  }

  @Test
  func signInSubmitWithEmptyFieldSendsNoRequest() async {
    var requested = false
    let store = makeStore(
      initialState: AuthFeature.State(email: "user@example.com"),
      signIn: { _, _ in
        requested = true
      }
    )

    // The password is missing: a no-op — no state change, no effect.
    await store.send(.submitButtonTapped)
    #expect(!requested)
    #expect(!store.state.isLoading)
  }

  @Test
  func signUpSubmitWithEmptyFieldSendsNoRequest() async {
    var requested = false
    let store = makeStore(
      initialState: AuthFeature.State(mode: .signUp, email: "user@example.com"),
      signUp: { _, _, _ in
        requested = true
      }
    )

    // The name and password are missing: a no-op — no state change, no effect.
    await store.send(.submitButtonTapped)
    #expect(!requested)
    #expect(!store.state.isLoading)
  }

  // MARK: Mode switching

  @Test
  func switchingModeClearsErrorAndConfirmation() async {
    var initialState = AuthFeature.State(email: "user@example.com")
    initialState.errorMessage = "Invalid email or password"
    initialState.signUpSuccess = true

    let store = TestStore(initialState: initialState) {
      AuthFeature()
    }

    await store.send(.binding(.set(\.mode, .signUp))) {
      $0.mode = .signUp
      $0.errorMessage = nil
      $0.signUpSuccess = false
    }
  }
}
