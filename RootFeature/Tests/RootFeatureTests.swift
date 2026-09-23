import ComposableArchitecture
import Core
import Foundation
import JWTAuth
import SQLiteData
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
  private func tokens(sub: String) -> AuthTokens {
    func base64url(_ string: String) -> String {
      Data(string.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    }
    let header = base64url(#"{"alg":"HS256"}"#)
    let payload = base64url(#"{"sub":"\#(sub)"}"#)
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

  @Test func plainLaunchLeavesCachedRowsIntact() async throws {
    let database = try appDatabase()
    try await database.write { db in
      try Note.insert { Note.Draft(Note(title: "Survives the launch")) }.execute(db)
    }

    // Same database as the feature sees, so a wrongly-issued wipe would
    // delete the seeded row and fail the assertion below.
    let store = makeStore(database: database) { _ in
      AuthTokens(access: "fresh", refresh: "fresh")
    }

    await store.send(.task)
    await store.receive(\.sessionLoaded)

    await store.finish()

    let remaining = try await database.read { try Note.fetchAll($0) }
    #expect(remaining.count == 1)
  }
}
