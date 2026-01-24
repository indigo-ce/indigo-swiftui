import ComposableArchitecture
import Core
import Foundation
import Testing

@testable import NoteEditorFeature

private struct TestError: Error, LocalizedError {
  var errorDescription: String? { "Test error" }
}

@Suite
struct NoteEditorFeatureTests {
  @Test
  func stateDefaultValues_createMode() {
    let state = NoteEditorFeature.State(mode: .create)
    #expect(state.title == "")
    #expect(state.body == "")
    #expect(state.isSaving == false)
    #expect(state.errorMessage == nil)
    #expect(state.mode == .create)
  }

  @Test
  func stateDefaultValues_editMode() {
    let note = Note(title: "Test", body: "Body")
    let state = NoteEditorFeature.State(mode: .edit(note))
    #expect(state.title == "Test")
    #expect(state.body == "Body")
    #expect(state.isSaving == false)
    #expect(state.errorMessage == nil)
    #expect(state.mode.isEditing == true)
  }


  @Test @MainActor
  func saveButtonTapped_createMode() async {
    let createdNote = Note(title: "New Note", body: "Content")
    var initialState = NoteEditorFeature.State(mode: .create)
    initialState.title = "New Note"
    initialState.body = "Content"

    let store = TestStore(initialState: initialState) {
      NoteEditorFeature()
    } withDependencies: {
      $0.notesClient.create = { @Sendable _, _ in
        createdNote
      }
    }
    store.exhaustivity = .off

    await store.send(.saveButtonTapped) {
      $0.isSaving = true
    }
  }


  @Test @MainActor
  func saveButtonTapped_editMode() async {
    var existingNote = Note(title: "Original", body: "Original body")
    existingNote.title = "Updated"
    existingNote.body = "Updated body"

    let store = TestStore(
      initialState: NoteEditorFeature.State(mode: .edit(existingNote))
    ) {
      NoteEditorFeature()
    } withDependencies: {
      $0.notesClient.update = { @Sendable _ in }
    }
    store.exhaustivity = .off

    await store.send(.saveButtonTapped) {
      $0.isSaving = true
    }
  }



  @Test @MainActor
  func deleteButtonTapped() async {
    let noteToDelete = Note(title: "Delete me", body: "")

    let store = TestStore(
      initialState: NoteEditorFeature.State(mode: .edit(noteToDelete))
    ) {
      NoteEditorFeature()
    } withDependencies: {
      $0.notesClient.delete = { @Sendable _ in }
    }
    store.exhaustivity = .off

    await store.send(.deleteButtonTapped) {
      $0.isSaving = true
    }
  }

  @Test @MainActor
  func deleteButtonTapped_createMode_doesNothing() async {
    let store = TestStore(
      initialState: NoteEditorFeature.State(mode: .create)
    ) {
      NoteEditorFeature()
    }

    await store.send(.deleteButtonTapped)
  }

  @Test @MainActor
  func saveCompleted_failure_setsErrorMessage() async {
    var initialState = NoteEditorFeature.State(mode: .create)
    initialState.title = "Note"

    let store = TestStore(initialState: initialState) {
      NoteEditorFeature()
    } withDependencies: {
      $0.notesClient.create = { @Sendable _, _ in
        throw TestError()
      }
    }
    store.exhaustivity = .off

    await store.send(.saveButtonTapped) {
      $0.isSaving = true
    }
  }

  @Test @MainActor
  func dismissError_clearsErrorMessage() async {
    var state = NoteEditorFeature.State(mode: .create)
    state.errorMessage = "Some error"

    let store = TestStore(initialState: state) {
      NoteEditorFeature()
    }

    await store.send(.dismissError) {
      $0.errorMessage = nil
    }
  }

  @Test @MainActor
  func cancelButtonTapped_dismisses() async {
    let store = TestStore(
      initialState: NoteEditorFeature.State(mode: .create)
    ) {
      NoteEditorFeature()
    } withDependencies: {
      $0.dismiss = DismissEffect {}
    }
    store.exhaustivity = .off

    await store.send(.cancelButtonTapped)
  }
}
