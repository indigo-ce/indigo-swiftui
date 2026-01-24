import ComposableArchitecture
import Core
import Foundation

@Reducer
public struct NotesListFeature: Sendable {
  @ObservableState
  public struct State: Equatable {
    var notes: [Note] = []
    var isLoading = false
    var errorMessage: String?
    @Presents var editor: NoteEditorFeature.State?

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
