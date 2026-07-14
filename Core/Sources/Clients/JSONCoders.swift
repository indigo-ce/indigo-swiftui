import Foundation

// Shared JSON coders configured for a typical REST API: snake_case on the wire,
// camelCase in Swift, ISO-8601 dates. Use `.api` everywhere you talk to the
// backend instead of scattering ad-hoc `JSONEncoder()` / `JSONDecoder()` with
// inconsistent strategies. Adjust the strategies to match your API.
extension JSONEncoder {
  public static let api: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()
}

extension JSONDecoder {
  public static let api: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}
