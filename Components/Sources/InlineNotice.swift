import SwiftUI

/// A compact inline banner for surfacing info, warnings, or errors within a layout.
public struct InlineNotice: View {
  private let message: LocalizedStringKey
  private let icon: String
  private let tint: Color

  public init(
    _ message: LocalizedStringKey,
    icon: String = "info.circle.fill",
    tint: Color = .blue
  ) {
    self.message = message
    self.icon = icon
    self.tint = tint
  }

  public var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: icon)
        .foregroundStyle(tint)
        .font(.body)

      Text(message)
        .font(.callout)
        .foregroundStyle(.primary)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(12)
    .background(tint.opacity(0.12), in: .rect(cornerRadius: 12, style: .continuous))
  }
}

extension InlineNotice {
  /// A warning-styled notice (amber, triangle icon).
  public static func warning(_ message: LocalizedStringKey) -> InlineNotice {
    InlineNotice(message, icon: "exclamationmark.triangle.fill", tint: .orange)
  }

  /// An error-styled notice (red, octagon icon).
  public static func error(_ message: LocalizedStringKey) -> InlineNotice {
    InlineNotice(message, icon: "exclamationmark.octagon.fill", tint: .red)
  }
}

#Preview {
  VStack(spacing: 12) {
    InlineNotice("Your notes sync automatically across devices.")
    InlineNotice.warning("You have unsaved changes.")
    InlineNotice.error("Could not reach the server. Try again.")
  }
  .padding()
}
