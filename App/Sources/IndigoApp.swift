import ComposableArchitecture
import Core
import Dependencies
import NotesListFeature
import SQLiteData
import SwiftUI

#if DEBUG
  import PulseUI
  #if os(iOS)
    import Components
  #endif
#endif

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

#if DEBUG
  @State private var isConsolePresented = false
#endif

  var body: some Scene {
    WindowGroup {
      NotesListView(store: Self.store)
#if DEBUG
#if os(iOS)
        .fullScreenCover(isPresented: $isConsolePresented) {
          NavigationView {
            ConsoleView()
          }
        }
        .onShake {
          isConsolePresented.toggle()
        }
#endif
#endif
    }
  }
}
