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
    signUp: @escaping @Sendable (String, String, String) async throws -> Void = { _, _, _ in },
    requestPasswordReset: @escaping @Sendable (String) async throws -> Void = { _ in }
  ) -> TestStoreOf<AuthFeature> {
    TestStore(initialState: initialState) {
      AuthFeature()
    } withDependencies: {
      $0.sessionClient.signIn = signIn
      $0.sessionClient.signUp = signUp
      $0.sessionClient.requestPasswordReset = requestPasswordReset
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
    // A stream gate, not an optional continuation: a yield before the effect
    // starts consuming is buffered, so the release signal cannot be lost when
    // the resume happens before the effect reaches its suspension point.
    let (gate, gateContinuation) = AsyncStream<Void>.makeStream()
    let store = makeStore(
      initialState: AuthFeature.State(email: "user@example.com", password: "secret"),
      signIn: { _, _ in
        for await _ in gate { break }
      }
    )

    await store.send(.submitButtonTapped) {
      $0.isLoading = true
    }
    // Still loading: the second tap is a no-op — no state change, no effect.
    await store.send(.submitButtonTapped)

    gateContinuation.yield()
    await store.receive(\.signInResponse) {
      $0.isLoading = false
    }
  }

  @Test
  func failedThenSuccessfulSignInRetryClearsError() async {
    // The first attempt signs in with the wrong password and fails; the user
    // corrects the field and retries successfully. Only the second call sees
    // "secret", so a mismatch throws and fails the retry receive below.
    let store = makeStore(
      initialState: AuthFeature.State(email: "user@example.com", password: "wrong"),
      signIn: { _, password in
        if password != "secret" {
          throw HTTPRequestClient.Error.badResponse(
            UUID(), 401, #"{"error":"Invalid email or password"}"#
          )
        }
      }
    )

    await store.send(.submitButtonTapped) {
      $0.isLoading = true
      $0.errorMessage = nil
    }
    await store.receive(.failed("Invalid email or password")) {
      $0.isLoading = false
      $0.errorMessage = "Invalid email or password"
    }

    await store.send(.binding(.set(\.password, "secret"))) {
      $0.password = "secret"
    }
    await store.send(.submitButtonTapped) {
      $0.isLoading = true
      $0.errorMessage = nil
    }
    await store.receive(\.signInResponse) {
      $0.isLoading = false
    }
    #expect(store.state.errorMessage == nil)
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

  // MARK: Forgot password

  @Test
  func forgotPasswordButtonPresentsSheetSeededWithSignInEmail() async {
    let expectedEmail = "user@example.com"
    let store = makeStore(initialState: AuthFeature.State(email: expectedEmail))

    await store.send(.forgotPasswordButtonTapped) {
      $0.forgotPassword = ForgotPasswordFeature.State(email: expectedEmail)
    }
  }

  @Test
  func forgotPasswordButtonIsNoOpWhileLoading() async {
    // A stream gate, not an optional continuation: a yield before the effect
    // starts consuming is buffered, so the release signal cannot be lost.
    let (gate, gateContinuation) = AsyncStream<Void>.makeStream()
    let store = makeStore(
      initialState: AuthFeature.State(email: "user@example.com", password: "secret"),
      signIn: { _, _ in
        for await _ in gate { break }
      }
    )

    await store.send(.submitButtonTapped) {
      $0.isLoading = true
    }
    // Mid-request: the button is a no-op — no sheet, no state change.
    await store.send(.forgotPasswordButtonTapped)
    #expect(store.state.forgotPassword == nil)

    gateContinuation.yield()
    await store.receive(\.signInResponse) {
      $0.isLoading = false
    }
  }

  @Test
  func forgotPasswordButtonIsNoOpInSignUpMode() async {
    let store = makeStore(
      initialState: AuthFeature.State(mode: .signUp, email: "user@example.com")
    )

    await store.send(.forgotPasswordButtonTapped)
    #expect(store.state.forgotPassword == nil)
  }

  @Test
  func forgotPasswordSubmitCallsClientWithEmailAndSetsEmailSent() async {
    let expectedEmail = "user@example.com"
    let store = makeStore(
      initialState: AuthFeature.State(email: expectedEmail),
      requestPasswordReset: { email in
        // A mismatch throws, which fails the `.sendResponse` receive below.
        if email != expectedEmail {
          throw HTTPRequestClient.Error.badResponse(UUID(), 500, #"{"error":"wrong"}"#)
        }
      }
    )

    await store.send(.forgotPasswordButtonTapped) {
      $0.forgotPassword = ForgotPasswordFeature.State(email: expectedEmail)
    }
    await store.send(.forgotPassword(.presented(.submitButtonTapped))) {
      $0.forgotPassword?.isLoading = true
    }
    await store.receive(.forgotPassword(.presented(.sendResponse))) {
      $0.forgotPassword?.isLoading = false
      $0.forgotPassword?.emailSent = true
    }
  }

  @Test
  func forgotPasswordBadResponseSurfacesServerMessage() async {
    let store = makeStore(
      initialState: AuthFeature.State(email: "user@example.com"),
      requestPasswordReset: { _ in
        throw HTTPRequestClient.Error.badResponse(
          UUID(), 400, #"{"error":"Something went wrong on our end"}"#
        )
      }
    )

    await store.send(.forgotPasswordButtonTapped) {
      $0.forgotPassword = ForgotPasswordFeature.State(email: "user@example.com")
    }
    await store.send(.forgotPassword(.presented(.submitButtonTapped))) {
      $0.forgotPassword?.isLoading = true
    }
    await store.receive(.forgotPassword(.presented(.failed("Something went wrong on our end")))) {
      $0.forgotPassword?.isLoading = false
      $0.forgotPassword?.errorMessage = "Something went wrong on our end"
    }
  }

  @Test
  func forgotPasswordSubmitWithEmptyEmailSendsNoRequest() async {
    var requested = false
    let store = makeStore(
      initialState: AuthFeature.State(),
      requestPasswordReset: { _ in
        requested = true
      }
    )

    await store.send(.forgotPasswordButtonTapped) {
      $0.forgotPassword = ForgotPasswordFeature.State()
    }
    // The email is empty: a no-op — no state change, no effect.
    await store.send(.forgotPassword(.presented(.submitButtonTapped)))
    #expect(!requested)
    #expect(store.state.forgotPassword?.isLoading != true)
  }

  @Test
  func forgotPasswordSubmitWhileLoadingSendsNoSecondRequest() async {
    // A stream gate, not an optional continuation: a yield before the effect
    // starts consuming is buffered, so the release signal cannot be lost.
    let (gate, gateContinuation) = AsyncStream<Void>.makeStream()
    let store = makeStore(
      initialState: AuthFeature.State(email: "user@example.com"),
      requestPasswordReset: { _ in
        for await _ in gate { break }
      }
    )

    await store.send(.forgotPasswordButtonTapped) {
      $0.forgotPassword = ForgotPasswordFeature.State(email: "user@example.com")
    }
    await store.send(.forgotPassword(.presented(.submitButtonTapped))) {
      $0.forgotPassword?.isLoading = true
    }
    // Still loading: a second submit is a no-op — no state change, no effect.
    await store.send(.forgotPassword(.presented(.submitButtonTapped)))

    gateContinuation.yield()
    await store.receive(.forgotPassword(.presented(.sendResponse))) {
      $0.forgotPassword?.isLoading = false
      $0.forgotPassword?.emailSent = true
    }
  }

  @Test
  func forgotPasswordCancelWhileLoadingEndsTheRequestWithoutAFailure() async {
    // The gate is never released: the request stays suspended until the
    // dismissal cancels it, then throws the way URLSession reports one.
    let (gate, _) = AsyncStream<Void>.makeStream()
    let store = makeStore(
      initialState: AuthFeature.State(email: "user@example.com"),
      requestPasswordReset: { _ in
        for await _ in gate {}
        throw URLError(.cancelled)
      }
    )

    await store.send(.forgotPasswordButtonTapped) {
      $0.forgotPassword = ForgotPasswordFeature.State(email: "user@example.com")
    }
    await store.send(.forgotPassword(.presented(.submitButtonTapped))) {
      $0.forgotPassword?.isLoading = true
    }
    // Dismissing cancels the in-flight request; no `.failed` follows.
    await store.send(.forgotPassword(.presented(.cancelButtonTapped)))
    await store.receive(.forgotPassword(.dismiss)) {
      $0.forgotPassword = nil
    }
  }

  @Test
  func forgotPasswordDoneDismissesTheSheet() async {
    let store = makeStore(initialState: AuthFeature.State(email: "user@example.com"))

    await store.send(.forgotPasswordButtonTapped) {
      $0.forgotPassword = ForgotPasswordFeature.State(email: "user@example.com")
    }
    await store.send(.forgotPassword(.presented(.doneButtonTapped)))
    await store.receive(.forgotPassword(.dismiss)) {
      $0.forgotPassword = nil
    }
  }

  @Test
  func forgotPasswordCancelDismissesTheSheet() async {
    let store = makeStore(initialState: AuthFeature.State(email: "user@example.com"))

    await store.send(.forgotPasswordButtonTapped) {
      $0.forgotPassword = ForgotPasswordFeature.State(email: "user@example.com")
    }
    await store.send(.forgotPassword(.presented(.cancelButtonTapped)))
    await store.receive(.forgotPassword(.dismiss)) {
      $0.forgotPassword = nil
    }
  }
}
