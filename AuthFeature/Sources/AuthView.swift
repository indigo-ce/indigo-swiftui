import ComposableArchitecture
import Components
import Core
import HTTPRequestClient
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "Indigo", category: "AuthFeature")

// MARK: - Feature

/// The sign-in / sign-up form.
///
/// The feature talks only to `@Dependency(\.sessionClient)`: a successful
/// sign-in is published by `SessionClient.signIn`'s gated credential save, so
/// the feature itself never decides what happens next — its presenter reacts
/// to the session change (see the observer in `RootFeature`). Failures are
/// logged and surfaced with the server's own message through
/// `AuthFeature.errorMessage(from:)`.
@Reducer
public struct AuthFeature: Sendable {
  @Dependency(\.sessionClient) var sessionClient

  @ObservableState
  public struct State: Equatable, Sendable {
    public var mode: Mode = .signIn
    public var name = ""
    public var email = ""
    public var password = ""
    public var isLoading = false
    public var errorMessage: String?
    // Set when a sign-up succeeded. Signing up does not sign in — see
    // `SessionClient`.
    public var signUpSuccess = false
    // The address a sign-in was refused for as unverified, and whether a
    // resend of the verification email for it has succeeded. Cleared whenever
    // the form stops showing that address (a mode switch, an email edit, or a
    // new sign-in submission) so the resend button never targets an address
    // the user can no longer see.
    public var unverifiedEmail: String?
    public var verificationEmailSent = false
    // The forgot-password sheet, offered in sign-in mode and seeded with the
    // email already typed.
    @Presents public var forgotPassword: ForgotPasswordFeature.State?

    public enum Mode: Hashable, Sendable {
      case signIn
      case signUp
    }

    public init(
      mode: Mode = .signIn,
      name: String = "",
      email: String = "",
      password: String = "",
      forgotPassword: ForgotPasswordFeature.State? = nil
    ) {
      self.mode = mode
      self.name = name
      self.email = email
      self.password = password
      self.forgotPassword = forgotPassword
    }
  }

  public enum Action: BindableAction, Equatable, Sendable {
    case binding(BindingAction<State>)
    case submitButtonTapped
    case signInResponse
    case signUpResponse
    case failed(String)
    case emailNotVerified(email: String, message: String)
    case resendVerificationEmailButtonTapped
    case verificationEmailSent(email: String)
    case forgotPasswordButtonTapped
    case forgotPassword(PresentationAction<ForgotPasswordFeature.Action>)
  }

  public init() {}

  public var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding(\.mode):
        state.errorMessage = nil
        state.signUpSuccess = false
        state.unverifiedEmail = nil
        state.verificationEmailSent = false
        return .none

      case .binding(\.email):
        state.unverifiedEmail = nil
        state.verificationEmailSent = false
        return .none

      case .binding:
        return .none

      case .submitButtonTapped:
        guard !state.isLoading else { return .none }

        switch state.mode {
        case .signIn:
          guard !state.email.isEmpty, !state.password.isEmpty else { return .none }
          state.isLoading = true
          // Starting a fresh attempt clears the previous attempt's error, so a
          // retry that succeeds never shows it next to the confirmation. It
          // also drops a stale unverified-email state: the resend button must
          // never target an address the form no longer shows.
          state.errorMessage = nil
          state.unverifiedEmail = nil
          state.verificationEmailSent = false
          let email = state.email
          let password = state.password
          return .run { send in
            do {
              try await sessionClient.signIn(email, password)
              await send(.signInResponse)
            } catch {
              logger.error("Sign-in failed: \(error, privacy: .public)")
              if AuthFeature.isEmailNotVerified(error) {
                await send(
                  .emailNotVerified(email: email, message: AuthFeature.errorMessage(from: error))
                )
              } else {
                await send(.failed(AuthFeature.errorMessage(from: error)))
              }
            }
          }

        case .signUp:
          guard !state.name.isEmpty, !state.email.isEmpty, !state.password.isEmpty else {
            return .none
          }
          state.isLoading = true
          state.errorMessage = nil
          let name = state.name
          let email = state.email
          let password = state.password
          return .run { send in
            do {
              try await sessionClient.signUp(name, email, password)
              await send(.signUpResponse)
            } catch {
              logger.error("Sign-up failed: \(error, privacy: .public)")
              await send(.failed(AuthFeature.errorMessage(from: error)))
            }
          }
        }

      case .signInResponse:
        // The gated save inside `SessionClient.signIn` has published the
        // session; the presenter dismisses this feature through the session
        // observer. Nothing else to do here.
        state.isLoading = false
        return .none

      case .signUpResponse:
        // Signing up does not sign in: land in sign-in with the password
        // cleared and let the notice tell the user what to do next.
        state.isLoading = false
        state.signUpSuccess = true
        state.mode = .signIn
        state.password = ""
        return .none

      case .failed(let message):
        state.isLoading = false
        state.errorMessage = message
        return .none

      case .emailNotVerified(let email, let message):
        state.isLoading = false
        state.errorMessage = message
        // Only record the refusal's address while the form still shows it: a
        // response that races an edit must not point the resend button at an
        // address the user no longer sees.
        if email == state.email {
          state.unverifiedEmail = email
        }
        return .none

