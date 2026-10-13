import SwiftUI

/// A compact inline banner for surfacing info, warnings, or errors within a layout.
public struct InlineNotice: View {
  private let message: Text
  private let icon: String
  private let tint: Color

  public init(
    _ message: LocalizedStringKey,
    icon: String = "info.circle.fill",
    tint: Color = .blue
  ) {
    self.message = Text(message)
    self.icon = icon
    self.tint = tint
  }

  /// Creates a notice whose message is rendered verbatim, without a
  /// localization-table lookup. Use this for dynamic strings — server messages,
  /// error text — that must not be reinterpreted as localization keys.
  private init(
    verbatim message: String,
    icon: String,
    tint: Color
  ) {
    self.message = Text(verbatim: message)
    self.icon = icon
    self.tint = tint
  }

  public var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: icon)
        .foregroundStyle(tint)
        .font(.body)

      message
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

  /// An error-styled notice (red, octagon icon) whose message is rendered
  /// verbatim. Use this for dynamic error text, such as a server response.
  public static func error(verbatim message: String) -> InlineNotice {
    InlineNotice(verbatim: message, icon: "exclamationmark.octagon.fill", tint: .red)
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
