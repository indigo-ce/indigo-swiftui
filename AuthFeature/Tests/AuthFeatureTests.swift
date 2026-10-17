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
    requestPasswordReset: @escaping @Sendable (String) async throws -> Void = { _ in },
    sendVerificationEmail: @escaping @Sendable (String) async throws -> Void = { _ in }
  ) -> TestStoreOf<AuthFeature> {
    TestStore(initialState: initialState) {
      AuthFeature()
    } withDependencies: {
      $0.sessionClient.signIn = signIn
      $0.sessionClient.signUp = signUp
      $0.sessionClient.requestPasswordReset = requestPasswordReset
      $0.sessionClient.sendVerificationEmail = sendVerificationEmail
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

  // MARK: Unverified email

  @Test
  func signInRefusedAsUnverifiedOffersAResend() async {
    let refusedEmail = "unverified@example.com"
    let store = makeStore(
      initialState: AuthFeature.State(email: refusedEmail, password: "secret"),
      signIn: { email, _ in
        // A mismatch throws, which fails the `.emailNotVerified` receive below.
        if email != refusedEmail {
          throw HTTPRequestClient.Error.badResponse(UUID(), 500, #"{"error":"wrong"}"#)
        }
        throw HTTPRequestClient.Error.badResponse(
          UUID(), 401, #"{"error":"Email not verified"}"#
        )
      }
    )

    await store.send(.submitButtonTapped) {
      $0.isLoading = true
      $0.errorMessage = nil
      $0.unverifiedEmail = nil
      $0.verificationEmailSent = false
    }
    await store.receive(.emailNotVerified(email: refusedEmail, message: "Email not verified")) {
      $0.isLoading = false
      $0.errorMessage = "Email not verified"
      $0.unverifiedEmail = refusedEmail
    }
  }

  @Test
  func signInRefusedWithWrongCredentialsRecordsNoUnverifiedEmail() async {
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
      $0.errorMessage = nil
      $0.unverifiedEmail = nil
      $0.verificationEmailSent = false
    }
    await store.receive(.failed("Invalid email or password")) {
      $0.isLoading = false
      $0.errorMessage = "Invalid email or password"
    }
    #expect(store.state.unverifiedEmail == nil)
  }

  @Test
  func resendVerificationEmailCallsClientWithRefusedAddress() async {
    let refusedEmail = "unverified@example.com"
    let store = makeStore(
      initialState: {
        var state = AuthFeature.State(email: refusedEmail, password: "secret")
        state.errorMessage = "Email not verified"
        state.unverifiedEmail = refusedEmail
        return state
      }(),
      sendVerificationEmail: { email in
        // A mismatch throws, which fails the `.verificationEmailSent` receive
        // below.
        if email != refusedEmail {
          throw HTTPRequestClient.Error.badResponse(UUID(), 500, #"{"error":"wrong"}"#)
        }
      }
    )

    await store.send(.resendVerificationEmailButtonTapped) {
      $0.isLoading = true
      $0.errorMessage = nil
    }
    await store.receive(.verificationEmailSent(email: refusedEmail)) {
      $0.isLoading = false
      $0.verificationEmailSent = true
    }
    // The refused address is kept so the button still matches what the form
    // shows.
    #expect(store.state.unverifiedEmail == refusedEmail)
  }

  @Test
  func failedResendSurfacesServerMessageAndKeepsTheRefusedAddress() async {
    let refusedEmail = "unverified@example.com"
    let store = makeStore(
      initialState: {
        var state = AuthFeature.State(email: refusedEmail, password: "secret")
        state.unverifiedEmail = refusedEmail
        return state
      }(),
      sendVerificationEmail: { _ in
        throw HTTPRequestClient.Error.badResponse(
          UUID(), 400, #"{"error":"Too many emails. Try again later."}"#
        )
      }
    )

    await store.send(.resendVerificationEmailButtonTapped) {
      $0.isLoading = true
      $0.errorMessage = nil
    }
    await store.receive(.failed("Too many emails. Try again later.")) {
      $0.isLoading = false
      $0.errorMessage = "Too many emails. Try again later."
    }
    // The resend can be retried for the same address.
    #expect(store.state.unverifiedEmail == refusedEmail)
  }

  @Test
  func editingTheEmailClearsTheUnverifiedState() async {
    var initialState = AuthFeature.State(email: "unverified@example.com")
    initialState.errorMessage = "Email not verified"
    initialState.unverifiedEmail = "unverified@example.com"
    initialState.verificationEmailSent = true

    let store = TestStore(initialState: initialState) {
      AuthFeature()
    }

    await store.send(.binding(.set(\.email, "other@example.com"))) {
      $0.email = "other@example.com"
      $0.unverifiedEmail = nil
      $0.verificationEmailSent = false
    }
  }

  @Test
  func switchingModeClearsTheUnverifiedState() async {
    var initialState = AuthFeature.State(email: "unverified@example.com")
    initialState.unverifiedEmail = "unverified@example.com"
    initialState.verificationEmailSent = true

    let store = TestStore(initialState: initialState) {
      AuthFeature()
    }

    await store.send(.binding(.set(\.mode, .signUp))) {
      $0.mode = .signUp
      $0.errorMessage = nil
      $0.signUpSuccess = false
      $0.unverifiedEmail = nil
      $0.verificationEmailSent = false
    }
  }

  @Test
  func resendingWhileLoadingIsANoOp() async {
    // A stream gate, not an optional continuation: a yield before the effect
    // starts consuming is buffered, so the release signal cannot be lost when
    // the resume happens before the effect reaches its suspension point.
    let (gate, gateContinuation) = AsyncStream<Void>.makeStream()
    var initialState = AuthFeature.State(email: "unverified@example.com", password: "secret")
    initialState.unverifiedEmail = "unverified@example.com"
    let store = makeStore(
      initialState: initialState,
      signIn: { _, _ in
        for await _ in gate { break }
      },
      sendVerificationEmail: { _ in
        Issue.record("The resend must not run while a sign-in is in flight.")
      }
    )

    await store.send(.submitButtonTapped) {
      $0.isLoading = true
      $0.errorMessage = nil
      $0.unverifiedEmail = nil
      $0.verificationEmailSent = false
    }
    // Mid-request: the resend is a no-op — no state change, no effect.
    await store.send(.resendVerificationEmailButtonTapped)

    gateContinuation.yield()
    await store.receive(\.signInResponse) {
      $0.isLoading = false
    }
  }

  @Test
  func signInRefusalArrivingAfterAnEmailEditRecordsNoResendTarget() async {
    // The form disables its fields mid-request, but the reducer must not
    // depend on that: a refusal that races an edit must not point the resend
    // button at the address the form no longer shows.
    let refusedEmail = "unverified@example.com"
    let (gate, gateContinuation) = AsyncStream<Void>.makeStream()
    let store = makeStore(
      initialState: AuthFeature.State(email: refusedEmail, password: "secret"),
      signIn: { _, _ in
        for await _ in gate { break }
        throw HTTPRequestClient.Error.badResponse(
          UUID(), 401, #"{"error":"Email not verified"}"#
        )
      }
    )

    await store.send(.submitButtonTapped) {
      $0.isLoading = true
      $0.errorMessage = nil
      $0.unverifiedEmail = nil
      $0.verificationEmailSent = false
    }
    await store.send(.binding(.set(\.email, "other@example.com"))) {
      $0.email = "other@example.com"
      $0.unverifiedEmail = nil
      $0.verificationEmailSent = false
    }

    gateContinuation.yield()
    await store.receive(.emailNotVerified(email: refusedEmail, message: "Email not verified")) {
      $0.isLoading = false
      $0.errorMessage = "Email not verified"
    }
    // The stale refusal records no address, so no resend button appears.
    #expect(store.state.unverifiedEmail == nil)
  }

  @Test
  func resendCompletionAfterAnEmailEditIsIgnored() async {
    // A completion for the old address must not show the check-your-inbox
    // notice beside a different one.
    let refusedEmail = "unverified@example.com"
    let (gate, gateContinuation) = AsyncStream<Void>.makeStream()
    var initialState = AuthFeature.State(email: refusedEmail)
    initialState.unverifiedEmail = refusedEmail
    let store = makeStore(
      initialState: initialState,
      sendVerificationEmail: { _ in
        for await _ in gate { break }
      }
    )

    await store.send(.resendVerificationEmailButtonTapped) {
      $0.isLoading = true
      $0.errorMessage = nil
    }
    await store.send(.binding(.set(\.email, "other@example.com"))) {
      $0.email = "other@example.com"
      $0.unverifiedEmail = nil
      $0.verificationEmailSent = false
    }

    gateContinuation.yield()
    await store.receive(.verificationEmailSent(email: refusedEmail)) {
      $0.isLoading = false
    }
    #expect(!store.state.verificationEmailSent)
  }

  @Test
  func resendCompletionAfterAModeSwitchIsIgnored() async {
    // A completion that arrives after the user left sign-in must not light up
    // the notice when they switch back.
    let refusedEmail = "unverified@example.com"
    let (gate, gateContinuation) = AsyncStream<Void>.makeStream()
    var initialState = AuthFeature.State(email: refusedEmail)
    initialState.unverifiedEmail = refusedEmail
    let store = makeStore(
      initialState: initialState,
      sendVerificationEmail: { _ in
        for await _ in gate { break }
      }
    )

    await store.send(.resendVerificationEmailButtonTapped) {
      $0.isLoading = true
      $0.errorMessage = nil
    }
    await store.send(.binding(.set(\.mode, .signUp))) {
      $0.mode = .signUp
      $0.errorMessage = nil
      $0.signUpSuccess = false
      $0.unverifiedEmail = nil
      $0.verificationEmailSent = false
    }

    gateContinuation.yield()
    await store.receive(.verificationEmailSent(email: refusedEmail)) {
      $0.isLoading = false
    }
    #expect(!store.state.verificationEmailSent)
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
