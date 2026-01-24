import ComposableArchitecture
import Core
import Foundation

@Reducer
public struct NoteEditorFeature: Sendable {
  public enum Mode: Equatable, Sendable {
    case create
    case edit(Note)

    var note: Note? {
      switch self {
      case .create: nil
      case .edit(let note): note
      }
    }

    var isEditing: Bool {
      if case .edit = self { return true }
      return false
    }
  }

  @ObservableState
  public struct State: Equatable {
    var mode: Mode
    var title: String
    var body: String
    var isSaving = false
    var errorMessage: String?

    public init(mode: Mode) {
      self.mode = mode
      self.title = mode.note?.title ?? ""
      self.body = mode.note?.body ?? ""
    }
  }

  public enum Action: BindableAction, Sendable {
    case binding(BindingAction<State>)
    case saveButtonTapped
    case deleteButtonTapped
    case cancelButtonTapped
    case saveCompleted(Result<Void, Error>)
    case deleteCompleted(Result<Void, Error>)
  }

  @Dependency(\.notesClient) var notesClient
  @Dependency(\.dismiss) var dismiss

  public init() {}

  public var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        return .none

      case .saveButtonTapped:
        state.isSaving = true
        let title = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = state.body

        return .run { [mode = state.mode] send in
          switch mode {
          case .create:
            _ = try await notesClient.create(title, body)
          case .edit(var note):
            note.title = title
            note.body = body
            try await notesClient.update(note)
          }
          await send(.saveCompleted(.success(())))
        } catch: { error, send in
          await send(.saveCompleted(.failure(error)))
        }

      case .deleteButtonTapped:
        guard case .edit(let note) = state.mode else { return .none }
        state.isSaving = true

        return .run { send in
          try await notesClient.delete(note.id)
          await send(.deleteCompleted(.success(())))
        } catch: { error, send in
          await send(.deleteCompleted(.failure(error)))
        }

      case .cancelButtonTapped:
        return .run { _ in
          await dismiss()
        }

      case .saveCompleted(.success):
        state.isSaving = false
        return .none

      case .saveCompleted(.failure(let error)):
        state.isSaving = false
        state.errorMessage = error.localizedDescription
        return .none

      case .deleteCompleted(.success):
        state.isSaving = false
        return .none

      case .deleteCompleted(.failure(let error)):
        state.isSaving = false
        state.errorMessage = error.localizedDescription
        return .none
      }
    }
  }
}
