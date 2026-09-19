import Foundation
import HTTPRequestClient
import Testing

@testable import Core

@Suite struct APIErrorBodyTests {
  @Test func decodesWellFormedBodyWithCode() {
    let error = HTTPRequestClient.Error.badResponse(
      UUID(), 422, #"{"error":"Name is taken","code":"duplicate"}"#
    )
    let body = APIErrorBody.from(error)
    #expect(body?.error == "Name is taken")
    #expect(body?.code == "duplicate")
  }

  @Test func decodesBodyWithoutCode() {
    let error = HTTPRequestClient.Error.badResponse(
      UUID(), 400, #"{"error":"Bad request"}"#
    )
    let body = APIErrorBody.from(error)
    #expect(body?.error == "Bad request")
    #expect(body?.code == nil)
  }

  @Test func returnsNilForUndecodableBody() {
    let error = HTTPRequestClient.Error.badResponse(UUID(), 500, "boom")
    #expect(APIErrorBody.from(error) == nil)
  }

  @Test func returnsNilForNonBadResponseError() {
    struct SomeOtherError: Error {}
    #expect(APIErrorBody.from(SomeOtherError()) == nil)
  }
}
