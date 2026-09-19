# API Clients Guide

## Introduction

This guide covers how to build API clients that integrate with The Composable Architecture (TCA) using `HTTPRequestClient` and `HTTPRequestBuilder`. The patterns described here provide type-safe, testable, and composable networking.

```swift
@Dependency(\.apiEndpointClient) var apiClient

let stacks = try await apiClient.getStacks()
```

Key advantages:

- **TCA Integration**: First-class support for dependency injection and testing
- **Functional Request Building**: Declarative, composable request construction
- **JWT Authentication**: Built-in token refresh handling
- **Preview/Test Support**: Automatic mock generation via macros

## Dependencies

Add these packages to your project:

```swift
.package(url: "https://github.com/indigo-ce/http-request-client", from: "1.6.0"),
.package(url: "https://github.com/indigo-ce/jwt-auth-client", from: "2.0.0"),
```

Import them in your client files:

```swift
import Dependencies
import DependenciesMacros
import HTTPRequestBuilder
import HTTPRequestClient
import JWTAuth
```

## Basic Structure

Every API client follows this structure:

```swift
@DependencyClient
public struct MyAPIClient: Sendable {
  // Endpoint closures
  public var getItems: @Sendable () async throws -> [Item]
  public var createItem: @Sendable (_ item: Item) async throws -> Item
}

extension MyAPIClient: DependencyKey {
  public static let liveValue = { () -> Self in
    @Dependency(\.apiClient) var apiClient

    return Self {
      // Implementation
    } createItem: { item in
      // Implementation
    }
  }()
}

extension DependencyValues {
  public var myAPIClient: MyAPIClient {
    get { self[MyAPIClient.self] }
    set { self[MyAPIClient.self] = newValue }
  }
}
```

The `@DependencyClient` macro automatically generates `previewValue` and `testValue` with unimplemented closures, so you don't need to define them manually unless you want custom mock data.

## Client Organization

### Single Client (Recommended for Small APIs)

For apps with a limited number of endpoints, a single client keeps things simple:

```swift
@DependencyClient
public struct APIEndpointClient: Sendable {
  public var signIn: @Sendable (_ with: SignInPayload) async throws -> Token
  public var signOut: @Sendable (_ sessionId: String) async throws -> EmptyResponse
  public var getStacks: @Sendable () async throws -> [Stack]
  public var createStack: @Sendable (_ stack: CreateStack) async throws -> Stack
  public var getTiles: @Sendable (_ stackID: UUID) async throws -> [Tile]
}
```

**Pros:**

- Single import and dependency
- Easy to discover all available endpoints
- Less boilerplate

**Cons:**

- Can become unwieldy with many endpoints
- Harder to test individual domains in isolation

### Multiple Domain Clients (Recommended for Large APIs)

For larger APIs, split clients by domain:

```swift
// AuthAPIClient.swift
@DependencyClient
public struct AuthAPIClient: Sendable {
  public var signIn: @Sendable (_ payload: SignInPayload) async throws -> Token
  public var signOut: @Sendable () async throws -> EmptyResponse
  public var refreshToken: @Sendable () async throws -> Token
}

// GamesAPIClient.swift
@DependencyClient
public struct GamesAPIClient: Sendable {
  public var getPaginated: @Sendable (_ page: Int) async throws -> Paginated<Game>
  public var find: @Sendable (_ id: UUID) async throws -> Game
  public var search: @Sendable (_ query: String) async throws -> [Game]
}

// UserProfileAPIClient.swift
@DependencyClient
public struct UserProfileAPIClient: Sendable {
  public var get: @Sendable () async throws -> UserProfile
  public var update: @Sendable (_ profile: UserProfile) async throws -> UserProfile
}
```

**Pros:**

- Clear separation of concerns
- Easier to test individual domains
- Better code organization for large teams

**Cons:**

- More files and boilerplate
- Multiple dependencies to inject

## Endpoint Path Styles

### Inline Paths (Recommended for Most Cases)

Define paths directly in the request builder:

```swift
public static let liveValue = { () -> Self in
  @Dependency(\.apiClient) var apiClient

  return Self {
    try await apiClient.sendAuthenticated {
      Path("api", "v1", "stacks")
    }.value
  } createStack: { stack in
    try await apiClient.sendAuthenticated {
      Path("api", "v1", "stacks")
      post(stack, encoder: .api)
    }.value
  } getTiles: { stackID in
    try await apiClient.sendAuthenticated {
      Path("api", "v1", "stacks", stackID.uuidString.lowercased(), "tiles")
    }.value
  }
}()
```

**Pros:**

