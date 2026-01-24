import ComposableArchitecture
import Core
import SwiftUI

struct NotesListView: View {
  @Bindable var store: StoreOf<NotesListFeature>

  var body: some View {
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

#Preview {
  NotesListView(
    store: Store(initialState: NotesListFeature.State()) {
      NotesListFeature()
    } withDependencies: {
      $0.notesClient = .previewValue
    }
  )
}
