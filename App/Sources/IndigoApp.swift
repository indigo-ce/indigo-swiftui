import ComposableArchitecture
import Core
import Dependencies
import NotesListFeature
import SQLiteData
import SwiftUI

@main
struct IndigoApp: App {
  static let store = Store(initialState: NotesListFeature.State()) {
    NotesListFeature()
  }

  init() {
    prepareDependencies {
      $0.defaultDatabase = try! appDatabase()
    }
  }

  var body: some Scene {
    WindowGroup {
      NotesListView(store: Self.store)
    }
  }
}
