import Foundation

// Shared JSON coders configured for a typical REST API: keys pass through
// verbatim (sent as declared in Swift), ISO-8601 dates. Use `.api` everywhere
// you talk to the backend instead of scattering ad-hoc `JSONEncoder()` /
// `JSONDecoder()` with inconsistent strategies. Adjust the key and date
// strategies to match your API.
extension JSONEncoder {
  public static let api: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()
}

extension JSONDecoder {
  public static let api: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let dateString = try container.decode(String.self)

      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

      if let date = formatter.date(from: dateString) {
        return date
      }

      // Fallback without fractional seconds
      formatter.formatOptions = [.withInternetDateTime]
      if let date = formatter.date(from: dateString) {
        return date
      }

      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Invalid date format: \(dateString)"
        )
      )
    }
    return decoder
  }()
}