- Paths visible at call site
- No additional abstraction layer
- Easy to understand

### Pre-defined Endpoint Extensions (For Complex APIs)

Define endpoints as extensions on a marker type:

```swift
// Endpoints.swift
public enum APIEndpoint {}

extension APIEndpoint {
  static var games: RequestMiddleware {
    Path("games")
  }

  static func game(with id: UUID) -> RequestMiddleware {
    Path("games", id.uuidString.lowercased())
  }

  static var upcomingGames: RequestMiddleware {
    Path("games", "upcoming")
  }
}

extension RequestMiddleware {
  func apiVersion(_ version: APIVersion) -> RequestMiddleware {
    Path("api", version.rawValue) + self
  }
}
```

Then use them in clients:

```swift
return Self { page in
  try await apiClient.send {
    .gamesPaginated(page: page).apiVersion(.v1)
    clientKeyRequest()
  }.value
} find: { id in
  try await apiClient.send {
    .game(with: id).apiVersion(.v1)
    clientKeyRequest()
  }.value
}
```

**Pros:**

- Reusable endpoint definitions
- Centralized path management
- Cleaner client code

**Cons:**

- Additional indirection
- Need to look up endpoint definitions

## Authentication

### Setting Up JWT Authentication

The template ships this wiring in `Core/Sources/Clients/JWTAuthClient+Live.swift` — copy it and adjust `host`, the refresh endpoint path, and the request/response models to match your backend:

```swift
import Dependencies
import Foundation
import HTTPRequestBuilder
import HTTPRequestClient
import JWTAuth

extension JWTAuthClient: @retroactive DependencyKey {
  public static let host = "https://api.example.com"

  public static let liveValue = Self(
    baseURL: { host },
    refresh: { tokens in
      @Dependency(\.httpRequestClient) var httpClient

      do {
        let response: SuccessResponse<TokenResponse> = try await httpClient.send(
          baseURL: host,
          decoder: .api
        ) {
          Path("api", "v1", "auth", "refresh-access")
          post(RefreshTokenRequest(refreshToken: tokens.refresh), encoder: .api)
        }
        return AuthTokens(
          access: response.value.accessToken,
          refresh: response.value.refreshToken
        )
      } catch let error as HTTPRequestClient.Error {
        // Only a 401 means the refresh token was rejected: surface
        // `refreshRejected` so stored credentials are wiped and the user
        // re-authenticates. Every other failure (timeout, offline, 5xx,
        // decoding error) is transient, so rethrow it untouched and keep the
        // tokens for a later retry — mapping those to `refreshRejected` would
        // log the user out on a momentary network blip.
        if case .badResponse(_, 401, _) = error {
          throw AuthTokens.Error.refreshRejected
        }
        throw error
      }
    }
  )
}
```

`RefreshTokenRequest` and `TokenResponse` are declared alongside the live value; rename their fields to match your API. Keys are sent as declared — the date and key strategies in `JSONCoders.api` are the thing to adjust per backend.

Create an alias for convenience:

```swift
extension DependencyValues {
  public var apiClient: JWTAuthClient {
    jwtAuthClient
  }
}
```

### Making Authenticated Requests

Use `sendAuthenticated` for endpoints that require authentication:

```swift
// Authenticated request - automatically includes JWT and handles refresh
try await apiClient.sendAuthenticated {
  Path("api", "v1", "user", "profile")
}.value

// With custom decoder
try await apiClient.sendAuthenticated(decoder: .api) {
  Path("api", "v1", "stacks")
  post(stack, encoder: .api)
}.value
```

The `sendAuthenticated` method:

1. Retrieves the current access token from storage
2. Adds the `Authorization: Bearer <token>` header
3. If the request fails with 401, automatically refreshes the token
4. Retries the original request with the new token

### Unauthenticated Requests

For public endpoints (sign-in, sign-up, public data):

```swift
// Basic request without auth
try await apiClient.send {
  Path("api", "v1", "games")
}.value

// With basic auth for sign-in
try await apiClient.send {
  Path("api", "v1", "auth", "sign-in")
  basicAuth(username: email, password: password)
}.value
```

## Request Building

### HTTP Methods

```swift
// GET (default)
Path("api", "v1", "items")

// POST with body
Path("api", "v1", "items")
post(item)

// POST with custom encoder
Path("api", "v1", "items")
post(item, encoder: .api)

// PUT
Path("api", "v1", "items", itemId)
put(item)

// DELETE
Path("api", "v1", "items", itemId)
method(.delete)
```

### Query Parameters

```swift
Path("api", "v1", "search")
queries(["q": searchTerm, "page": "\(page)"])
```

