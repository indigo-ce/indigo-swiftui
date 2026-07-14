import SwiftUI

extension View {
  /// Redacts the view and overlays an animated shimmer, for loading placeholders.
  public func placeholderShimmer() -> some View {
    modifier(PlaceholderShimmer())
  }
}

private struct PlaceholderShimmer: ViewModifier {
  @State private var startPoint = UnitPoint(x: -0.7, y: 0)
  @State private var endPoint = UnitPoint(x: 0, y: 0.3)

  private let animation = Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: false)

  func body(content: Content) -> some View {
    content
      .redacted(reason: .placeholder)
      .overlay {
        Rectangle()
          .fill(
            LinearGradient(
              colors: [.white.opacity(0), .white, .white.opacity(0)],
              startPoint: startPoint,
              endPoint: endPoint
            )
          )
          .mask(content.redacted(reason: .placeholder))
          .animation(animation, value: startPoint)
          .onAppear {
            startPoint = UnitPoint(x: 1, y: 0)
            endPoint = UnitPoint(x: 1.7, y: 0.3)
          }
          .flipsForRightToLeftLayoutDirection(true)
      }
      .disabled(true)
      .opacity(0.5)
  }
}

#Preview {
  VStack(alignment: .leading, spacing: 8) {
    Text("A note title")
      .font(.headline)
    Text("Some placeholder body text that is being loaded from the database.")
  }
  .placeholderShimmer()
  .padding()
}
