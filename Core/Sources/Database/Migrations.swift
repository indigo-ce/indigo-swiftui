import SQLiteData

func v1(on database: Database) throws {
  try #sql(
    """
    CREATE TABLE "notes" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      "title" TEXT NOT NULL,
      "body" TEXT NOT NULL DEFAULT '',
      "createdAt" TEXT NOT NULL,
      "updatedAt" TEXT
    ) STRICT
    """
  )
  .execute(database)
}
