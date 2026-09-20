import ComposableArchitecture
import JWTAuth
import NotesListFeature
import SwiftUI

// MARK: - Feature

/// The app's composition root. Restores the persisted auth session into
/// `@Shared(.authSession)` and refreshes an expired access token before any
/// feature runs, so features observe the settled session instead of racing
/// the restore.
@Reducer
public struct RootFeature: Sendable {
  @ObservableState
  public struct State: Equatable {
    @Shared(.authSession) public var authSession: AuthSession?
    public var isSessionLoaded = false
    public var notesList = NotesListFeature.State()

    public init() {}
  }

  public enum Action: Sendable {
    case task
    case sessionLoaded
    case notesList(NotesListFeature.Action)
  }

  @Dependency(\.jwtAuthClient) var authClient

  public init() {}

  public var body: some ReducerOf<Self> {
    Scope(state: \.notesList, action: \.notesList) {
      NotesListFeature()
    }

    Reduce { state, action in
      switch action {
      case .task:
        return .run { send in
          // The `try?` is deliberate: with no stored tokens the call throws
          // `AuthTokens.Error.missingToken`, which is the expected first-launch
          // path, and a transient network failure must not block the app. In
          // every case the session that could be restored has been restored.
          try? await authClient.refreshExpiredTokens()
          await send(.sessionLoaded)
        }

      case .sessionLoaded:
        state.isSessionLoaded = true
        return .none

      case .notesList:
        return .none
      }
    }
  }
}

// MARK: - View

public struct RootView: View {
  let store: StoreOf<RootFeature>

  public init(store: StoreOf<RootFeature>) {
    self.store = store
  }

  public var body: some View {
    Group {
      if store.isSessionLoaded {
        NotesListView(
          store: store.scope(state: \.notesList, action: \.notesList)
        )
      } else {
        ProgressView()
      }
    }
    // Kicks off the auth bootstrap exactly once per launch; without this the
    // session is never loaded and the progress view never resolves.
    .task {
      await store.send(.task).finish()
    }
  }
}
