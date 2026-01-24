import Foundation
import SQLiteData

@Table
public struct Note: Identifiable, Codable, Hashable, Sendable {
  public let id: UUID
  public var title: String
  public var body: String
  public let createdAt: Date
  public var updatedAt: Date?

  public init(
    id: UUID = UUID(),
    title: String,
    body: String = "",
    createdAt: Date = Date(),
    updatedAt: Date? = nil
  ) {
    self.id = id
    self.title = title
    self.body = body
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  enum CodingKeys: String, CodingKey {
    case id
    case title
    case body
    case createdAt
    case updatedAt
  }
}

extension Note.Draft: Decodable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: Note.CodingKeys.self)
    self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    self.title = try container.decode(String.self, forKey: .title)
    self.body = try container.decode(String.self, forKey: .body)
    self.createdAt = try container.decode(Date.self, forKey: .createdAt)
    self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
  }
}