      case .resendVerificationEmailButtonTapped:
        guard !state.isLoading, let email = state.unverifiedEmail else { return .none }
        state.isLoading = true
        state.errorMessage = nil
        return .run { send in
          do {
            try await sessionClient.sendVerificationEmail(email)
            await send(.verificationEmailSent(email: email))
          } catch {
            logger.error("Verification-email resend failed: \(error, privacy: .public)")
            await send(.failed(AuthFeature.errorMessage(from: error)))
          }
        }

      case .verificationEmailSent(let email):
        state.isLoading = false
        // Same rule as `.emailNotVerified`: apply the confirmation only while
        // the resend still belongs to what the form shows. An email edit or a
        // mode switch clears `unverifiedEmail`, so a completion for the old
        // address no longer matches and is dropped.
        if email == state.unverifiedEmail {
          state.verificationEmailSent = true
        }
        return .none

      case .forgotPasswordButtonTapped:
        // Sign-in mode only, and never mid-request: a half-typed sign-up or an
        // in-flight attempt is not a reset request for the typed email.
        guard state.mode == .signIn, !state.isLoading else { return .none }
        state.forgotPassword = ForgotPasswordFeature.State(email: state.email)
        return .none

      case .forgotPassword:
        return .none
      }
    }
    .ifLet(\.$forgotPassword, action: \.forgotPassword) {
      ForgotPasswordFeature()
    }
  }

  /// Maps a failed sign-in / sign-up request to a user-facing message: the
  /// server's own words for a non-2xx answer with a decodable body, a generic
  /// fallback for transport failures or unreadable bodies.
  static func errorMessage(from error: any Error) -> String {
    if let body = APIErrorBody.from(error) {
      return body.error
    }
    return String(localized: "Something went wrong. Please try again.")
  }

  /// Whether `error` is a sign-in refused because the account's email is not
  /// verified — the refusal `sendVerificationEmail` is the recovery path for.
  /// The backend sends no stable `code` for this case, so the exact message is
  /// the only discriminator.
  static func isEmailNotVerified(_ error: any Error) -> Bool {
    guard case HTTPRequestClient.Error.badResponse(_, 401, _) = error else { return false }
    return APIErrorBody.from(error)?.error == "Email not verified"
  }
}

// MARK: - View

public struct AuthView: View {
  @Bindable var store: StoreOf<AuthFeature>

  public init(store: StoreOf<AuthFeature>) {
    self.store = store
  }

  public var body: some View {
    Form {
      Picker("Mode", selection: $store.mode) {
        Text("Sign In").tag(AuthFeature.State.Mode.signIn)
        Text("Sign Up").tag(AuthFeature.State.Mode.signUp)
      }
      .pickerStyle(.segmented)
      // A response in flight belongs to the mode it was submitted from:
      // switching modes mid-request would apply its result to the wrong form.
      .disabled(store.isLoading)

      if store.signUpSuccess {
        InlineNotice("Account created. Check your email to verify it, then sign in.")
      }

      if store.mode == .signUp {
        TextField("Name", text: $store.name)
          .disabled(store.isLoading)
          #if os(iOS)
          .textInputAutocapitalization(.words)
          #endif
      }

      TextField("Email", text: $store.email)
        .disabled(store.isLoading)
        #if os(iOS)
        .keyboardType(.emailAddress)
        .textInputAutocapitalization(.never)
        .textContentType(.emailAddress)
        #endif
        .autocorrectionDisabled()

      SecureField("Password", text: $store.password)
        .disabled(store.isLoading)
        .textContentType(store.mode == .signUp ? .newPassword : .password)

      if store.mode == .signIn {
        Button("Forgot password?") {
          store.send(.forgotPasswordButtonTapped)
        }
        .font(.footnote)
        .disabled(store.isLoading)
      }

      Button {
        store.send(.submitButtonTapped)
      } label: {
        HStack {
          Spacer()
          if store.isLoading {
            ProgressView()
          } else {
            Text(store.mode == .signUp ? "Sign Up" : "Sign In")
          }
          Spacer()
        }
      }
      .disabled(store.isLoading)

      if let errorMessage = store.errorMessage {
        InlineNotice.error(verbatim: errorMessage)
      }

      if store.mode == .signIn, store.unverifiedEmail != nil, !store.verificationEmailSent {
        Button("Resend verification email") {
          store.send(.resendVerificationEmailButtonTapped)
        }
        .disabled(store.isLoading)
      }

      if store.mode == .signIn, store.verificationEmailSent {
        InlineNotice("Verification email sent. Check your inbox, then sign in.")
      }
    }
    .sheet(item: $store.scope(state: \.forgotPassword, action: \.forgotPassword)) {
      forgotPasswordStore in
      ForgotPasswordView(store: forgotPasswordStore)
    }
  }
}

// MARK: - Previews

#Preview("Sign In") {
  NavigationStack {
    AuthView(
      store: Store(initialState: AuthFeature.State()) {
        AuthFeature()
      } withDependencies: {
        $0.sessionClient = .previewValue
      }
    )
  }
}

#Preview("Sign Up") {
  NavigationStack {
    AuthView(
      store: Store(initialState: AuthFeature.State(mode: .signUp)) {
        AuthFeature()
      } withDependencies: {
        $0.sessionClient = .previewValue
      }
    )
  }
}
