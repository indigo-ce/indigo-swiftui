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

    public enum Mode: Hashable, Sendable {
      case signIn
      case signUp
    }

    public init(
      mode: Mode = .signIn,
      name: String = "",
      email: String = "",
      password: String = ""
    ) {
      self.mode = mode
      self.name = name
      self.email = email
      self.password = password
    }
  }

  public enum Action: BindableAction, Equatable, Sendable {
    case binding(BindingAction<State>)
    case submitButtonTapped
    case signInResponse
    case signUpResponse
    case failed(String)
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
      }
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

      if store.signUpSuccess {
        InlineNotice("Account created. Check your email to verify it, then sign in.")
      }

      if store.mode == .signUp {
        TextField("Name", text: $store.name)
          #if os(iOS)
          .textInputAutocapitalization(.words)
          #endif
      }

      TextField("Email", text: $store.email)
        #if os(iOS)
        .keyboardType(.emailAddress)
        .textInputAutocapitalization(.never)
        .textContentType(.emailAddress)
        #endif
        .autocorrectionDisabled()

      SecureField("Password", text: $store.password)
        .textContentType(store.mode == .signUp ? .newPassword : .password)

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
        InlineNotice.error(LocalizedStringKey(errorMessage))
      }
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
