#if os(iOS)
  import SwiftUI
  import UIKit

  extension UIDevice {
    static let deviceDidShakeNotification = Notification.Name("deviceDidShakeNotification")
  }

  extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
      super.motionEnded(motion, with: event)
      if motion == .motionShake {
        NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
      }
    }
  }

  extension View {
    /// Runs `action` when the device is shaken.
    public func onShake(_ action: @escaping () -> Void) -> some View {
      modifier(ShakeViewModifier(action: action))
    }
  }

  private struct ShakeViewModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
      content.onReceive(
        NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)
      ) { _ in
        action()
      }
    }
  }
#endif
