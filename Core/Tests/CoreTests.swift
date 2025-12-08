import Foundation
import Testing

@testable import Core

@Suite struct CoreTests {
  @Test func testTwoPlusTwoIsFour() {
    #expect(2 + 2 == 4)
  }
}