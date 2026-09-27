import SQLiteData
import Testing

@testable import Core

@Suite
struct UserCacheResetTests {
  /// Under a test context `appDatabase()` hands each test its own temp file,
  /// so the two seeded rows cannot leak between suites.
  @Test func clearUserCacheEmptiesEveryUserScopedTable() async throws {
    let database = try appDatabase()

    try await database.write { db in
      try Note.insert { Note.Draft(Note(title: "First")) }.execute(db)
      try Note.insert { Note.Draft(Note(title: "Second")) }.execute(db)
    }

    try await clearUserCache(database)

    let remaining = try await database.read { try Note.fetchAll($0) }
    #expect(remaining.isEmpty)
  }
}
