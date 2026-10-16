import ComposableArchitecture
import Components
import Core
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
          // retry that succeeds never shows it next to the confirmation.
          state.errorMessage = nil
          let email = state.email
          let password = state.password
          return .run { send in
            do {
              try await sessionClient.signIn(email, password)
              await send(.signInResponse)
            } catch {
              logger.error("Sign-in failed: \(error, privacy: .public)")
              await send(.failed(AuthFeature.errorMessage(from: error)))
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
