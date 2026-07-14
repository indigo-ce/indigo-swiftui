import SwiftUI

/// An image constrained to a square side length, scaled to fit.
public struct ScaledImage: View {
  private let image: Image
  private let side: CGFloat

  public init(_ image: Image, side: CGFloat) {
    self.image = image
    self.side = side
  }

  public var body: some View {
    image
      .resizable()
      .aspectRatio(contentMode: .fit)
      .frame(width: side, height: side)
  }
}

#Preview {
  ScaledImage(Image(systemName: "note.text"), side: 44)
    .padding()
}
