import Foundation
import Testing

@Suite struct IndigoFoundationTests {
  @Test func testTwoPlusTwoIsFour() {
    #expect(2 + 2 == 4)
  }
}
