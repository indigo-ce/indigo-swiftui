import Foundation

extension Bundle {
  public var releaseVersionNumber: String? {
    return infoDictionary?["CFBundleShortVersionString"] as? String
  }

  public var buildVersionNumber: String? {
    return infoDictionary?["CFBundleVersion"] as? String
  }

  public var fullVersionString: String? {
    guard
      let releaseVersionNumber,
      let buildVersionNumber
    else {
      return nil
    }

    return "\(releaseVersionNumber) (\(buildVersionNumber))"
  }
}

extension Bundle {
  public static var core: Bundle {
    Bundle(for: BundleToken.self)
  }
}

private final class BundleToken {}
