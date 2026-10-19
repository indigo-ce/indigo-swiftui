import Dependencies
import JWTAuth
import Sharing

// MARK: - Gate

/// Serializes credential publication against sign-out.
///
/// `JWTAuthClient.refreshExpiredTokens()` — and every `sendAuthenticated` call
/// that needs a rotation — persists whatever the `refresh` closure returns by
/// calling `authTokensClient.set(newTokens)`. That write lives inside the
/// library with no hook for the app to veto it, so a refresh that completes
/// while sign-out is tearing the session down would store credentials *after*
/// `destroy()` and sign the user back in with a refresh token sign-out never
/// revoked.
///
/// The gate closes that hole. `JWTAuthClient`'s `refresh` closure records the
/// publish it is about to hand back (`stagePublish(newRefresh:sourceRefresh:)`),
/// and the gated `AuthTokensClient` (`.gated`) decides every write under the
/// gate's lock:
///
/// - A save that completes a staged refresh is written only while the refresh
///   token it started from is still the stored one and sign-out has not
///   begun. Otherwise it is dropped: the session it would republish is being
///   destroyed. The server has already issued the dropped refresh token, so
///   the gated client revokes it best effort — otherwise it would stay live
///   server-side with no copy left on the device to revoke later. The
///   decision happens at save time — sign-out may destroy the stored
///   credentials between staging and saving, and only the save-time check
///   sees the final state.
/// - Callers that shared one refresh flight each save its result, but only
///   the first successful save writes: later ones skip the write once the
///   rotation is known to be persisted, and are dropped (so revoked) once a
///   destroy has discarded it. When a rotation reached memory
///   through a failed save (the library publishes it before rethrowing), the
///   next staged caller persists it as a repair instead of skipping — memory
///   alone is never proof that the keychain holds the credentials.
/// - A destroy runs to completion before any other write, and ends the
///   sign-out window.
/// - Any other save is a fresh sign-in: it writes through and re-arms
///   publication after an abandoned sign-out.
///
/// `SessionClient.signOut` opens the sign-out window (`beginSignOut()`)
/// before it revokes, and the destroy it ends with closes it. Install
/// `.gated` once at launch so the library's internal publishes are gated too
/// — `App/Sources/IndigoApp.swift` does this in `prepareDependencies`.
actor AuthSessionGate: DependencyKey {
  static let liveValue = AuthSessionGate()
  static let previewValue = AuthSessionGate()
  static let testValue = AuthSessionGate()

  /// A rotation staged by the `refresh` closure: the refresh tokens its
  /// rotation started from (one entry per staged caller) and whether any
  /// caller has completed a keychain save of it yet.
  private struct StagedRefresh {
    var pendingSources: [String]
    var isPersisted = false
  }

  /// New refresh token → its staged rotation. Callers sharing one refresh
  /// flight each stage, and each of their saves consumes one entry.
  private var stagedRefreshes: [String: StagedRefresh] = [:]
  private var isSignOutInProgress = false

  // A promise-style mutex: `publish` and `destroy` hold it across the awaited
  // session/keychain writes, so a destroy can never interleave with the
  // middle of a save (which would leave one keychain entry behind). Plain
  // actor reentrancy is not enough — the writes suspend.
  private var isLocked = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  // MARK: API

  /// Records that the `refresh` closure is about to hand `newRefresh` back to
  /// the library, which persists it through the gated client. `sourceRefresh`
  /// is the refresh token the rotation started from; the publish decision
  /// re-checks it at save time.
  func stagePublish(newRefresh: String, sourceRefresh: String) {
    stagedRefreshes[newRefresh, default: StagedRefresh(pendingSources: [])]
      .pendingSources
      .append(sourceRefresh)
  }

  /// Marks the start of sign-out: from here until the destroy settles, no
  /// staged refresh publish may write credentials.
  func beginSignOut() {
    isSignOutInProgress = true
  }

  /// Decides and performs a credential save under the gate's lock. A save
  /// completing a staged refresh is dropped once sign-out has begun or its
  /// source refresh token is no longer the stored one; it is skipped after a
  /// co-sharer has already persisted the same rotation; and it is performed
  /// as a repair when the rotation is already in memory but no save has
  /// succeeded yet (the library moves an unsaved rotation into memory when
  /// its keychain save throws). Any other save is a fresh sign-in and
  /// re-arms publication.
  ///
  /// - Returns: `false` when the save was dropped.
  @discardableResult
  func publish(
    _ tokens: AuthTokens,
    persist: @Sendable () async throws -> Void
  ) async throws -> Bool {
    await acquire()
    do {
      if stagedRefreshes[tokens.refresh]?.pendingSources.isEmpty == false {
        // Every path below, a failed save included, consumes one staged
        // caller. The stored entry is updated in place, never through a
        // copy written back: a caller sharing this flight may stage while
        // the save below is suspended, and erasing its entry would let its
        // publish pass as a fresh sign-in after sign-out's destroy.
        let source = stagedRefreshes[tokens.refresh]!.pendingSources.removeFirst()
        defer { finishStaged(forKey: tokens.refresh) }
        if isSignOutInProgress {
          release()
          return false
        }
        if stagedRefreshes[tokens.refresh]!.isPersisted {
          // A caller that shared this refresh flight already persisted it.
          // The write is only skipped while the session still bears the
          // rotation — its tokens, or the source it rotated from while
          // memory lags the save. Once destruction has discarded both, the
          // drop sends the gated client after the rotated token: sign-out
          // only ever revoked the source, and the replacement must not stay
          // live server-side with no copy left on the device.
          @Shared(.authSession) var session
          let stillHeld =
            session?.tokens == tokens
            || session?.tokens?.refresh == source
          release()
          return stillHeld
        }
        @Shared(.authSession) var session
        let sourceIsCurrent = session?.tokens?.refresh == source
        let memoryHasRotation = session?.tokens == tokens
        guard sourceIsCurrent || memoryHasRotation else {
          release()
          return false
        }
        try await persist()
        stagedRefreshes[tokens.refresh]?.isPersisted = true
        release()
        return true
      } else {
        // A save that completes no staged refresh is a fresh sign-in.
        isSignOutInProgress = false
      }
      try await persist()
      release()
      return true
    } catch {
      release()
      throw error
    }
  }

  /// Performs a credential destroy under the gate's lock and closes the
  /// sign-out window — even on failure, because a failed destroy leaves the
  /// user signed in and their refreshes must keep publishing.
  func destroy(persist: @Sendable () async throws -> Void) async throws {
    await acquire()
    do {
      try await persist()
    } catch {
      isSignOutInProgress = false
      release()
      throw error
    }
    isSignOutInProgress = false
    release()
  }

  /// Drops a rotation once its last staged caller has published. An entry
  /// that gained callers while a save was suspended stays.
  private func finishStaged(forKey newRefresh: String) {
    if stagedRefreshes[newRefresh]?.pendingSources.isEmpty == true {
      stagedRefreshes[newRefresh] = nil
    }
  }

  // MARK: Mutex

  private func acquire() async {
    if isLocked {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        waiters.append(continuation)
      }
    } else {
      isLocked = true
    }
  }

  /// Hands the lock to the first waiter, or unlocks when none are queued.
  private func release() {
    if let next = waiters.first {
      waiters.removeFirst()
      next.resume()
    } else {
      isLocked = false
    }
  }
}

