import Foundation
import Testing

@testable import Components

@Suite struct ComponentsTests {
  @Test func testTwoPlusTwoIsFour() {
    #expect(2 + 2 == 4)
  }
}