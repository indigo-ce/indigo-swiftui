import Foundation
import Testing

@testable import Core

private struct CamelCasePayload: Codable, Equatable {
  let refreshToken: String
  let accessToken: String
}

private struct DatedPayload: Codable, Equatable {
  let createdAt: Date
}

@Suite struct JSONCodersTests {
  @Test func encodesKeysAsDeclared() throws {
    let payload = CamelCasePayload(refreshToken: "refresh", accessToken: "access")
    let data = try JSONEncoder.api.encode(payload)
    let json = try #require(String(data: data, encoding: .utf8))
    #expect(json.contains("refreshToken"))
    #expect(json.contains("accessToken"))
    #expect(!json.contains("refresh_token"))
    #expect(!json.contains("access_token"))
  }

  @Test func decodesKeysAsDeclared() throws {
    let json = #"{"accessToken":"access","refreshToken":"refresh"}"#
    let payload = try JSONDecoder.api.decode(
      CamelCasePayload.self,
      from: Data(json.utf8)
    )
    #expect(payload == CamelCasePayload(refreshToken: "refresh", accessToken: "access"))
  }

  @Test func decodesDateWithoutFractionalSeconds() throws {
    let json = #"{"createdAt":"2026-09-18T12:00:00Z"}"#
    let payload = try JSONDecoder.api.decode(
      DatedPayload.self,
      from: Data(json.utf8)
    )
    #expect(payload.createdAt.timeIntervalSince1970 > 0)
  }

  @Test func decodesDateWithFractionalSeconds() throws {
    let json = #"{"createdAt":"2026-09-18T12:00:00.123Z"}"#
    let payload = try JSONDecoder.api.decode(
      DatedPayload.self,
      from: Data(json.utf8)
    )
    #expect(payload.createdAt.timeIntervalSince1970 > 0)
  }

  @Test func encodedDateRoundTrips() throws {
    let payload = DatedPayload(createdAt: Date(timeIntervalSince1970: 1_758_190_800))
    let decoded = try JSONDecoder.api.decode(
      DatedPayload.self,
      from: try JSONEncoder.api.encode(payload)
    )
    #expect(decoded == payload)
  }

  @Test func malformedDateStringThrows() {
    let json = #"{"createdAt":"not-a-date"}"#
    #expect(throws: DecodingError.self) {
      try JSONDecoder.api.decode(DatedPayload.self, from: Data(json.utf8))
    }
  }
}
