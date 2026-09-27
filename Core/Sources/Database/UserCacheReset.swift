import Foundation
import SQLiteData

/// Clears every user-scoped cached table. Call when the signed-in user
/// changes or the session ends.
///
/// When you add a user-scoped table, add its delete here — this is the one
/// place the app tears down per-account data.
public func clearUserCache(_ writer: any DatabaseWriter) async throws {
  try await writer.write { db in
    try Note.delete().execute(db)
  }
}
