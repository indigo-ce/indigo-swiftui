import AccountFeature
import AuthFeature
import ComposableArchitecture
import Core
import Foundation
import JWTAuth
import SQLiteData
import Synchronization
import Testing

@testable import RootFeature

@Suite
@MainActor
struct RootFeatureTests {
  // "stale" is not a decodable JWT, so `AuthTokens.toSession()` reports
  // `.expired`, which is what drives the refresh — no signed fixture token is
  // needed. `authTokensClient` stays live so the real persistence path runs
  // against the stub keychain.
  /// - Parameters:
  ///   - database: The database the feature sees. Defaults to its own temp-file
  ///     database; pass one you hold on to when the test asserts on its rows.
  private func makeStore(
    database: (any DatabaseWriter)? = nil,
    refresh: @escaping @Sendable (AuthTokens) async throws -> AuthTokens
  ) -> TestStoreOf<RootFeature> {
    let store = TestStore(initialState: RootFeature.State()) {
      RootFeature()
    } withDependencies: {
      $0.keychainClient.load = { _ in "stale" }
      $0.keychainClient.save = { _, _ in }
      $0.keychainClient.delete = { _ in }
      $0.authTokensClient = .liveValue
      $0.jwtAuthClient.refresh = refresh
      // The session observer installed at `.sessionLoaded` can see the
      // refresh flip the session (a rejected refresh becomes `.missing`,
      // which wipes the user cache), so the wipe path must stay runnable.
      $0.defaultDatabase = try! database ?? appDatabase()
      $0.notesClient.fetchAll = { [] }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    return store
  }

  @Test
  func taskRefreshesExpiredTokens() async {
    let store = makeStore { _ in AuthTokens(access: "fresh", refresh: "fresh") }

    await store.send(.task)
    await store.receive(\.sessionLoaded)

    await store.finish()

    // `.sessionLoaded` no longer implies the refresh has run: the launch gate
    // waits on the keychain restore only, so post-refresh assertions belong
    // after `finish()`.
    #expect(store.state.authSession?.tokens?.access == "fresh")
    #expect(store.state.isAuthenticated)
    #expect(store.state.isSessionLoaded)
  }

  @Test
  func taskRejectedRefreshDestroysCredentials() async {
    let store = makeStore { _ in throw AuthTokens.Error.refreshRejected }

    await store.send(.task)
    await store.receive(\.sessionLoaded)

    await store.finish()

    #expect(store.state.authSession == nil)
    #expect(!store.state.isAuthenticated)
    #expect(store.state.isSessionLoaded)
  }

  @Test
  func taskTransientRefreshFailurePreservesTokens() async {
    let store = makeStore { _ in throw URLError(.timedOut) }

    await store.send(.task)
    await store.receive(\.sessionLoaded)

    await store.finish()

    #expect(store.state.authSession?.tokens?.access == "stale")
    // The transient-failure case pins the `.expired` rule: a merely stale
    // access token still counts as signed in.
    #expect(store.state.isAuthenticated)
    #expect(store.state.isSessionLoaded)
  }

  @Test
  func sessionLoadedDoesNotWaitForRefresh() async {
    // The refresh suspends on a continuation this test owns, proving the
    // launch gate is lifted while the network refresh is still in flight.
    let (refreshStarted, refreshStartedContinuation) =
      AsyncStream<CheckedContinuation<Void, Never>>.makeStream()

    let store = makeStore { _ in
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        refreshStartedContinuation.yield(continuation)
      }
      return AuthTokens(access: "fresh", refresh: "fresh")
    }

    await store.send(.task)
    await store.receive(\.sessionLoaded)

    #expect(store.state.isSessionLoaded)
    // Still `.expired(stale)` while the refresh is suspended — signed in.
    #expect(store.state.isAuthenticated)

    var refreshContinuation: CheckedContinuation<Void, Never>?
    for await continuation in refreshStarted {
      refreshContinuation = continuation
      break
    }
    refreshContinuation?.resume()

    await store.finish()
  }
}

// MARK: - User cache reset

