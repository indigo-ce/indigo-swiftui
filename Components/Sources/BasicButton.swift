import SwiftUI

/// A minimal example component: a filled, rounded action button.
///
/// Kept as the simplest possible `Components` example. For app buttons prefer
/// the styles in `ButtonStyles` (`glassButtonStyle()`, `primaryCTA()`).
public struct BasicButton: View {
  public let title: String
  public let action: () -> Void

  public init(title: String, action: @escaping () -> Void) {
    self.title = title
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      Text(title)
        .font(.headline)
        .foregroundStyle(.white)
        .padding()
        .background(.tint, in: .rect(cornerRadius: 8, style: .continuous))
    }
  }
}

#Preview {
  BasicButton(title: "Sample Button") {}
}
