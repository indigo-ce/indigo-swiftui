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
    case dismissError
    case editor(PresentationAction<NoteEditorFeature.Action>)
    case delegate(Delegate)

    /// Out-of-feature events. The list stays unaware of auth; the root
    /// feature owns the account presentations and decides what a tap means
    /// based on the session it already observes.
    @CasePathable
    public enum Delegate: Sendable {
      case accountButtonTapped
    }
  }

  /// Identifies the in-flight notes fetch so the root feature can cancel it
  /// when it wipes the user cache (and so overlapping refetches collapse to
  /// the latest one via `cancelInFlight`).
  public enum CancelID: Hashable, Sendable {
    case fetch
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
        .cancellable(id: CancelID.fetch, cancelInFlight: true)

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

      case .dismissError:
        state.errorMessage = nil
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

      case .delegate:
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
        // `.navigation` is the leading placement that is valid on both iOS
        // and macOS. It only reports the tap; `RootFeature` presents the
        // sign-in sheet or the sign-out confirmation.
        ToolbarItem(placement: .navigation) {
          Button {
            store.send(.delegate(.accountButtonTapped))
          } label: {
            Image(systemName: "person.crop.circle")
          }
          .accessibilityLabel("Account")
        }
      }
      .sheet(item: $store.scope(state: \.editor, action: \.editor)) { editorStore in
        NavigationStack {
          NoteEditorView(store: editorStore)
        }
      }
      .alert(
        "Error",
        isPresented: Binding(
          get: { store.errorMessage != nil },
          set: { if !$0 { store.send(.dismissError) } }
        )
      ) {
        Button("OK") {
          store.send(.dismissError)
        }
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
