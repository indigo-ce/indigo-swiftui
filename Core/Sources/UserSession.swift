import Foundation
import SwiftSharing

public enum AppState: Equatable, Sendable {
  case loading
  case ready
  case error(String)
}

extension SharedKey where Self == InMemoryKey<AppState>.Default {
  public static var appState: Self {
    Self[.inMemory("appState"), default: .loading]
  }
}
