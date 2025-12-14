import Core
import SwiftUI

public struct ContentView: View {
  public init() {}

  public var body: some View {
    VStack {
      Text("Hello World!")
        .padding()

      Text(verbatim: Bundle.main.fullVersionString ?? "")
        .padding()
    }
  }
}

#Preview {
  ContentView()
}
