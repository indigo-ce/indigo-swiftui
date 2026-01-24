import Foundation

public extension String {
  init?(base64EncodedString: String) {
    guard let data = Data(base64Encoded: base64EncodedString) else {
      return nil
    }

    self.init(data: data, encoding: .utf8)
  }

  var base64EncodedString: String {
    Data(utf8).base64EncodedString()
  }

  var excludeEmpty: String? {
    isEmpty ? nil : self
  }
}
