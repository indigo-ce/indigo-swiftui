import Dependencies
import Foundation
import Pulse

// The single `URLSession` every client in `Core` sends through. It is declared
// as a dependency rather than a global so the app gets one immutable session
// while tests override it through `withDependencies` — the same override seam
// the rest of the codebase uses.
//
// Every client under `Core/Sources/Clients` should pass
// `urlSession: networkSession` on its `HTTPRequestClient` calls so DEBUG builds
// capture all traffic in the shipped network console: only requests made on the
// `URLSessionProxy` session reach it.
public enum NetworkSessionKey: DependencyKey {
  public static let liveValue: any URLSessionProtocol = {
    #if DEBUG
      return URLSessionProxy(configuration: .default)
    #else
      return URLSession(configuration: .default)
    #endif
  }()

  // No `testValue`: the library default reports an issue when a test reaches
  // the session without overriding it, which is the behavior we want.
}

extension DependencyValues {
  public var networkSession: any URLSessionProtocol {
    get { self[NetworkSessionKey.self] }
    set { self[NetworkSessionKey.self] = newValue }
  }
}
