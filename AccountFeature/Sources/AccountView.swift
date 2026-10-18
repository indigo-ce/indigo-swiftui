import Components
import ComposableArchitecture
import Core
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "Indigo", category: "AccountFeature")

// MARK: - Feature

/// The signed-in profile.
///
/// The feature talks only to `@Dependency(\.accountClient)` — the template's
/// one shipped `sendAuthenticated` call site. It never touches the session:
/// a failed fetch (including a 401) shows the server's message and keeps any
/// profile already on screen, because the documented `sendAuthenticated`
/// contract leaves session decisions to the caller. Signing out works the
/// same way — the feature asks for confirmation and reports the answer
/// through `delegate(.signOutConfirmed)`; the revoking `sessionClient.signOut()`
/// effect stays with the presenter (`RootFeature`), which owns the session
/// observer that must run it.
@Reducer
public struct AccountFeature: Sendable {
  @Dependency(\.accountClient) var accountClient

  @ObservableState
  public struct State: Equatable, Sendable {
    /// The profile as last fetched. Kept across a failed refetch so a
    /// transient failure does not blank the screen.
    public var profile: AccountProfile?

    public var isLoading = false

    /// Set alongside any retained profile when a fetch fails; `nil` while a
    /// fetch is running, so the retry affordance disappears with the message.
    public var errorMessage: String?

    /// The sign-out confirmation, presented by the sign-out button.
    @Presents public var confirmationDialog: ConfirmationDialogState<Action.ConfirmationDialog>?

    public init() {}
  }

  public enum Action: Equatable, Sendable {
    case task
    case profileResponse(AccountProfile)
    case failed(String)
    case retryButtonTapped
    case signOutButtonTapped
    case confirmationDialog(PresentationAction<ConfirmationDialog>)
    case delegate(Delegate)

    @CasePathable
    public enum ConfirmationDialog: Equatable, Sendable {
      case confirmSignOutButtonTapped
    }

    @CasePathable
    public enum Delegate: Equatable, Sendable {
      case signOutConfirmed
    }
  }

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .retryButtonTapped:
        // The same guarded fetch `.task` runs: while a fetch is in flight the
        // retry affordance is already gone, and the guard keeps a stray tap
        // from starting a second concurrent request.
        return .send(.task)

      case .task:
        guard !state.isLoading else { return .none }
        state.isLoading = true
        state.errorMessage = nil
        return .run { send in
          do {
            // A refetch keeps the profile already on screen until the fresh
            // one lands, so a slow network never blanks the view.
            let profile = try await accountClient.fetchProfile()
            await send(.profileResponse(profile))
          } catch {
            // Dismissing the presenter mid-request cancels this effect; a
            // cancellation is not a request failure, so never log it as one
            // or report it to the view that is already gone.
            guard !Task.isCancelled else { return }
            logger.error("Profile fetch failed: \(error, privacy: .public)")
            await send(.failed(AccountFeature.errorMessage(from: error)))
          }
        }

      case .profileResponse(let profile):
        state.isLoading = false
        state.profile = profile
        return .none

      case .failed(let message):
        state.isLoading = false
        state.errorMessage = message
        return .none

      case .signOutButtonTapped:
        state.confirmationDialog = .signOut
        return .none

      case .confirmationDialog(.presented(.confirmSignOutButtonTapped)):
        state.confirmationDialog = nil
        return .send(.delegate(.signOutConfirmed))

      case .confirmationDialog, .delegate:
        return .none
      }
    }
    .ifLet(\.$confirmationDialog, action: \.confirmationDialog)
  }

  /// Maps a failed profile request to a user-facing message: the server's own
  /// words for a non-2xx answer with a decodable body, a generic fallback for
  /// transport failures or unreadable bodies. A 401 keeps its message here and
  /// nothing more — the feature neither signs out nor touches the session,
  /// matching the documented `sendAuthenticated` contract.
  static func errorMessage(from error: any Error) -> String {
    if let body = APIErrorBody.from(error) {
      return body.error
    }
    return String(localized: "Something went wrong. Please try again.")
  }
}

// MARK: - View

public struct AccountView: View {
  @Bindable var store: StoreOf<AccountFeature>

  public init(store: StoreOf<AccountFeature>) {
    self.store = store
  }

  public var body: some View {
    Form {
      if store.isLoading {
        Section {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
        }
      }

      if let profile = store.profile {
        Section {
          LabeledContent("Name", value: profile.name)
          LabeledContent("Email", value: profile.email)
          LabeledContent("Email verified", value: profile.emailVerified ? "Yes" : "No")
          LabeledContent(
            "Member since",
            value: profile.createdAt.formatted(date: .long, time: .omitted)
          )
        }
      }

      if let errorMessage = store.errorMessage {
        Section {
          InlineNotice.error(verbatim: errorMessage)
          Button("Retry") {
            store.send(.retryButtonTapped)
          }
        }
      }

      Section {
        Button("Sign Out", role: .destructive) {
          store.send(.signOutButtonTapped)
        }
      }
    }
    .task {
      await store.send(.task).finish()
    }
    .confirmationDialog(
      $store.scope(state: \.confirmationDialog, action: \.confirmationDialog)
    )
  }
}

// MARK: - Sign-out dialog

extension ConfirmationDialogState where Action == AccountFeature.Action.ConfirmationDialog {
  /// The sign-out confirmation, with the same title, message, and buttons the
  /// presenter used to show itself: the feature owns the question, the
  /// presenter owns the revoking effect that answers it.
  static var signOut: Self {
    ConfirmationDialogState {
      TextState("Sign Out?")
    } actions: {
      ButtonState(role: .destructive, action: .confirmSignOutButtonTapped) {
        TextState("Sign Out")
      }
      ButtonState(role: .cancel) {
        TextState("Cancel")
      }
    } message: {
      TextState(
        "Signing out (or switching accounts) wipes this account's cached notes from the device."
      )
    }
  }
}
