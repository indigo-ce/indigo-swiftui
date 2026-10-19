import Dependencies
import Foundation
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

  @Test func callersSharingARefreshFlightWriteItOnce() async throws {
    Self.seed(AuthTokens(access: "a", refresh: "r"))
    let gate = AuthSessionGate()
    let recorder = Self.makeRecorder()
    let shared = AuthTokens(access: "a2", refresh: "r2")

    // Two callers shared one rotation, so each stages and saves its result.
    await gate.stagePublish(newRefresh: "r2", sourceRefresh: "r")
    await gate.stagePublish(newRefresh: "r2", sourceRefresh: "r")
    let first = try await gate.publish(shared) { try await recorder.persist(shared) }
    let second = try await gate.publish(shared) { try await recorder.persist(shared) }

    #expect(first && second)
    #expect(recorder.writes.value.count == 1)
    #expect(Self.storedRefresh() == "r2")
  }

  /// A caller that stages while another caller's save is suspended keeps its
  /// staging — the finished save must not erase it by writing back a stale
  /// copy — so its publish, landing after sign-out's destroy, skips the
  /// write instead of restoring the discarded credentials.
  @Test func aStagingAppendedDuringASaveKeepsItsSignOutProtection() async throws {
    Self.seed(AuthTokens(access: "a", refresh: "r"))
    let gate = AuthSessionGate()
    let recorder = Self.makeRecorder()
    let shared = AuthTokens(access: "a2", refresh: "r2")

    await gate.stagePublish(newRefresh: "r2", sourceRefresh: "r")

    // The first caller's save parks mid-write.
    let (saveStarted, saveStartedContinuation) =
      AsyncStream<CheckedContinuation<Void, Never>>.makeStream()
    async let first = gate.publish(shared) {
      await withCheckedContinuation { continuation in
        saveStartedContinuation.yield(continuation)
      }
      try await recorder.persist(shared)
    }
    var pendingContinuation: CheckedContinuation<Void, Never>?
    for await continuation in saveStarted {
      pendingContinuation = continuation
      break
    }

    // While that save is suspended, a second caller stages its own, and
    // sign-out begins.
    await gate.stagePublish(newRefresh: "r2", sourceRefresh: "r")
    await gate.beginSignOut()

    pendingContinuation?.resume()
    let firstResult = try await first

    // Sign-out destroys the stored credentials, closing the sign-out window.
    try await gate.destroy { Self.seed(nil) }

    // The second caller's publish must not write: its rotation was saved by
    // the first caller, and the destroy discarded those credentials.
    let second = try await gate.publish(shared) { try await recorder.persist(shared) }

    #expect(firstResult)
    #expect(second)
    #expect(recorder.writes.value.count == 1)
    #expect(Self.storedRefresh() == nil)
  }

  /// When the first shared save throws, the library compensates by moving
  /// the rotation into memory while restoring the old keychain. The next
  /// caller sharing the flight must then still persist it — memory matching
  /// alone is never proof that the keychain holds the credentials.
  @Test func aFailedSharedSaveLetsTheNextCallerRetryPersistence() async throws {
    Self.seed(AuthTokens(access: "a", refresh: "r"))
    let gate = AuthSessionGate()
    let recorder = Self.makeRecorder()
    let shared = AuthTokens(access: "a2", refresh: "r2")

    await gate.stagePublish(newRefresh: "r2", sourceRefresh: "r")
    await gate.stagePublish(newRefresh: "r2", sourceRefresh: "r")

    // The first save fails on the transport; the recorder only counts
    // completed writes.
    do {
      try await gate.publish(shared) {
        throw URLError(.networkConnectionLost)
      }
      Issue.record("Expected the failing save to rethrow")
    } catch is URLError {
      // Expected.
    }

    // The library's compensation has published the rotation to memory while
    // the keychain kept the old credentials — the next caller must write.
    Self.seed(shared)
    let second = try await gate.publish(shared) { try await recorder.persist(shared) }

    #expect(second)
    #expect(recorder.writes.value.count == 1)
    #expect(Self.storedRefresh() == "r2")
  }

  @Test func callersSharingARefreshFlightStayDroppedDuringSignOut() async throws {
    Self.seed(AuthTokens(access: "a", refresh: "r"))
    let gate = AuthSessionGate()
    let recorder = Self.makeRecorder()
    let shared = AuthTokens(access: "a2", refresh: "r2")

    await gate.stagePublish(newRefresh: "r2", sourceRefresh: "r")
    await gate.stagePublish(newRefresh: "r2", sourceRefresh: "r")
    await gate.beginSignOut()
    // The second save must not pass for a fresh sign-in and re-arm.
    try await gate.publish(shared) { try await recorder.persist(shared) }
    try await gate.publish(shared) { try await recorder.persist(shared) }

    #expect(recorder.writes.value.isEmpty)
    #expect(Self.storedRefresh() == "r")
  }

  @Test func theGatedClientRevokesADroppedRefreshToken() async throws {
    Self.seed(AuthTokens(access: "a", refresh: "r"))
    let gate = AuthSessionGate()
    let saved = LockIsolated<[AuthTokens]>([])
    let revoked = LockIsolated<[String]>([])
    let client = withDependencies {
      $0.authSessionGate = gate
    } operation: {
      AuthTokensClient.gated(
        live: AuthTokensClient(
          save: { tokens in saved.withValue { $0.append(tokens) } },
          destroy: {}
        ),
        revoke: { refresh in revoked.withValue { $0.append(refresh) } }
      )
    }

    await gate.beginSignOut()
    await gate.stagePublish(newRefresh: "r2", sourceRefresh: "r")
    try await withDependencies {
      $0.authSessionGate = gate
    } operation: {
      try await client.save(AuthTokens(access: "a2", refresh: "r2"))
    }

    #expect(saved.value.isEmpty)
    #expect(revoked.value == ["r2"])
  }
}
