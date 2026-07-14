import SwiftUI

extension View {
  /// Liquid Glass button style with a graceful fallback on pre-26 platforms.
  @ViewBuilder
  public func glassButtonStyle() -> some View {
    if #available(iOS 26.0, macOS 26.0, *) {
      buttonStyle(.glass)
    } else {
      buttonStyle(.bordered)
    }
  }

  /// Prominent Liquid Glass button style with a graceful fallback on pre-26 platforms.
  @ViewBuilder
  public func glassProminentButtonStyle() -> some View {
    if #available(iOS 26.0, macOS 26.0, *) {
      buttonStyle(.glassProminent)
    } else {
      buttonStyle(.borderedProminent)
    }
  }

  /// Primary call-to-action styling: prominent, large, capsule, accent-tinted.
  public func primaryCTA() -> some View {
    glassProminentButtonStyle()
      .controlSize(.large)
      .buttonBorderShape(.capsule)
      .tint(.accentColor)
      .font(.title3.weight(.semibold))
  }
}

#Preview {
  VStack(spacing: 16) {
    Button("Glass") {}
      .glassButtonStyle()

    Button("Prominent") {}
      .glassProminentButtonStyle()

    Button("Continue") {}
      .primaryCTA()
  }
  .padding()
}
