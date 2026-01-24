import Dependencies
import Foundation
import Logging
import OSLog
import SQLiteData

private let logger = Logger(subsystem: "Indigo", category: "Database")

public func appDatabase() throws -> any DatabaseWriter {
  @Dependency(\.context) var context

  let database: any DatabaseWriter
  var configuration = Configuration()

  configuration.foreignKeysEnabled = true

  configuration.prepareDatabase { db in
    #if DEBUG
      db.trace(options: .profile) {
        if context == .live {
          logger.debug("\($0.expandedDescription)")
        } else {
          print("\($0.expandedDescription)")
        }
      }
    #endif
  }

  if context == .preview {
    database = try DatabaseQueue(configuration: configuration)
  } else {
    let path =
      context == .live
      ? URL.documentsDirectory.appending(component: "db.sqlite").path()
      : URL.temporaryDirectory.appending(component: "\(UUID().uuidString)-db.sqlite").path()
    logger.info("Open \(path)")
    database = try DatabasePool(path: path, configuration: configuration)
  }

  try DatabaseMigrator.baseMigrator.migrate(database)
  return database
}

extension DatabaseMigrator {
  static var baseMigrator: Self {
    var migrator = DatabaseMigrator()

    #if DEBUG
      migrator.eraseDatabaseOnSchemaChange = true
    #endif

    migrator.registerV1Migration()
    return migrator
  }

  mutating func registerV1Migration() {
    registerMigration(.v1) { db in
      try v1(on: db)
      logger.info("Migrated to version \(String.v1)")
    }
  }
}

extension String {
  static let v1 = "v1"
}
