import SwiftUI

/// A small, tinted, capsule-ish tag label.
public struct TagLabelView: View {
  private let title: String
  private let color: Color

  public init(_ title: String, color: Color = .blue) {
    self.title = title
    self.color = color
  }

  public var body: some View {
    Text(title)
      .font(.footnote.weight(.medium))
      .foregroundStyle(color)
      .padding(.vertical, 4)
      .padding(.horizontal, 8)
      .background(color.opacity(0.1), in: .rect(cornerRadius: 6, style: .continuous))
  }
}

#Preview {
  HFlow {
    TagLabelView("SwiftUI")
    TagLabelView("Draft", color: .orange)
    TagLabelView("Archived", color: .gray)
  }
  .padding()
}
