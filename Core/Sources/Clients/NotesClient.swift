import Dependencies
import DependenciesMacros
import Foundation
import SQLiteData

@DependencyClient
public struct NotesClient: Sendable {
  public var fetchAll: @Sendable () async throws -> [Note]
  public var fetch: @Sendable (_ id: UUID) async throws -> Note?
  public var create: @Sendable (_ title: String, _ body: String) async throws -> Note
  public var update: @Sendable (_ note: Note) async throws -> Void
  public var delete: @Sendable (_ id: UUID) async throws -> Void
}

extension NotesClient: DependencyKey {
  public static var liveValue: NotesClient {
    @Dependency(\.defaultDatabase) var database

    return NotesClient(
      fetchAll: {
        try await database.read { db in
          try Note.fetchAll(db)
        }
      },
      fetch: { id in
        try await database.read { db in
          try Note.where { $0.id.eq(id) }.fetchOne(db)
        }
      },
      create: { title, body in
        let note = Note(title: title, body: body)
        try await database.write { db in
          try Note.insert { Note.Draft(note) }.execute(db)
        }
        return note
      },
      update: { note in
        var updated = note
        updated.updatedAt = Date()

        try await database.write { [updated] db in
          try Note.upsert { Note.Draft(updated) }.execute(db)
        }
      },
      delete: { id in
        try await database.write { db in
          try Note.where { $0.id.eq(id) }.delete().execute(db)
        }
      }
    )
  }

  public static var previewValue: NotesClient {
    let notes = LockIsolated<[Note]>([
      Note(title: "Welcome", body: "This is your first note!"),
      Note(title: "Shopping List", body: "- Milk\n- Eggs\n- Bread")
    ])

    return NotesClient(
      fetchAll: { notes.value },
      fetch: { id in notes.value.first { $0.id == id } },
      create: { title, body in
        let note = Note(title: title, body: body)
        notes.withValue { $0.append(note) }
        return note
      },
      update: { note in
        notes.withValue { list in
          if let index = list.firstIndex(where: { $0.id == note.id }) {
            var updated = note
            updated.updatedAt = Date()
            list[index] = updated
          }
        }
      },
      delete: { id in
        notes.withValue { $0.removeAll { $0.id == id } }
      }
    )
  }

  public static var testValue: NotesClient {
    NotesClient()
  }
}

extension DependencyValues {
  public var notesClient: NotesClient {
    get { self[NotesClient.self] }
    set { self[NotesClient.self] = newValue }
  }
}
