import ComposableArchitecture
import Core
import JWTAuth
import NotesListFeature
import OSLog
import SQLiteData
import SwiftUI

private let logger = Logger(subsystem: "Indigo", category: "RootFeature")

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

    /// The `sub` claim of the last signed-in identity. `RootFeature` compares
    /// every later session value against it so an ordinary token rotation is
    /// not mistaken for an account switch (which wipes the user cache).
    @Shared(.appStorage("lastSignedInUserId")) public var lastSignedInUserId: String?

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
    case sessionChanged(AuthSession?)
    case userCacheWiped
    case notesList(NotesListFeature.Action)
  }

  @Dependency(\.jwtAuthClient) var authClient
  @Dependency(\.defaultDatabase) var database

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
        // Record the identity the first time a valid session is seen, so a
        // later session value has a baseline to compare against. A session
        // that is `.expired` or missing still gets a baseline for free: the
        // next `.valid` value counts as a fresh sign-in and is recorded when
        // it arrives.
        if state.lastSignedInUserId == nil,
          case .valid(let tokens) = state.authSession
        {
          state.$lastSignedInUserId.withLock { $0 = tokens[string: "sub"] }
        }
        // Forward every later session value to `.sessionChanged`. The launch
        // bootstrap already set the session before `.sessionLoaded`, so
        // `.dropFirst()` skips that replay — without it every launch would
        // look like a session change and wipe the cache before the user has
        // done anything.
        return .run { [authSession = state.$authSession] send in
          for await session in authSession.publisher.values.dropFirst() {
            await send(.sessionChanged(session))
          }
        }

      case .sessionChanged(let session):
        switch session {
        case .valid(let tokens):
          // Rotating an access token keeps the same identity — only a
          // different `sub` (or an unreadable token, whose `sub` reads back
          // `nil`) means the account actually changed.
          let incomingUserId = tokens[string: "sub"]
          guard state.lastSignedInUserId != incomingUserId
          else { return .none }

          state.$lastSignedInUserId.withLock { $0 = incomingUserId }
          // The notes-list reset is deferred to `.userCacheWiped` so the new
          // fetch cannot race the wipe and have its rows deleted out from
          // under it.
          return wipeUserCache()

        case .missing, .expired, nil:
          // A session that has gone away or is no longer valid must not
          // leave one account's cached rows behind.
          return wipeUserCache()
        }

      case .userCacheWiped:
        // Reset *after* the delete completes: a refetch issued before the
        // wipe would have its rows deleted underneath it.
        state.notesList = NotesListFeature.State()
        return .send(.notesList(.onAppear))

      case .notesList:
        return .none
      }
    }
  }

  private func wipeUserCache() -> Effect<Action> {
    .run { [database] send in
      do {
        try await clearUserCache(database)
        await send(.userCacheWiped)
      } catch {
        // A failed wipe must not crash the app; the stale rows are wiped on
        // the next session change.
        logger.error("Wipe user cache failed: \(error, privacy: .public)")
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
