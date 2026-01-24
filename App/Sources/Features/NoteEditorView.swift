import ComposableArchitecture
import Core
import SwiftUI

struct NoteEditorView: View {
  @Bindable var store: StoreOf<NoteEditorFeature>
  @FocusState private var focusedField: Field?

  enum Field {
    case title
    case body
  }

  var body: some View {
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
    .alert("Error", isPresented: .constant(store.errorMessage != nil)) {
      Button("OK") {}
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
