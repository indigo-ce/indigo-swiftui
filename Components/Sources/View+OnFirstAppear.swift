import SwiftUI

extension View {
  /// Runs `action` exactly once, the first time the view appears.
  public func once(_ action: @escaping () -> Void) -> some View {
    modifier(OnceViewModifier(action: action))
  }
}

private struct OnceViewModifier: ViewModifier {
  @State private var hasAppeared = false

  let action: () -> Void

  func body(content: Content) -> some View {
    content.onAppear {
      guard !hasAppeared else { return }
      hasAppeared = true
      action()
    }
  }
}