### Custom Headers

```swift
Path("api", "v1", "data")
header("X-Custom-Header", "value")
```

## JSON Encoding/Decoding

The template ships ready-made coders in `Core/Sources/Clients/JSONCoders.swift`: `JSONEncoder.api` and `JSONDecoder.api`. Keys pass through verbatim (sent as declared in Swift) and dates use ISO-8601 — the decoder additionally tolerates fractional seconds on the way in. Use `.api` everywhere you talk to the backend instead of scattering ad-hoc `JSONEncoder()` / `JSONDecoder()` instances, and adjust the strategies in `JSONCoders.swift` to match your API.

Use them in requests:

```swift
try await apiClient.sendAuthenticated(decoder: .api) {
  Path("api", "v1", "items")
  post(item, encoder: .api)
}.value
```

### Surfacing server errors

Non-2xx responses arrive as `HTTPRequestClient.Error.badResponse` carrying the raw body string. Decode it with `APIErrorBody` from `Core/Sources/Clients/APIErrorBody.swift`:

```swift
do {
  try await apiClient.sendAuthenticated {
    Path("api", "v1", "items")
  }.value
} catch {
  if let body = APIErrorBody.from(error) {
    // `error` is a human-readable server message for display or logging;
    // `code` is a stable machine-readable identifier that only some
    // endpoints send, so fall back to the message when it is nil.
  }
  throw error
}
```

`APIErrorBody.from` returns `nil` for errors that are not `badResponse` and for bodies that fail to decode. Neither field is promised to be localized — that depends on the backend.

## Configuration

### Environment-Based Host

```swift
extension APIEndpointClient {
  #if DEBUG
    public static let webHost = "http://localhost:4321"
  #else
    public static let webHost = "https://api.myapp.com"
  #endif
}
```

Or use a configuration object:

```swift
public enum Configuration {
  public static var current: Environment = .development

  public enum Environment {
    case development
    case production

    var apiHost: String {
      switch self {
      case .development: return "http://localhost:4321"
      case .production: return "https://api.myapp.com"
      }
    }
  }
}
```

## Testing

### Using in Reducers

```swift
@Reducer
struct StacksFeature {
  @Dependency(\.apiEndpointClient) var apiClient

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .loadStacks:
        return .run { send in
          let stacks = try await apiClient.getStacks()
          await send(.stacksLoaded(stacks))
        }
      }
    }
  }
}
```

### Writing Tests

```swift
@Test
func loadStacks() async {
  let store = TestStore(initialState: StacksFeature.State()) {
    StacksFeature()
  } withDependencies: {
    $0.apiEndpointClient.getStacks = { [.mock] }
  }

  await store.send(.loadStacks)
  await store.receive(.stacksLoaded([.mock])) {
    $0.stacks = [.mock]
  }
}
```

### Custom Preview Values

If you need richer mock data for previews, implement `TestDependencyKey`:

```swift
extension MyAPIClient: TestDependencyKey {
  public static let previewValue = Self(
    getItems: { MockData.items },
    createItem: { item in item }
  )

  public static let testValue = Self()
}
```

## Complete Example

Here's a complete single-client implementation:

```swift
import Dependencies
import DependenciesMacros
import Foundation
import HTTPRequestBuilder
import HTTPRequestClient

@DependencyClient
public struct APIEndpointClient: Sendable {
  public var signIn: @Sendable (_ with: SignInPayload) async throws -> Token
  public var getStacks: @Sendable () async throws -> [Stack]
  public var createStack: @Sendable (_ stack: CreateStack) async throws -> Stack
}

public enum APIClientError: Error {
  case invalidResponse
}

extension APIEndpointClient: DependencyKey {
  #if DEBUG
    public static let webHost = "http://localhost:4321"
  #else
    public static let webHost = "https://api.myapp.com"
  #endif

  public static let liveValue = { () -> Self in
    @Dependency(\.apiClient) var apiClient

    return Self { payload in
      try await apiClient.send {
        Path("api", "v1", "auth", "sign-in")
        basicAuth(username: payload.email, password: payload.password)
      }.value
    } getStacks: {
      try await apiClient.sendAuthenticated(decoder: .api) {
        Path("api", "v1", "stacks")
      }.value
    } createStack: { stack in
      try await apiClient.sendAuthenticated(decoder: .api) {
        Path("api", "v1", "stacks")
        post(stack, encoder: .api)
      }.value
    }
  }()
}

extension DependencyValues {
  public var apiEndpointClient: APIEndpointClient {
    get { self[APIEndpointClient.self] }
    set { self[APIEndpointClient.self] = newValue }
  }
}
```
