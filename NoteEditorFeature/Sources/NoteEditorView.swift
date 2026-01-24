import ComposableArchitecture
import Core
import Foundation
import SwiftUI

// MARK: - Feature

@Reducer
public struct NoteEditorFeature: Sendable {
  public enum Mode: Equatable, Sendable {
    case create
    case edit(Note)

    public var note: Note? {
      switch self {
      case .create: nil
      case .edit(let note): note
      }
    }

    public var isEditing: Bool {
      if case .edit = self { return true }
      return false
    }
  }

  @ObservableState
  public struct State: Equatable {
    public var mode: Mode
    public var title: String
    public var body: String
    public var isSaving = false
    public var errorMessage: String?

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
    case dismissError
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

      case .dismissError:
        state.errorMessage = nil
        return .none
      }
    }
  }
}

// MARK: - View

public struct NoteEditorView: View {
  @Bindable var store: StoreOf<NoteEditorFeature>
  @FocusState private var focusedField: Field?

  enum Field {
    case title
    case body
  }

  public init(store: StoreOf<NoteEditorFeature>) {
    self.store = store
  }

  public var body: some View {
    content
      .navigationTitle(store.mode.isEditing ? "Edit Note" : "New Note")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          store.send(.cancelButtonTapped)
        }
        .disabled(store.isSaving)
      }

      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          store.send(.saveButtonTapped)
        }
        .disabled(store.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSaving)
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
    .onAppear {
      focusedField = store.mode.isEditing ? .body : .title
    }
  }

  @ViewBuilder
  private var content: some View {
    #if os(macOS)
    VStack(alignment: .leading, spacing: 16) {
      TextField("Title", text: $store.title)
        .focused($focusedField, equals: .title)
        .font(.title2)
        .textFieldStyle(.plain)

      Divider()

      TextEditor(text: $store.body)
        .focused($focusedField, equals: .body)
        .font(.body)
        .scrollContentBackground(.hidden)

      if store.mode.isEditing {
        Divider()

        Button(role: .destructive) {
          store.send(.deleteButtonTapped)
        } label: {
          if store.isSaving {
            ProgressView()
              .controlSize(.small)
          } else {
            Text("Delete Note")
          }
        }
        .disabled(store.isSaving)
      }
    }
    .padding()
    .frame(minWidth: 400, minHeight: 300)
    #else
    Form {
      Section {
        TextField("Title", text: $store.title)
          .focused($focusedField, equals: .title)
          .font(.headline)
      }

      Section {
        TextEditor(text: $store.body)
          .focused($focusedField, equals: .body)
          .frame(minHeight: 200)
      } header: {
        Text("Content")
      }

      if store.mode.isEditing {
        Section {
          Button(role: .destructive) {
            store.send(.deleteButtonTapped)
          } label: {
            HStack {
              Spacer()
              if store.isSaving {
                ProgressView()
              } else {
                Text("Delete Note")
              }
              Spacer()
            }
          }
          .disabled(store.isSaving)
        }
      }
    }
    #endif
  }
}

// MARK: - Previews

#Preview("Create") {
  NavigationStack {
    NoteEditorView(
      store: Store(initialState: NoteEditorFeature.State(mode: .create)) {
        NoteEditorFeature()
      } withDependencies: {
        $0.notesClient = .previewValue
      }
    )
  }
}

#Preview("Edit") {
  NavigationStack {
    NoteEditorView(
      store: Store(
        initialState: NoteEditorFeature.State(
          mode: .edit(Note(title: "Sample Note", body: "This is a sample note body."))
        )
      ) {
        NoteEditorFeature()
      } withDependencies: {
        $0.notesClient = .previewValue
      }
    )
  }
}
