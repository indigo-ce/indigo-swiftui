import Dependencies
import JWTAuth
import Sharing
import Testing

@testable import Core

// Unit tests for the publish/destroy decisions of `AuthSessionGate`. The gate
// reads the stored session through `@Shared(.authSession)`, so each test
// seeds that shared value directly and drives the gate with recording
// closures — no network, no keychain.
@Suite(.serialized)
struct AuthSessionGateTests {
  private static func seed(_ tokens: AuthTokens?) {
    @Shared(.authSession) var session
    $session.withLock { $0 = tokens.map(AuthSession.valid) }
  }

  private static func storedRefresh() -> String? {
    @Shared(.authSession) var session
    return session?.tokens?.refresh
  }

  /// A persist closure that mirrors the real one: it records the write and
  /// updates the stored session, so subsequent decisions see the new state.
  private static func makeRecorder()
    -> (persist: @Sendable (AuthTokens) async throws -> Void, writes: LockIsolated<[AuthTokens]>)
  {
    let writes = LockIsolated<[AuthTokens]>([])
    return (
      persist: { tokens in
        writes.withValue { $0.append(tokens) }
        Self.seed(tokens)
      },
      writes: writes
    )
  }

  @Test func aPublishWithNoStagedEntryAlwaysWrites() async throws {
    Self.seed(nil)
    let gate = AuthSessionGate()
    let recorder = Self.makeRecorder()

    try await gate.publish(AuthTokens(access: "a", refresh: "r")) {
      try await recorder.persist(AuthTokens(access: "a", refresh: "r"))
    }

    #expect(recorder.writes.value.count == 1)
  }

  @Test func aStagedPublishWritesWhileItsSourceIsStillStored() async throws {
    Self.seed(AuthTokens(access: "a", refresh: "r"))
    let gate = AuthSessionGate()
    let recorder = Self.makeRecorder()

    await gate.stagePublish(newRefresh: "r2", sourceRefresh: "r")
    try await gate.publish(AuthTokens(access: "a2", refresh: "r2")) {
      try await recorder.persist(AuthTokens(access: "a2", refresh: "r2"))
    }

    #expect(recorder.writes.value.count == 1)
    #expect(Self.storedRefresh() == "r2")
  }

  @Test func aStagedPublishDropsOnceItsSourceIsDestroyed() async throws {
    Self.seed(AuthTokens(access: "a", refresh: "r"))
    let gate = AuthSessionGate()
    let recorder = Self.makeRecorder()

    await gate.stagePublish(newRefresh: "r2", sourceRefresh: "r")
    try await gate.destroy { Self.seed(nil) }
    try await gate.publish(AuthTokens(access: "a2", refresh: "r2")) {
      try await recorder.persist(AuthTokens(access: "a2", refresh: "r2"))
    }

    #expect(recorder.writes.value.isEmpty)
    #expect(Self.storedRefresh() == nil)
  }

  @Test func aStagedPublishDropsWhileSignOutIsInProgress() async throws {
    Self.seed(AuthTokens(access: "a", refresh: "r"))
    let gate = AuthSessionGate()
    let recorder = Self.makeRecorder()

    await gate.beginSignOut()
    await gate.stagePublish(newRefresh: "r2", sourceRefresh: "r")
    try await gate.publish(AuthTokens(access: "a2", refresh: "r2")) {
      try await recorder.persist(AuthTokens(access: "a2", refresh: "r2"))
    }
    #expect(recorder.writes.value.isEmpty)

    // The destroy that ends sign-out wipes the session and re-arms.
    try await gate.destroy { Self.seed(nil) }
    #expect(Self.storedRefresh() == nil)
  }

  @Test func aFreshSignInReArmsPublication() async throws {
    Self.seed(nil)
    let gate = AuthSessionGate()
    let recorder = Self.makeRecorder()

    // A sign-out window that never reaches its destroy (a cancelled revoke,
    // say) is closed by the next out-of-band save.
    await gate.beginSignOut()
    try await gate.publish(AuthTokens(access: "a", refresh: "r")) {
      try await recorder.persist(AuthTokens(access: "a", refresh: "r"))
    }
    #expect(recorder.writes.value.count == 1)

    // And a staged refresh publishes again from the signed-in session.
    await gate.stagePublish(newRefresh: "r2", sourceRefresh: "r")
    try await gate.publish(AuthTokens(access: "a2", refresh: "r2")) {
      try await recorder.persist(AuthTokens(access: "a2", refresh: "r2"))
    }
    #expect(recorder.writes.value.count == 2)
    #expect(Self.storedRefresh() == "r2")
  }
}
