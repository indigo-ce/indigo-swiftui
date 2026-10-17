import Dependencies
import DependenciesMacros
import Foundation
import HTTPRequestBuilder

// MARK: - Profile model

/// The signed-in user as `GET /api/v1/account/profile` answers it: the same
/// shape the backend's `User` schema describes. `image` is nullable, and both
/// dates are ISO-8601 strings with fractional seconds that `JSONCoders.api`
/// decodes into `Date`.
public struct AccountProfile: Decodable, Equatable, Sendable {
  public let id: String
  public let email: String
  public let name: String
  public let image: String?
  public let emailVerified: Bool
  public let createdAt: Date
  public let updatedAt: Date

  /// Memberwise on purpose: the synthesized initializer is internal, and
  /// feature targets (separate frameworks) constructing fixtures for previews
  /// or tests could not build a profile otherwise. See `Note` for the same
  /// convention.
  public init(
    id: String,
    email: String,
    name: String,
    image: String? = nil,
    emailVerified: Bool,
    createdAt: Date,
    updatedAt: Date
  ) {
    self.id = id
    self.email = email
    self.name = name
    self.image = image
    self.emailVerified = emailVerified
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

// MARK: - Client

/// Fetches the signed-in user's profile with `GET /api/v1/account/profile`.
///
/// This is the template's one shipped `sendAuthenticated` call site, and the
/// reason the distinction with `SessionClient` matters: every
/// `SessionClient` route uses `send` because those requests run before a
/// session exists (sign-in, sign-up) or while tearing one down (sign-out,
/// revoke), so there is no bearer token to attach — and refreshing first
/// could rotate the very credentials the operation is about to destroy or
/// overwrite. Fetching the profile is the opposite: it only makes sense
/// signed in, so the live closure hands the request to `sendAuthenticated`
/// and lets the library do what its contract documents — refresh an
/// already-expired access token first, attach `Authorization: Bearer <access>`,
/// and send once.
///
/// A 401 from the route (a bad token, or a user deleted server-side after
/// sign-in) is **not** retried and refreshes nothing: the error propagates
/// untouched, with no session mutation, matching the documented
/// `sendAuthenticated` contract. The caller decides what an unauthorized
/// profile means — typically routing the user back through sign-in — and can
/// read the server's message through `APIErrorBody.from(error)`.
@DependencyClient
public struct AccountClient: Sendable {
  public var fetchProfile: @Sendable () async throws -> AccountProfile
}

extension AccountClient: DependencyKey {
  // Dependencies are resolved inside the closure — the way `SessionClient`
  // and `JWTAuthClient+Live.swift` do — so `withDependencies` overrides apply
  // at call time.
  public static let liveValue: AccountClient = Self(
    fetchProfile: {
      @Dependency(\.apiClient) var apiClient
      @Dependency(\.networkSession) var networkSession

      return try await apiClient.sendAuthenticated(
        decoder: .api,
        urlSession: networkSession
      ) {
        Path("api", "v1", "account", "profile")
      }.value
    }
  )

  public static var previewValue: AccountClient {
    AccountClient(
      fetchProfile: {
        AccountProfile(
          id: "1",
          email: "user@example.com",
          name: "Test User",
          image: nil,
          emailVerified: true,
          createdAt: Date(timeIntervalSince1970: 0),
          updatedAt: Date(timeIntervalSince1970: 0)
        )
      }
    )
  }

  public static var testValue: AccountClient {
    AccountClient()
  }
}

extension DependencyValues {
  public var accountClient: AccountClient {
    get { self[AccountClient.self] }
    set { self[AccountClient.self] = newValue }
  }
}
