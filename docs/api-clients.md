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
.package(url: "https://github.com/kaishin/http-request-client", from: "0.1.0"),
.package(url: "https://github.com/kaishin/jwt-auth-client", from: "0.1.0"),
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
      post(stack, encoder: .shared)
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

Create a `JWTAuthClient+Live.swift` file:

```swift
import Dependencies
import HTTPRequestBuilder
import HTTPRequestClient
import JWTAuth

extension JWTAuthClient: @retroactive DependencyKey {
  public static let liveValue = Self {
    // Return your API base URL
    Configuration.apiHost
  } refresh: { tokens in
    @Dependency(\.httpClient) var httpClient

    // Call your token refresh endpoint
    return try await httpClient.send {
      Path("api", "v1", "auth", "refresh-access")
      post(RefreshToken(tokens.refresh))
    }.value
  }
}
```

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
try await apiClient.sendAuthenticated(decoder: .shared) {
  Path("api", "v1", "stacks")
  post(stack, encoder: .shared)
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
post(item, encoder: .shared)

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

For APIs with custom date formats, create shared coders:

```swift
extension JSONDecoder {
  public static let shared: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let dateString = try container.decode(String.self)

      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

      guard let date = formatter.date(from: dateString) else {
        throw DecodingError.dataCorrupted(
          DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: "Invalid date format: \(dateString)"
          )
        )
      }
      return date
    }
    return decoder
  }()
}

extension JSONEncoder {
  public static let shared: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()
}
```

Use them in requests:

```swift
try await apiClient.sendAuthenticated(decoder: .shared) {
  Path("api", "v1", "items")
  post(item, encoder: .shared)
}.value
```

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
      try await apiClient.sendAuthenticated(decoder: .shared) {
        Path("api", "v1", "stacks")
      }.value
    } createStack: { stack in
      try await apiClient.sendAuthenticated(decoder: .shared) {
        Path("api", "v1", "stacks")
        post(stack, encoder: .shared)
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