extension RootFeatureTests {
  /// Hand-assembled JWT whose payload decodes to `{"sub":"…"}`.
  /// `AuthTokens[string:]` decodes the token without verifying it, so no
  /// signed fixture is needed. Do not reuse the `"stale"` stub from
  /// `makeStore`: it is not decodable, so every `sub` reads back `nil`, which
  /// makes the same-identity guard swallow every transition and the tests
  /// pass for the wrong reason. Built directly rather than via `toSession()`,
  /// which inspects `exp`.
  private func tokens(sub: String?) -> AuthTokens {
    func base64url(_ string: String) -> String {
      Data(string.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    }
    let header = base64url(#"{"alg":"HS256"}"#)
    let payload = base64url(sub.map { #"{"sub":"\#($0)"}"# } ?? "{}")
    return AuthTokens(access: "\(header).\(payload).signature", refresh: "refresh")
  }

  @Test func switchingUsersWipesTheCacheAndRefetches() async throws {
    let database = try appDatabase()
    try await database.write { db in
      try Note.insert { Note.Draft(Note(title: "Previous user's note")) }.execute(db)
    }

    var state = RootFeature.State()
    state.$lastSignedInUserId.withLock { $0 = "a" }
    state.notesList.notes = [Note(title: "Previous user's note")]

    let store = TestStore(initialState: state) {
      RootFeature()
    } withDependencies: {
      $0.defaultDatabase = database
      $0.notesClient.fetchAll = { [] }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.sessionChanged(.valid(tokens(sub: "b"))))
    // NB: the reducer commits the marker only inside `.userCacheWiped`, so
    // there is no racy "marker is still the old value" assertion here — the
    // effect can deliver the completion before an intervening expectation
    // runs. The commit timing is pinned deterministically by
    // `wipeFailureKeepsTheMarkerAndHidesTheRows` (a failed wipe must leave
    // the marker alone).
    await store.receive(\.userCacheWiped)
    await store.receive(\.notesList.onAppear)
    await store.receive(\.notesList.notesLoaded)

    let remaining = try await database.read { try Note.fetchAll($0) }
    #expect(remaining.isEmpty)
    #expect(store.state.lastSignedInUserId == "b")
    #expect(store.state.notesList.notes.isEmpty)
  }

  @Test func endingTheSessionWipesTheCache() async throws {
    let database = try appDatabase()
    try await database.write { db in
      try Note.insert { Note.Draft(Note(title: "Ended session's note")) }.execute(db)
    }

    let state = RootFeature.State()
    state.$lastSignedInUserId.withLock { $0 = "a" }

    let store = TestStore(initialState: state) {
      RootFeature()
    } withDependencies: {
      $0.defaultDatabase = database
      $0.notesClient.fetchAll = { [] }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.sessionChanged(nil))
    await store.receive(\.userCacheWiped)
    await store.receive(\.notesList.onAppear)
    await store.receive(\.notesList.notesLoaded)

    let remaining = try await database.read { try Note.fetchAll($0) }
    #expect(remaining.isEmpty)
  }

  @Test func missingSessionWipesTheCache() async throws {
    let database = try appDatabase()
    try await database.write { db in
      try Note.insert { Note.Draft(Note(title: "Missing session's note")) }.execute(db)
    }

    let state = RootFeature.State()
    state.$lastSignedInUserId.withLock { $0 = "a" }

    let store = TestStore(initialState: state) {
      RootFeature()
    } withDependencies: {
      $0.defaultDatabase = database
      $0.notesClient.fetchAll = { [] }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.sessionChanged(.missing))
    await store.receive(\.userCacheWiped)
    await store.receive(\.notesList.onAppear)
    await store.receive(\.notesList.notesLoaded)

    let remaining = try await database.read { try Note.fetchAll($0) }
    #expect(remaining.isEmpty)
  }

  @Test func rotatingTokensForTheSameUserDoesNotWipeTheCache() async throws {
    let database = try appDatabase()
    try await database.write { db in
      try Note.insert { Note.Draft(Note(title: "Kept through rotation")) }.execute(db)
    }

    let state = RootFeature.State()
    state.$lastSignedInUserId.withLock { $0 = "a" }

    let store = TestStore(initialState: state) {
      RootFeature()
    } withDependencies: {
      $0.defaultDatabase = database
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.sessionChanged(.valid(tokens(sub: "a"))))

    let remaining = try await database.read { try Note.fetchAll($0) }
    #expect(remaining.count == 1)
  }

  /// A returning install restores `.expired` (its access token aged out),
  /// not `.valid`. The marker must be seeded from the expired session too —
  /// otherwise the routine refresh that follows publishes `.valid` for the
  /// SAME user and the nil-vs-"a" comparison reads it as an account switch.
  @Test func expiredRestoredSessionSeedsTheMarkerWithoutWiping() async throws {
    let database = try appDatabase()
    try await database.write { db in
      try Note.insert { Note.Draft(Note(title: "Returning user's note")) }.execute(db)
    }

    let state = RootFeature.State()
    state.authSession = .expired(tokens(sub: "a"))

    let store = TestStore(initialState: state) {
      RootFeature()
    } withDependencies: {
      $0.defaultDatabase = database
      $0.notesClient.fetchAll = { [] }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.sessionLoaded)

    #expect(store.state.lastSignedInUserId == "a")

    let remaining = try await database.read { try Note.fetchAll($0) }
    #expect(remaining.count == 1)

    // The refresh then publishes `.valid` for the same user: no wipe.
    await store.send(.sessionChanged(.valid(tokens(sub: "a"))))

    let stillThere = try await database.read { try Note.fetchAll($0) }
    #expect(stillThere.count == 1)
  }

  /// The process can die between persisting new credentials and committing
  /// the marker, so the restored session can belong to a different account
  /// than the marker claims. `.dropFirst()` would discard that session's
  /// only emission — the reconcile at `.sessionLoaded` is the only chance to
  /// catch the mismatch before the observer starts.
  @Test func restoredSessionIsReconciledAgainstTheStaleMarker() async throws {
    let database = try appDatabase()
    try await database.write { db in
      try Note.insert { Note.Draft(Note(title: "Account A's note")) }.execute(db)
    }

    let state = RootFeature.State()
    state.$lastSignedInUserId.withLock { $0 = "a" }
    state.authSession = .valid(tokens(sub: "b"))

    let store = TestStore(initialState: state) {
      RootFeature()
    } withDependencies: {
      $0.defaultDatabase = database
      $0.notesClient.fetchAll = { [] }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.sessionLoaded)
    await store.receive(\.userCacheWiped)
    await store.receive(\.notesList.onAppear)
    await store.receive(\.notesList.notesLoaded)

    let remaining = try await database.read { try Note.fetchAll($0) }
    #expect(remaining.isEmpty)
    #expect(store.state.lastSignedInUserId == "b")
  }

  /// A session that ended after the last launch (for example the wipe that
  /// should have accompanied it failed or was interrupted) is reconciled the
  /// same way: the launch itself finishes the teardown.
  @Test func endedSessionIsReconciledAtLaunch() async throws {
    let database = try appDatabase()
    try await database.write { db in
      try Note.insert { Note.Draft(Note(title: "Ended session's note")) }.execute(db)
    }

    let state = RootFeature.State()
    state.$lastSignedInUserId.withLock { $0 = "a" }
    state.authSession = .missing

    let store = TestStore(initialState: state) {
      RootFeature()
    } withDependencies: {
      $0.defaultDatabase = database
      $0.notesClient.fetchAll = { [] }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.sessionLoaded)
    await store.receive(\.userCacheWiped)
    await store.receive(\.notesList.onAppear)
    await store.receive(\.notesList.notesLoaded)

    let remaining = try await database.read { try Note.fetchAll($0) }
    #expect(remaining.isEmpty)
    #expect(store.state.lastSignedInUserId == nil)
  }

  /// A failed wipe hides the rows (the table may still hold the previous
  /// account's data) but keeps the marker naming the old account, so the
  /// next launch or session change retries the wipe.
  @Test func wipeFailureKeepsTheMarkerAndHidesTheRows() async throws {
    let database = try appDatabase()
    try await database.write { db in
      try Note.insert { Note.Draft(Note(title: "Undeletable note")) }.execute(db)
    }
    // A closed queue makes every write throw.
    try database.close()

    let state = RootFeature.State()
    state.$lastSignedInUserId.withLock { $0 = "a" }

    let store = TestStore(initialState: state) {
      RootFeature()
    } withDependencies: {
      $0.defaultDatabase = database
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.sessionChanged(nil))
    await store.receive(\.userCacheWipeFailed)

    #expect(store.state.lastSignedInUserId == "a")
    #expect(store.state.notesList.notes.isEmpty)
  }

  /// A fetch issued before the wipe must not repopulate the reset list: the
  /// wipe cancels the in-flight notes fetch, so releasing the stale fetch
  /// after `.userCacheWiped` delivers nothing. Only the post-wipe fetch can
  /// populate the list.
  @Test func wipeCancelsTheInFlightNotesFetch() async {
    let staleNote = Note(title: "Previous account's note")
    let (fetchStarted, fetchStartedContinuation) =
      AsyncStream<CheckedContinuation<[Note], Never>>.makeStream()
    // Only the first fetch (the pre-wipe one) suspends; the post-wipe
    // refetch resolves immediately.
    let fetchCalls = Mutex(0)

    let state = RootFeature.State()
    state.$lastSignedInUserId.withLock { $0 = "a" }

    let store = TestStore(initialState: state) {
      RootFeature()
    } withDependencies: {
      $0.defaultDatabase = try! appDatabase()
      $0.notesClient.fetchAll = {
        if fetchCalls.withLock({ $0 }) == 0 {
          fetchCalls.withLock { $0 += 1 }
          return await withCheckedContinuation { continuation in
            fetchStartedContinuation.yield(continuation)
          }
        }
        return []
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.notesList(.onAppear))

    var staleFetchContinuation: CheckedContinuation<[Note], Never>?
    for await continuation in fetchStarted {
      staleFetchContinuation = continuation
      break
    }

    await store.send(.sessionChanged(nil))
    await store.receive(\.userCacheWiped)
    await store.receive(\.notesList.onAppear)
    await store.receive(\.notesList.notesLoaded)
    // The reset list stays empty until the post-wipe fetch lands.
    #expect(store.state.notesList.notes.isEmpty)

    // Releasing the pre-wipe fetch must not repopulate the list: its effect
    // was cancelled at the wipe, so its `.notesLoaded` send is dropped.
    staleFetchContinuation?.resume(returning: [staleNote])
    await store.finish()

    #expect(store.state.notesList.notes.isEmpty)
  }

  /// The same guarantee when the wipe fails: `.userCacheWipeFailed` hides the
  /// rows, and an in-flight pre-wipe fetch must not bring them back.
  @Test func wipeFailureCancelsTheInFlightNotesFetch() async throws {
    let database = try appDatabase()
    try await database.write { db in
      try Note.insert { Note.Draft(Note(title: "Undeletable note")) }.execute(db)
    }
    // A closed queue makes every write throw.
    try database.close()

    let staleNote = Note(title: "Previous account's note")
    let (fetchStarted, fetchStartedContinuation) =
      AsyncStream<CheckedContinuation<[Note], Never>>.makeStream()

    let state = RootFeature.State()
    state.$lastSignedInUserId.withLock { $0 = "a" }

    let store = TestStore(initialState: state) {
      RootFeature()
    } withDependencies: {
      $0.defaultDatabase = database
      $0.notesClient.fetchAll = {
        await withCheckedContinuation { continuation in
          fetchStartedContinuation.yield(continuation)
        }
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.notesList(.onAppear))

    var staleFetchContinuation: CheckedContinuation<[Note], Never>?
    for await continuation in fetchStarted {
      staleFetchContinuation = continuation
      break
    }

    await store.send(.sessionChanged(nil))
    await store.receive(\.userCacheWipeFailed)

    #expect(store.state.lastSignedInUserId == "a")
    #expect(store.state.notesList.notes.isEmpty)

    // Releasing the pre-wipe fetch must not repopulate the hidden list.
    staleFetchContinuation?.resume(returning: [staleNote])
    await store.finish()

    #expect(store.state.notesList.notes.isEmpty)
  }

  @Test func plainLaunchLeavesCachedRowsIntact() async throws {
    let database = try appDatabase()
    try await database.write { db in
      try Note.insert { Note.Draft(Note(title: "Survives the launch")) }.execute(db)
    }

    // Same database as the feature sees, so a wrongly-issued wipe would
    // delete the seeded row and fail the assertion below. The refresh must
    // return a decodable, unexpired token: an unreadable one publishes as
    // `.expired`, which legitimately wipes. No `sub`, matching the restored
    // tokens, so the refresh is not an account switch either.
    let freshTokens = tokens(sub: nil)
    let store = makeStore(database: database) { _ in freshTokens }

    await store.send(.task)
    await store.receive(\.sessionLoaded)

    await store.finish()

    let remaining = try await database.read { try Note.fetchAll($0) }
    #expect(remaining.count == 1)
  }
}

// MARK: - Account flow

extension RootFeatureTests {
  /// A store whose session is already `.valid` and whose marker names the
  /// same account — the signed-in state the account button sees. No `.task`
  /// is sent, so no launch bootstrap runs. `makeStore` does not set
  /// `sessionClient` because only the sign-out path ever calls it; tests that
  /// confirm the sheet's sign-out override `sessionClient.signOut` per test.
  private func makeSignedInStore(
    signOut: (@Sendable () async throws -> Void)? = nil
  ) -> TestStoreOf<RootFeature> {
    var state = RootFeature.State()
    state.authSession = .valid(tokens(sub: "a"))
    state.$lastSignedInUserId.withLock { $0 = "a" }

    let store = TestStore(initialState: state) {
      RootFeature()
    } withDependencies: {
      $0.defaultDatabase = try! appDatabase()
      $0.notesClient.fetchAll = { [] }
      if let signOut {
        $0.sessionClient.signOut = signOut
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    return store
  }

  private struct SignOutFailed: Error {}

  @Test func accountButtonWithoutSessionPresentsSignIn() async {
    let store = makeStore { _ in AuthTokens(access: "fresh", refresh: "fresh") }

    await store.send(.notesList(.delegate(.accountButtonTapped)))

    #expect(store.state.auth != nil)
    #expect(store.state.account == nil)
  }

  @Test func accountButtonWithSessionPresentsTheAccountSheet() async {
    let store = makeSignedInStore()

    await store.send(.notesList(.delegate(.accountButtonTapped)))

    #expect(store.state.account != nil)
    #expect(store.state.auth == nil)
  }

  @Test func confirmingSignOutCallsSignOutOnceAndShowsNoAlert() async {
    let signOutCalls = Mutex(0)
    let store = makeSignedInStore {
      signOutCalls.withLock { $0 += 1 }
    }

    await store.send(.notesList(.delegate(.accountButtonTapped)))
    await store.send(.account(.presented(.delegate(.signOutConfirmed))))
    await store.receive(\.signOutResponse)

    #expect(signOutCalls.withLock { $0 } == 1)
    #expect(store.state.account == nil)
    #expect(store.state.alert == nil)
    #expect(!store.state.isSigningOut)
  }

  @Test func failedSignOutPresentsTheAlert() async {
    let store = makeSignedInStore {
      throw SignOutFailed()
    }

    await store.send(.notesList(.delegate(.accountButtonTapped)))
    await store.send(.account(.presented(.delegate(.signOutConfirmed))))
    await store.receive(\.signOutResponse)

    #expect(store.state.account == nil)
    #expect(store.state.alert != nil)
    #expect(!store.state.isSigningOut)
  }

  /// While a sign-out attempt is in flight, the account button presents
  /// nothing: re-presenting the sheet would let a second confirm start a
  /// second effect, whose stale failure response could raise the alert after
  /// a concurrent attempt already ended the session.
  @Test func accountButtonWhileSigningOutPresentsNothing() async {
    let (signOutStarted, signOutStartedContinuation) =
      AsyncStream<CheckedContinuation<Void, Never>>.makeStream()
    let store = makeSignedInStore {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        signOutStartedContinuation.yield(continuation)
      }
    }

    await store.send(.notesList(.delegate(.accountButtonTapped)))
    await store.send(.account(.presented(.delegate(.signOutConfirmed))))

    var pendingContinuation: CheckedContinuation<Void, Never>?
    for await continuation in signOutStarted {
      pendingContinuation = continuation
      break
    }
    #expect(store.state.isSigningOut)

    await store.send(.notesList(.delegate(.accountButtonTapped)))
    #expect(store.state.account == nil)
    #expect(store.state.auth == nil)
    #expect(store.state.isSigningOut)

    pendingContinuation?.resume()
    await store.receive(\.signOutResponse)

    #expect(!store.state.isSigningOut)
  }

  /// A sign-in that keeps the same account still publishes `.valid` — the
  /// sheet must be dismissed even though the same-`sub` guard then swallows
  /// the session change.
  @Test func validSessionDismissesPresentedSignInForTheSameAccount() async {
    var state = RootFeature.State()
    state.auth = AuthFeature.State()
    state.$lastSignedInUserId.withLock { $0 = "a" }

    let store = TestStore(initialState: state) {
      RootFeature()
    } withDependencies: {
      $0.defaultDatabase = try! appDatabase()
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.sessionChanged(.valid(tokens(sub: "a"))))

    #expect(store.state.auth == nil)
  }

  @Test func validSessionDismissesPresentedSignInAndWipesForANewAccount() async throws {
    let database = try appDatabase()
    try await database.write { db in
      try Note.insert { Note.Draft(Note(title: "Account A's note")) }.execute(db)
    }

    var state = RootFeature.State()
    state.auth = AuthFeature.State()
    state.$lastSignedInUserId.withLock { $0 = "a" }

    let store = TestStore(initialState: state) {
      RootFeature()
    } withDependencies: {
      $0.defaultDatabase = database
      $0.notesClient.fetchAll = { [] }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.sessionChanged(.valid(tokens(sub: "b"))))
    await store.receive(\.userCacheWiped)
    await store.receive(\.notesList.onAppear)
    await store.receive(\.notesList.notesLoaded)

    #expect(store.state.auth == nil)
    let remaining = try await database.read { try Note.fetchAll($0) }
    #expect(remaining.isEmpty)
  }

  /// A session that ends while the account sheet is open closes it: the
  /// profile on screen belongs to an identity that no longer exists (for
  /// example, a refresh rejected by the server).
  @Test func missingSessionClosesThePresentedAccountSheet() async {
    var state = RootFeature.State()
    state.authSession = .valid(tokens(sub: "a"))
    state.$lastSignedInUserId.withLock { $0 = "a" }
    state.account = AccountFeature.State()

    let store = TestStore(initialState: state) {
      RootFeature()
    } withDependencies: {
      $0.defaultDatabase = try! appDatabase()
      $0.notesClient.fetchAll = { [] }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.sessionChanged(.missing))
    await store.receive(\.userCacheWiped)
    await store.receive(\.notesList.onAppear)
    await store.receive(\.notesList.notesLoaded)

    #expect(store.state.account == nil)
  }

  /// An ordinary token rotation for the same account leaves the sheet alone:
  /// the profile it shows is still this user's.
  @Test func validSessionForTheSameAccountKeepsTheAccountSheetOpen() async {
    var state = RootFeature.State()
    state.authSession = .valid(tokens(sub: "a"))
    state.$lastSignedInUserId.withLock { $0 = "a" }
    state.account = AccountFeature.State()

    let store = TestStore(initialState: state) {
      RootFeature()
    } withDependencies: {
      $0.defaultDatabase = try! appDatabase()
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.sessionChanged(.valid(tokens(sub: "a"))))

    #expect(store.state.account != nil)
  }
}
