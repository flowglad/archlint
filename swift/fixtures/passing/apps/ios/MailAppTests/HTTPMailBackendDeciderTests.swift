// @archlint.module test
// @archlint.domain backend.http
import PropertyBased
import Testing
import XCTest

final class HTTPMailBackendDeciderTests: XCTestCase {
  func testPath() {
    XCTAssertEqual(HTTPMailBackendDecider.decidePath(0), "/v1/accounts")
  }
}

@Test
func pathProperty() async {
  await propertyCheck(input: Gen.int(in: 0...10)) { shard in
    #expect(HTTPMailBackendDecider.decidePath(shard) == "/v1/accounts")
  }
}
