import ComposableArchitecture
import JWTAuth
import NotesListFeature
import SwiftUI

// MARK: - Feature

/// The app's composition root. Restores the persisted auth session from the
/// keychain before any feature runs, so features observe a settled session
/// instead of racing the restore. The launch gate waits on that keychain read
/// only — it must never wait on the network. Refreshing an expired access
/// token happens afterwards, in the background, and `@Shared(.authSession)`
/// republishes when it lands.
@Reducer
public struct RootFeature: Sendable {
  @ObservableState
  public struct State: Equatable {
    @Shared(.authSession) public var authSession: AuthSession?
    public var isSessionLoaded = false
    public var notesList = NotesListFeature.State()

    public init() {}

    /// Whether a persisted session is present. `.expired` still carries a
    /// usable refresh token, so it counts as signed in — the next
    /// `sendAuthenticated` (or the launch refresh) silently rotates the access
    /// token. Treating `.expired` as signed out would bounce a user with a
    /// merely stale access token to a login screen. Only `.missing` and `nil`
    /// mean "no session".
    public var isAuthenticated: Bool {
      switch authSession {
      case .valid, .expired:
        return true
      case .missing, nil:
        return false
      }
    }
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
          // The `try?`s are deliberate: with no stored tokens `loadSession()`
          // throws `AuthTokens.Error.missingToken`, which is the expected
          // first-launch path, and a transient network failure in the refresh
          // must not block the app. In every case the session that could be
          // restored has been restored before the gate is lifted; the refresh
          // settles afterwards in the background.
          try? await authClient.loadSession()
          await send(.sessionLoaded)
          try? await authClient.refreshExpiredTokens()
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
