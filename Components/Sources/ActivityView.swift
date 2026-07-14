#if canImport(UIKit)
  import SwiftUI

  /// A SwiftUI wrapper around `UIActivityViewController` (the system share sheet).
  public struct ActivityView: UIViewControllerRepresentable {
    private let activityItems: [Any]

    public init(items: [Any]) {
      self.activityItems = items
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
      UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    public func updateUIViewController(
      _ uiViewController: UIActivityViewController,
      context: Context
    ) {}
  }
#endif