// MARK: - Gated client

extension AuthTokensClient {
  /// The live credential client with every write serialized through the
  /// shared `AuthSessionGate`, so a token refresh that completes while
  /// sign-out is in flight cannot publish the session being destroyed.
  ///
  /// Install it once at launch, next to the app's other default dependencies:
  ///
  /// ```swift
  /// prepareDependencies {
  ///   $0.authTokensClient = .gated
  /// }
  /// ```
  ///
  /// Without it, `refreshExpiredTokens()`'s unconditional publish can land
  /// after `SessionClient.signOut`'s destroy and sign the user back in.
  public static var gated: AuthTokensClient {
    gated(live: .liveValue, revoke: revokeRefreshToken)
  }

  /// `revoke` runs outside the gate's lock for every refresh token the gate
  /// drops, so a slow revoke never stalls sign-out's destroy.
  static func gated(
    live: AuthTokensClient,
    revoke: @escaping @Sendable (String) async -> Void
  ) -> AuthTokensClient {
    Self(
      save: { tokens in
        @Dependency(\.authSessionGate) var gate
        let published = try await gate.publish(tokens) {
          try await live.save(tokens)
        }
        if !published {
          await revoke(tokens.refresh)
        }
      },
      destroy: {
        @Dependency(\.authSessionGate) var gate
        try await gate.destroy {
          try await live.destroy()
        }
      }
    )
  }
}

// MARK: - Dependency registration

extension DependencyValues {
  var authSessionGate: AuthSessionGate {
    get { self[AuthSessionGate.self] }
    set { self[AuthSessionGate.self] = newValue }
  }
}
