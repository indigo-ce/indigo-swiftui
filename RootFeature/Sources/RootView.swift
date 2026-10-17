import AuthFeature
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
    /// not mistaken for an account switch (which wipes the user cache). The
    /// marker is committed only after the cache wipe that accompanies the
    /// identity change succeeds, so a crash can never leave the marker
    /// naming an account whose rows are still on disk — the next launch
    /// reconciles against the stale marker and retries the wipe.
    @Shared(.appStorage("lastSignedInUserId")) public var lastSignedInUserId: String?

    public var isSessionLoaded = false
    public var notesList = NotesListFeature.State()

    /// The sign-in / sign-up sheet, presented by the account button while
    /// signed out. Dismissed through the session observer below when a
    /// sign-in publishes — the feature never dismisses itself.
    @Presents public var auth: AuthFeature.State?

    /// The sign-out confirmation, presented by the account button while a
    /// session exists.
    @Presents public var confirmationDialog:
      ConfirmationDialogState<Action.ConfirmationDialog>?

    /// Shown when `signOut` throws: destroying the local credentials is the
    /// only step that can fail, and a silent failure would leave the user
    /// believing they had signed out when their credentials are still on the
    /// device.
    @Presents public var alert: AlertState<Never>?

    /// A `signOut` attempt is in flight. While it runs, the account button
    /// presents nothing: re-presenting the dialog would let a second confirm
    /// start a second effect, whose stale failure response could raise the
    /// alert after a concurrent attempt already ended the session.
    public var isSigningOut = false

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
    case userCacheWiped(pendingUserId: String?)
    case userCacheWipeFailed
    case notesList(NotesListFeature.Action)
    case auth(PresentationAction<AuthFeature.Action>)
    case confirmationDialog(PresentationAction<ConfirmationDialog>)
    case alert(PresentationAction<Never>)
    case signOutResponse(Result<Void, any Error>)

    @CasePathable
    public enum ConfirmationDialog: Equatable, Sendable {
      case confirmSignOutButtonTapped
    }
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
        let restoredUserId = state.authSession?.tokens?[string: "sub"]
        // Seed the marker on first sight of a session — `.expired` included.
        // An install returning after days restores `.expired`, and its
        // routine refresh then publishes `.valid` for the SAME user; without
        // a baseline that refresh would be mistaken for an account switch
        // and would erase the cache.
        if state.lastSignedInUserId == nil, let restoredUserId {
          state.$lastSignedInUserId.withLock { $0 = restoredUserId }
        }
        // Reconcile the restored session against the marker before the
        // observer's `.dropFirst()` discards its replay — the replay is the
        // only chance to catch a restore that belongs to a different account
        // than the marker claims (the process can die between persisting the
        // new credentials and committing the new marker), or a session that
        // ended after the last launch. A session whose tokens carry no
        // readable `sub` proves nothing about identity and is left alone.
        let sessionEnded = state.authSession == nil || state.authSession == .missing
        let reconcile: Effect<Action> =
          (restoredUserId != nil && restoredUserId != state.lastSignedInUserId)
          || (sessionEnded && state.lastSignedInUserId != nil)
          ? wipeUserCache(pendingUserId: restoredUserId)
          : .none
        // Forward every later session value to `.sessionChanged`. The launch
        // bootstrap already handled the current value above, so `.dropFirst()`
        // skips that replay — without it every launch would look like a
        // session change and wipe the cache before the user has done anything.
        return .merge(
          reconcile,
          .run { [authSession = state.$authSession] send in
            for await session in authSession.publisher.values.dropFirst() {
              await send(.sessionChanged(session))
            }
          }
        )

      case .sessionChanged(let session):
        switch session {
        case .valid(let tokens):
          // A successful sign-in publishes here, whether it switched accounts
          // or not: dismiss the auth sheet before the same-`sub` early return
          // so an ordinary sign-in that keeps the same account is dismissed
          // too.
          state.auth = nil
          // Rotating an access token keeps the same identity — only a
          // different `sub` (or an unreadable token, whose `sub` reads back
          // `nil`) means the account actually changed.
          let incomingUserId = tokens[string: "sub"]
          guard incomingUserId != state.lastSignedInUserId
          else { return .none }

          // The marker is NOT updated here: it is committed only after the
          // wipe succeeds, so an interrupted wipe leaves the old marker in
          // place and the next launch retries the wipe instead of trusting
          // it. The notes-list reset is likewise deferred to
          // `.userCacheWiped` so the new fetch cannot race the wipe and have
          // its rows deleted out from under it.
          return wipeUserCache(pendingUserId: incomingUserId)

        case .missing, .expired, nil:
          // A session that has gone away or is no longer valid must not
          // leave one account's cached rows behind.
          return wipeUserCache(pendingUserId: nil)
        }

      case .userCacheWiped(let pendingUserId):
        // Commit the durable marker only now that the delete has succeeded,
        // then reset *after* the delete completes: a refetch issued before
        // the wipe would have its rows deleted underneath it.
        state.$lastSignedInUserId.withLock { $0 = pendingUserId }
        state.notesList = NotesListFeature.State()
        return .send(.notesList(.onAppear))

      case .userCacheWipeFailed:
        // Hide the previous account's rows without refetching — the table
        // may still hold them. Cancel any in-flight notes fetch too: a
        // pre-wipe read must not repopulate the list the failed wipe just
        // hid. The marker keeps naming the old account, so the next launch
        // (or session change) retries the wipe.
        state.notesList = NotesListFeature.State()
        return .cancel(id: NotesListFeature.CancelID.fetch)

      case .notesList(.delegate(.accountButtonTapped)):
        // Authentication is offered, not forced: the notes app must stay
        // usable without a backend, so the button presents the sign-in sheet
        // when signed out and the sign-out confirmation when signed in.
        guard !state.isSigningOut else { return .none }
        if state.isAuthenticated {
          state.confirmationDialog = .signOut
        } else {
          state.auth = AuthFeature.State()
        }
        return .none

      case .notesList:
        return .none

      case .confirmationDialog(.presented(.confirmSignOutButtonTapped)):
        state.confirmationDialog = nil
        state.isSigningOut = true
        return .run { send in
          @Dependency(\.sessionClient) var sessionClient
          do {
            try await sessionClient.signOut()
            await send(.signOutResponse(.success(())))
          } catch {
            await send(.signOutResponse(.failure(error)))
          }
        }

      case .signOutResponse(.success):
        // The credential destroy published the session change; the observer
        // above performs the cache wipe with no extra wiring.
        state.isSigningOut = false
        return .none

      case .signOutResponse(.failure(let error)):
        logger.error("Sign out failed: \(error, privacy: .public)")
        state.isSigningOut = false
        state.alert = AlertState {
          TextState("Couldn't sign out.")
        } message: {
          TextState("Please try again.")
        }
        return .none

      case .auth, .alert, .confirmationDialog:
        return .none
      }
    }
    .ifLet(\.$auth, action: \.auth) {
      AuthFeature()
    }
  }

  private func wipeUserCache(pendingUserId: String?) -> Effect<Action> {
    // A pre-wipe read must not repopulate the reset list: cancel any notes
    // fetch issued before the wipe, so only a fetch started after
    // `.userCacheWiped` (or `.userCacheWipeFailed`) can deliver rows.
    .merge(
      .cancel(id: NotesListFeature.CancelID.fetch),
      .run { [database] send in
        do {
          try await clearUserCache(database)
          await send(.userCacheWiped(pendingUserId: pendingUserId))
        } catch {
          // A failed wipe must not crash the app; the stale rows are wiped on
          // the next session change or launch.
          logger.error("Wipe user cache failed: \(error, privacy: .public)")
          await send(.userCacheWipeFailed)
        }
      }
    )
  }
}

// MARK: - View

public struct RootView: View {
  @Bindable var store: StoreOf<RootFeature>

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
    // Account entry and exit are owned here, at the root, because the session
    // observer lives in the same feature: a successful sign-in dismisses the
    // sheet through `.sessionChanged`, and sign-out runs the revoking
    // `sessionClient.signOut()`.
    .sheet(item: $store.scope(state: \.auth, action: \.auth)) { authStore in
      NavigationStack {
        AuthView(store: authStore)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Cancel") {
                store.send(.auth(.dismiss))
              }
            }
          }
      }
    }
    .confirmationDialog(
      $store.scope(state: \.confirmationDialog, action: \.confirmationDialog)
    )
    .alert($store.scope(state: \.alert, action: \.alert))
  }
}

// MARK: - Sign-out dialog

extension ConfirmationDialogState where Action == RootFeature.Action.ConfirmationDialog {
  /// The sign-out confirmation the account button presents while signed in.
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
