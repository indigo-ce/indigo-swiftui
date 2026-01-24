import ComposableArchitecture
import Core
import Foundation
import NoteEditorFeature
import SwiftUI

// MARK: - Feature

@Reducer
public struct NotesListFeature: Sendable {
  @ObservableState
  public struct State: Equatable {
    public var notes: [Note] = []
    public var isLoading = false
    public var errorMessage: String?
    @Presents public var editor: NoteEditorFeature.State?

    public init() {}
  }

  public enum Action: Sendable {
    case onAppear
    case notesLoaded(Result<[Note], Error>)
    case addNoteButtonTapped
    case noteSelected(Note)
    case deleteNotes(IndexSet)
    case deleteCompleted(Result<Void, Error>)
    case editor(PresentationAction<NoteEditorFeature.Action>)
  }

  @Dependency(\.notesClient) var notesClient

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .onAppear:
        state.isLoading = true
        return .run { send in
          await send(.notesLoaded(Result { try await notesClient.fetchAll() }))
        }

      case .notesLoaded(.success(let notes)):
        state.isLoading = false
        state.notes = notes.sorted { $0.createdAt > $1.createdAt }
        return .none

      case .notesLoaded(.failure(let error)):
        state.isLoading = false
        state.errorMessage = error.localizedDescription
        return .none

      case .addNoteButtonTapped:
        state.editor = NoteEditorFeature.State(mode: .create)
        return .none

      case .noteSelected(let note):
        state.editor = NoteEditorFeature.State(mode: .edit(note))
        return .none

      case .deleteNotes(let indexSet):
        let notesToDelete = indexSet.map { state.notes[$0] }
        return .run { send in
          for note in notesToDelete {
            try await notesClient.delete(note.id)
          }
          await send(.deleteCompleted(.success(())))
        } catch: { error, send in
          await send(.deleteCompleted(.failure(error)))
        }

      case .deleteCompleted(.success):
        return .send(.onAppear)

      case .deleteCompleted(.failure(let error)):
        state.errorMessage = error.localizedDescription
        return .none

      case .editor(.presented(.saveCompleted(.success))):
        state.editor = nil
        return .send(.onAppear)

      case .editor(.presented(.deleteCompleted(.success))):
        state.editor = nil
        return .send(.onAppear)

      case .editor(.dismiss):
        state.editor = nil
        return .none

      case .editor:
        return .none
      }
    }
    .ifLet(\.$editor, action: \.editor) {
      NoteEditorFeature()
    }
  }
}

// MARK: - View

public struct NotesListView: View {
  @Bindable var store: StoreOf<NotesListFeature>

  public init(store: StoreOf<NotesListFeature>) {
    self.store = store
  }

  public var body: some View {
    NavigationStack {
      Group {
        if store.isLoading {
          ProgressView("Loading notes...")
        } else if store.notes.isEmpty {
          ContentUnavailableView(
            "No Notes",
            systemImage: "note.text",
            description: Text("Tap the + button to create your first note.")
          )
        } else {
          List {
            ForEach(store.notes) { note in
              NoteRow(note: note)
                .contentShape(Rectangle())
                .onTapGesture {
                  store.send(.noteSelected(note))
                }
            }
            .onDelete { indexSet in
              store.send(.deleteNotes(indexSet))
            }
          }
        }
      }
      .navigationTitle("Notes")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            store.send(.addNoteButtonTapped)
          } label: {
            Image(systemName: "plus")
          }
        }
      }
      .sheet(item: $store.scope(state: \.editor, action: \.editor)) { editorStore in
        NavigationStack {
          NoteEditorView(store: editorStore)
        }
      }
      .alert("Error", isPresented: .constant(store.errorMessage != nil)) {
        Button("OK") {}
      } message: {
        Text(store.errorMessage ?? "")
      }
    }
    .task {
      store.send(.onAppear)
    }
  }
}

// MARK: - Supporting Views

struct NoteRow: View {
  let note: Note

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(note.title)
        .font(.headline)
        .lineLimit(1)

      if !note.body.isEmpty {
        Text(note.body)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Text(note.createdAt, style: .date)
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 4)
  }
}

// MARK: - Previews

#Preview {
  NotesListView(
    store: Store(initialState: NotesListFeature.State()) {
      NotesListFeature()
    } withDependencies: {
      $0.notesClient = .previewValue
    }
  )
}
