import Foundation
import Testing

@testable import IndigoFoundation

@Suite struct IndigoFoundationTests {
  @Test func testTwoPlusTwoIsFour() {
    #expect(2 + 2 == 4)
  }
}
