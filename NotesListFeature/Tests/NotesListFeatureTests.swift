import ComposableArchitecture
import Core
import Foundation
import NoteEditorFeature
import Testing

@testable import NotesListFeature

@Suite
struct NotesListFeatureTests {
  @Test
  func stateDefaultValues() {
    let state = NotesListFeature.State()
    #expect(state.notes == [])
    #expect(state.isLoading == false)
    #expect(state.errorMessage == nil)
    #expect(state.editor == nil)
  }

  @Test @MainActor
  func onAppear_loadsNotes() async {
    let testNotes = [
      Note(title: "Note 1", body: "Body 1"),
      Note(title: "Note 2", body: "Body 2")
    ]

    let store = TestStore(
      initialState: NotesListFeature.State()
    ) {
      NotesListFeature()
    } withDependencies: {
      $0.notesClient.fetchAll = { @Sendable in testNotes }
    }
    store.exhaustivity = .off

    await store.send(.onAppear) {
      $0.isLoading = true
    }
  }

  @Test @MainActor
  func addNoteButtonTapped_presentsEditor() async {
    let store = TestStore(
      initialState: NotesListFeature.State()
    ) {
      NotesListFeature()
    }

    await store.send(.addNoteButtonTapped) {
      $0.editor = NoteEditorFeature.State(mode: .create)
    }
  }

  @Test @MainActor
  func noteSelected_presentsEditorInEditMode() async {
    let note = Note(title: "Test", body: "Body")
    var state = NotesListFeature.State()
    state.notes = [note]

    let store = TestStore(initialState: state) {
      NotesListFeature()
    }

    await store.send(.noteSelected(note)) {
      $0.editor = NoteEditorFeature.State(mode: .edit(note))
    }
  }

  @Test @MainActor
  func deleteNotes_startsDelete() async {
    let note1 = Note(title: "Note 1", body: "")
    let note2 = Note(title: "Note 2", body: "")
    var state = NotesListFeature.State()
    state.notes = [note1, note2]

    let store = TestStore(initialState: state) {
      NotesListFeature()
    } withDependencies: {
      $0.notesClient.delete = { @Sendable _ in }
      $0.notesClient.fetchAll = { @Sendable in [note2] }
    }
    store.exhaustivity = .off

    await store.send(.deleteNotes(IndexSet(integer: 0)))
  }

  @Test @MainActor
  func editorSaveCompleted_dismissesEditor() async {
    var state = NotesListFeature.State()
    state.editor = NoteEditorFeature.State(mode: .create)

    let store = TestStore(initialState: state) {
      NotesListFeature()
    } withDependencies: {
      $0.notesClient.fetchAll = { @Sendable in [] }
    }
    store.exhaustivity = .off

    await store.send(.editor(.presented(.saveCompleted(.success(()))))) {
      $0.editor = nil
    }
  }

  @Test @MainActor
  func editorDeleteCompleted_dismissesEditor() async {
    let note = Note(title: "Deleted", body: "")
    var state = NotesListFeature.State()
    state.editor = NoteEditorFeature.State(mode: .edit(note))

    let store = TestStore(initialState: state) {
      NotesListFeature()
    } withDependencies: {
      $0.notesClient.fetchAll = { @Sendable in [] }
    }
    store.exhaustivity = .off

    await store.send(.editor(.presented(.deleteCompleted(.success(()))))) {
      $0.editor = nil
    }
  }

  @Test @MainActor
  func editorDismiss_clearsEditor() async {
    var state = NotesListFeature.State()
    state.editor = NoteEditorFeature.State(mode: .create)

    let store = TestStore(initialState: state) {
      NotesListFeature()
    }

    await store.send(.editor(.dismiss)) {
      $0.editor = nil
    }
  }

  @Test @MainActor
  func dismissError_clearsErrorMessage() async {
    var state = NotesListFeature.State()
    state.errorMessage = "Some error"

    let store = TestStore(initialState: state) {
      NotesListFeature()
    }

    await store.send(.dismissError) {
      $0.errorMessage = nil
    }
  }
}
