import Components
import ComposableArchitecture
import Core
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "Indigo", category: "AuthFeature")

// MARK: - Feature

/// The forgot-password sheet.
///
/// A small child of `AuthFeature`: it asks `@Dependency(\.sessionClient)` for a
/// password-reset email and nothing else. Like its parent it never decides what
/// happens next — the emailed link opens the backend's reset page, so there is
/// no in-app destination to reach, and the session is never read or written.
/// A success swaps the form for a "check your email" notice; failures are
/// logged and surfaced with the server's own message through the same
/// `AuthFeature.errorMessage(from:)` mapping the sign-in form uses.
@Reducer
public struct ForgotPasswordFeature: Sendable {
  @Dependency(\.sessionClient) var sessionClient
  @Dependency(\.dismiss) var dismiss

  @ObservableState
  public struct State: Equatable, Sendable {
    public var email = ""
    public var isLoading = false
    public var errorMessage: String?
    public var emailSent = false

    public init(
      email: String = "",
      isLoading: Bool = false,
      errorMessage: String? = nil,
      emailSent: Bool = false
    ) {
      self.email = email
      self.isLoading = isLoading
      self.errorMessage = errorMessage
      self.emailSent = emailSent
    }
  }

  public enum Action: BindableAction, Equatable, Sendable {
    case binding(BindingAction<State>)
    case submitButtonTapped
    case sendResponse
    case failed(String)
    case cancelButtonTapped
    case doneButtonTapped
  }

  public init() {}

  public var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        return .none

      case .submitButtonTapped:
        guard !state.email.isEmpty, !state.isLoading else { return .none }
        state.isLoading = true
        // Starting a fresh attempt clears the previous attempt's error, so a
        // retry that succeeds never shows it next to the confirmation.
        state.errorMessage = nil
        let email = state.email
        return .run { send in
          do {
            try await sessionClient.requestPasswordReset(email)
            await send(.sendResponse)
          } catch {
            // Dismissing the sheet mid-request cancels this effect; a
            // cancellation is not a request failure, so never log it as one or
            // report it to the sheet that is already gone.
            guard !Task.isCancelled else { return }
            logger.error("Password-reset request failed: \(error, privacy: .public)")
            await send(.failed(AuthFeature.errorMessage(from: error)))
          }
        }

      case .sendResponse:
        state.isLoading = false
        state.emailSent = true
        return .none

      case .failed(let message):
        state.isLoading = false
        state.errorMessage = message
        return .none

      case .cancelButtonTapped, .doneButtonTapped:
        return .run { [dismiss] _ in await dismiss() }
      }
    }
  }
}

// MARK: - View

public struct ForgotPasswordView: View {
  @Bindable var store: StoreOf<ForgotPasswordFeature>

  public init(store: StoreOf<ForgotPasswordFeature>) {
    self.store = store
  }

  public var body: some View {
    NavigationStack {
      Form {
        if store.emailSent {
          InlineNotice("Check your email for a reset link.")

          Button {
            store.send(.doneButtonTapped)
          } label: {
            HStack {
              Spacer()
              Text("Done")
              Spacer()
            }
          }
        } else {
          Text(
            "Enter the email you signed up with and we'll send you a link to reset your password."
          )

          TextField("Email", text: $store.email)
            .disabled(store.isLoading)
            #if os(iOS)
              .keyboardType(.emailAddress)
              .textInputAutocapitalization(.never)
              .textContentType(.emailAddress)
            #endif
            .autocorrectionDisabled()

          Button {
            store.send(.submitButtonTapped)
          } label: {
            HStack {
              Spacer()
              if store.isLoading {
                ProgressView()
              } else {
                Text("Send Reset Link")
              }
              Spacer()
            }
          }
          .disabled(store.email.isEmpty || store.isLoading)

          if let errorMessage = store.errorMessage {
            InlineNotice.error(verbatim: errorMessage)
          }
        }
      }
      .navigationTitle("Reset Password")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            store.send(.cancelButtonTapped)
          }
        }
      }
    }
  }
}

// MARK: - Previews

#Preview {
  ForgotPasswordView(
    store: Store(initialState: ForgotPasswordFeature.State(email: "user@example.com")) {
      ForgotPasswordFeature()
    } withDependencies: {
      $0.sessionClient = .previewValue
    }
  )
}
